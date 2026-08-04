import Foundation

/// One box on a scorebook page: everything that happened to one batter in one
/// plate appearance, including what became of them afterwards.
///
/// A paper scorebook fills the little diamond in over time — you write `1B` when
/// the ball drops, then trace the runner around as later batters move them, and
/// you only know it was a run when they touch the plate two batters later. This
/// carries the same idea: the cell is created when the at-bat ends and then
/// keeps being updated until the half-inning is over.
struct ScorebookCell: Identifiable, Hashable, Sendable {
    /// The plate appearance's id, so a cell stays stable across rebuilds.
    var id: UUID
    var slot: Int
    var inning: Int
    var batterID: UUID
    /// What a scorer would write in the box: `6-4-3 DP`, `F9`, `ꓘ`, `BB`, `3U`.
    var notation: String
    var outcome: PlayOutcome
    var rbis: Int
    var pitchCount: Int

    /// Furthest base reached and still occupied. nil once they've scored or
    /// been retired.
    var reached: Base?
    var didScore: Bool = false
    /// Retired somewhere after reaching base — caught stealing, doubled off, or
    /// erased by a later fielder's choice.
    var wasRetiredOnBases: Bool = false
    /// Still standing on a base when the third out was made.
    var wasLeftOnBase: Bool = false
    /// Which out of the half-inning the batter made, if they made one. Scorers
    /// number these in the corner of the box.
    var outNumber: Int?

    /// True when the batter never reached base to begin with.
    var batterWasRetired: Bool { outNumber != nil }

    /// How far around the diamond to shade, 0...4. Drives the cell's mini
    /// diamond: one side per base, all four when the run scores.
    var basesAdvanced: Int {
        if didScore { return 4 }
        return reached?.rawValue ?? 0
    }

    var isHit: Bool { outcome.isHit }
}

/// One batting-order slot's row across the whole game.
struct ScorebookRow: Identifiable, Hashable, Sendable {
    /// Zero-based batting order position.
    var slot: Int
    /// Everyone who has batted in this slot, in the order they appeared, so a
    /// pinch hitter shows up under the starter rather than replacing them.
    var playerIDs: [UUID]
    /// Cells keyed by inning. A slot can come up twice in one inning when the
    /// order bats around, hence the array.
    var cellsByInning: [Int: [ScorebookCell]]

    var id: Int { slot }

    func cells(inning: Int) -> [ScorebookCell] {
        cellsByInning[inning] ?? []
    }
}

/// One team's scorebook page.
struct ScorebookPage: Hashable, Sendable {
    var side: Side
    var rows: [ScorebookRow]
    /// Innings this team has actually come to bat in, always at least one.
    var innings: [Int]
    /// Runs, hits, errors and men left on base per inning, for the page footer.
    var runsByInning: [Int: Int]
    var hitsByInning: [Int: Int]
    var leftOnBaseByInning: [Int: Int]

    var totalRuns: Int { runsByInning.values.reduce(0, +) }
    var totalHits: Int { hitsByInning.values.reduce(0, +) }
    var totalLeftOnBase: Int { leftOnBaseByInning.values.reduce(0, +) }
}

/// Builds scorebook pages by replaying the log through the same engine the live
/// screen uses.
///
/// It deliberately does not re-implement any baseball rules. It watches what
/// the engine does to the bases after each event and writes that down, which is
/// exactly what a human scorer does.
enum ScorebookBuilder {

    static func build(document: GameDocument) -> SideValues<ScorebookPage> {
        var away = PageBuilder(side: .away)
        var home = PageBuilder(side: .home)
        var state = ScoringEngine.initialState(document: document)

        // Seed the rows from the starting lineups so an unbatted slot still has
        // a row with a name on it.
        away.seed(lineup: document.startingLineups.away)
        home.seed(lineup: document.startingLineups.home)

        for recorded in ScoringEngine.resolved(document.events) {
            let before = state
            let result = ScoringEngine.apply(recorded.event, to: state, document: document)
            state = result.state

            // The half-inning the event belongs to is the one it started in —
            // the engine may have flipped sides by the time it returns.
            if before.battingSide == .away {
                away.absorb(event: recorded.event, result: result, before: before, after: state)
            } else {
                home.absorb(event: recorded.event, result: result, before: before, after: state)
            }
        }

        // The game may have stopped mid-inning; anyone still aboard is stranded
        // for the purposes of the page.
        away.closeOut()
        home.closeOut()

        return SideValues(
            away: away.page(lineScore: state.lineScore),
            home: home.page(lineScore: state.lineScore)
        )
    }

    // MARK: - Per-team accumulation

    private struct PageBuilder {
        let side: Side

        private var cells: [ScorebookCell] = []
        /// Runner id → index into `cells`, for everyone currently on base whose
        /// box is still open.
        private var openCells: [UUID: Int] = [:]
        private var slotOwners: [Int: [UUID]] = [:]
        private var runsByInning: [Int: Int] = [:]
        private var hitsByInning: [Int: Int] = [:]
        private var leftOnBaseByInning: [Int: Int] = [:]
        private var innings: Set<Int> = []

        init(side: Side) {
            self.side = side
        }

        mutating func seed(lineup: LineupState) {
            for (index, slot) in lineup.slots.enumerated() {
                slotOwners[index] = [slot.playerID]
            }
        }

        mutating func absorb(
            event: GameEvent,
            result: ApplyResult,
            before: GameState,
            after: GameState
        ) {
            if let appearance = result.plateAppearance {
                open(appearance, before: before, after: after)
            }

            // A pinch runner inherits the box of the runner they replace — the
            // starter keeps credit for reaching, the sub for whatever follows.
            if case .substitution(let substitution) = event,
               substitution.kind == .pinchRunner,
               substitution.side == side,
               let base = substitution.runnerBase,
               let replaced = before.bases[base]?.playerID,
               let index = openCells[replaced] {
                openCells[replaced] = nil
                openCells[substitution.incomingPlayerID] = index
            }

            advanceRunners(after: after)
            creditRuns(result.runs, inning: before.inning)

            // Stranding is settled first, because ending the half clears the
            // bases: without this, every man left on would look like he'd been
            // thrown out. Whoever is still open after that really did vanish.
            if result.halfInningEnded {
                strand(ids: result.strandedRunnerIDs, inning: before.inning)
            }
            retireVanishedRunners(before: before, after: after, result: result)
        }

        /// Opens a new box for a completed plate appearance.
        private mutating func open(
            _ appearance: PlateAppearanceResult,
            before: GameState,
            after: GameState
        ) {
            let inning = appearance.inning
            innings.insert(inning)

            let slot = appearance.battingSlot
            var owners = slotOwners[slot] ?? []
            if !owners.contains(appearance.batterID) {
                owners.append(appearance.batterID)
            }
            slotOwners[slot] = owners

            var cell = ScorebookCell(
                id: appearance.id,
                slot: slot,
                inning: inning,
                batterID: appearance.batterID,
                notation: appearance.notation,
                outcome: appearance.outcome,
                rbis: appearance.rbis,
                pitchCount: appearance.pitchCount,
                reached: nil
            )

            // Where the batter stands now that the dust has settled.
            if let base = base(of: appearance.batterID, in: after.bases) {
                cell.reached = base
            } else if appearance.runs.contains(where: { $0.runnerID == appearance.batterID }) {
                cell.didScore = true
            } else {
                // Nowhere to be found: they were retired on the play. On a
                // double play the batter is the back end of the relay, so they
                // are the last out the play recorded, not the first.
                cell.outNumber = min(3, before.outs + max(1, appearance.outsRecorded))
            }

            if appearance.outcome.isHit {
                hitsByInning[inning, default: 0] += 1
            }

            cells.append(cell)
            if cell.reached != nil {
                openCells[appearance.batterID] = cells.count - 1
            }
        }

        /// Every runner still aboard gets their box updated to the furthest
        /// base they now hold.
        private mutating func advanceRunners(after: GameState) {
            for base in after.bases.occupied {
                guard
                    let runner = after.bases[base],
                    let index = openCells[runner.playerID]
                else { continue }
                let current = cells[index].reached?.rawValue ?? 0
                if base.rawValue > current {
                    cells[index].reached = base
                }
            }
        }

        private mutating func creditRuns(_ runs: [ScoredRun], inning: Int) {
            guard !runs.isEmpty else { return }
            innings.insert(inning)
            runsByInning[inning, default: 0] += runs.count

            for run in runs {
                guard let index = openCells[run.runnerID] else { continue }
                cells[index].didScore = true
                cells[index].reached = nil
                openCells[run.runnerID] = nil
            }
        }

        /// A tracked runner who is no longer on base and didn't score was
        /// retired — caught stealing, doubled off, forced at second.
        private mutating func retireVanishedRunners(
            before: GameState,
            after: GameState,
            result: ApplyResult
        ) {
            guard result.outsRecorded > 0 || before.bases != after.bases else { return }

            let stillOn = Set(after.bases.occupied.compactMap { after.bases[$0]?.playerID })
            let scored = Set(result.runs.map(\.runnerID))

            // Snapshot before mutating, so the loop isn't walking the same
            // storage it's editing.
            for (playerID, index) in openCells.map({ ($0.key, $0.value) }) {
                guard !stillOn.contains(playerID), !scored.contains(playerID) else { continue }
                cells[index].wasRetiredOnBases = true
                openCells[playerID] = nil
            }
        }

        /// Third out: the runners the engine says were still standing there are
        /// left on base.
        private mutating func strand(ids: [UUID], inning: Int) {
            var stranded = 0
            for id in ids {
                guard let index = openCells[id] else { continue }
                cells[index].wasLeftOnBase = true
                openCells[id] = nil
                stranded += 1
            }
            if stranded > 0 {
                leftOnBaseByInning[inning, default: 0] += stranded
            }
        }

        /// The log ran out mid-inning. Runners still aboard are left exactly as
        /// they are — their box shows them partway round, which is the truth
        /// while the inning is still going.
        mutating func closeOut() {
            openCells.removeAll()
        }

        private func base(of playerID: UUID, in bases: Bases) -> Base? {
            bases.occupied.first { bases[$0]?.playerID == playerID }
        }

        func page(lineScore: [InningScore]) -> ScorebookPage {
            var rows: [ScorebookRow] = []
            let slots = slotOwners.keys.sorted()

            for slot in slots {
                var byInning: [Int: [ScorebookCell]] = [:]
                for cell in cells where cell.slot == slot {
                    byInning[cell.inning, default: []].append(cell)
                }
                rows.append(
                    ScorebookRow(
                        slot: slot,
                        playerIDs: slotOwners[slot] ?? [],
                        cellsByInning: byInning
                    )
                )
            }

            // Runs come from the line score rather than the boxes, so a run
            // that scored on a wild pitch or a steal of home still lands in the
            // right column.
            var runs: [Int: Int] = [:]
            for (index, score) in lineScore.enumerated() {
                if let value = score[side], value > 0 {
                    runs[index + 1] = value
                }
            }

            let played = Set(
                lineScore.enumerated()
                    .filter { $0.element[side] != nil }
                    .map { $0.offset + 1 }
            )
            let columns = innings.union(played).union([1]).sorted()

            return ScorebookPage(
                side: side,
                rows: rows,
                innings: columns,
                runsByInning: runs.isEmpty ? runsByInning : runs,
                hitsByInning: hitsByInning,
                leftOnBaseByInning: leftOnBaseByInning
            )
        }
    }
}
