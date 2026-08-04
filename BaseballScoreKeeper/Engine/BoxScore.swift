import Foundation

enum PitcherDecision: String, Codable, Hashable, Sendable {
    case win
    case loss
    case save

    var abbreviation: String {
        switch self {
        case .win: "W"
        case .loss: "L"
        case .save: "S"
        }
    }
}

struct BattingLine: Identifiable, Hashable, Sendable {
    var player: Player
    var side: Side
    var battingSlot: Int
    var position: Position
    var atBats = 0
    var runs = 0
    var hits = 0
    var rbis = 0
    var walks = 0
    var strikeouts = 0
    var doubles = 0
    var triples = 0
    var homeRuns = 0
    var stolenBases = 0
    var caughtStealing = 0
    var leftOnBase = 0
    /// Every plate appearance in order, so the row can show "K, F5, 6-3".
    var notations: [String] = []
    /// True when this player came off the bench for the slot.
    var isSubstitute = false

    var id: UUID { player.id }

    var summary: String {
        Notation.battingLine(hits: hits, atBats: atBats)
    }

    /// "0-for-3 · K, F5, 6-3" — the dense row from the box score design.
    var detailLine: String {
        let marks = notations.joined(separator: ", ")
        return marks.isEmpty ? summary : "\(summary) · \(marks)"
    }

    var average: Double {
        atBats > 0 ? Double(hits) / Double(atBats) : 0
    }
}

struct PitchingLine: Identifiable, Hashable, Sendable {
    var player: Player
    var side: Side
    var outsRecorded = 0
    var battersFaced = 0
    var hits = 0
    var runs = 0
    var earnedRuns = 0
    var walks = 0
    var strikeouts = 0
    var homeRuns = 0
    var pitches = 0
    var strikes = 0
    var decision: PitcherDecision?
    var isStarter = false
    /// Score differential for this pitcher's team when they entered.
    var leadOnEntry = 0
    var enteredAtEventIndex = 0
    var finishedGame = false

    var id: UUID { player.id }

    var inningsPitched: String {
        Notation.inningsPitched(outs: outsRecorded)
    }

    var earnedRunAverage: Double {
        guard outsRecorded > 0 else { return 0 }
        return Double(earnedRuns) * 27.0 / Double(outsRecorded)
    }
}

struct TeamTotals: Hashable, Sendable {
    var runs = 0
    var hits = 0
    var errors = 0
    var leftOnBase = 0
}

struct BoxScore: Sendable {
    var lineScore: [InningScore]
    var totals: SideValues<TeamTotals>
    var batting: SideValues<[BattingLine]>
    var pitching: SideValues<[PitchingLine]>
    var teams: SideValues<TeamRoster>
    var isFinal: Bool

    var winningSide: Side? {
        guard isFinal else { return nil }
        if totals.away.runs > totals.home.runs { return .away }
        if totals.home.runs > totals.away.runs { return .home }
        return nil
    }
}

/// Rebuilds a full box score by replaying the event log through the engine.
///
/// This is deliberately a separate pass from `GameStore`'s live state: the
/// store only needs "what is true now", while this needs the whole history.
enum BoxScoreBuilder {

    static func build(document: GameDocument) -> BoxScore {
        var state = ScoringEngine.initialState(document: document)

        var batting: [UUID: BattingLine] = [:]
        var pitching: [UUID: PitchingLine] = [:]
        var battingOrder: [UUID] = []
        var pitchingOrder: SideValues<[UUID]> = SideValues(repeating: [])

        // Score after each event, plus who was on the mound for each side, so
        // decisions can be worked out at the end.
        var snapshots: [Snapshot] = []

        registerStarters(
            document: document,
            state: state,
            batting: &batting,
            pitching: &pitching,
            battingOrder: &battingOrder,
            pitchingOrder: &pitchingOrder
        )

        for (index, recorded) in document.events.enumerated() {
            let pitcherBefore = state.currentPitcherID
            let fieldingSideBefore = state.fieldingSide
            let basesBefore = state.bases

            registerNewFaces(
                document: document,
                state: state,
                eventIndex: index,
                batting: &batting,
                pitching: &pitching,
                battingOrder: &battingOrder,
                pitchingOrder: &pitchingOrder
            )

            let result = ScoringEngine.apply(recorded.event, to: state, document: document)

            switch recorded.event {
            case .pitch(let pitch):
                if let pitcherBefore {
                    pitching[pitcherBefore]?.pitches += 1
                    if pitch.outcome.isStrike || pitch.outcome == .inPlay {
                        pitching[pitcherBefore]?.strikes += 1
                    }
                }

            case .stolenBase(let base):
                if let runner = basesBefore[base] {
                    batting[runner.playerID]?.stolenBases += 1
                }

            case .caughtStealing(let base):
                if let runner = basesBefore[base] {
                    batting[runner.playerID]?.caughtStealing += 1
                }

            default:
                break
            }

            if let appearance = result.plateAppearance {
                record(appearance, into: &batting, pitching: &pitching, document: document)
            }

            // Runs credit the runner who scored and the pitcher responsible.
            for run in result.runs {
                batting[run.runnerID]?.runs += 1
                pitching[run.responsiblePitcherID]?.runs += 1
                if run.isEarned {
                    pitching[run.responsiblePitcherID]?.earnedRuns += 1
                }
            }

            // Outs from pickoffs and caught stealing still count as innings
            // pitched even though no plate appearance ended.
            if result.plateAppearance == nil, result.outsRecorded > 0, let pitcherBefore {
                pitching[pitcherBefore]?.outsRecorded += result.outsRecorded
            }

            state = result.state

            snapshots.append(
                Snapshot(
                    away: state.awayRuns,
                    home: state.homeRuns,
                    pitchers: SideValues(
                        away: fieldingSideBefore == .away
                            ? pitcherBefore
                            : state.lineups.away.currentPitcherID,
                        home: fieldingSideBefore == .home
                            ? pitcherBefore
                            : state.lineups.home.currentPitcherID
                    )
                )
            )
        }

        // A substitution made after the last pitch still earns a line.
        registerNewFaces(
            document: document,
            state: state,
            eventIndex: document.events.count,
            batting: &batting,
            pitching: &pitching,
            battingOrder: &battingOrder,
            pitchingOrder: &pitchingOrder
        )

        // Runners stranded when the game ended are still left on base.
        var totals = SideValues(
            away: TeamTotals(
                runs: state.awayRuns,
                hits: state.hits.away,
                errors: state.errors.away,
                leftOnBase: state.leftOnBase.away
            ),
            home: TeamTotals(
                runs: state.homeRuns,
                hits: state.hits.home,
                errors: state.errors.home,
                leftOnBase: state.leftOnBase.home
            )
        )
        totals[state.battingSide].leftOnBase += state.bases.runnerCount

        markFinishers(pitching: &pitching, order: pitchingOrder)

        if state.isFinal {
            assignDecisions(
                snapshots: snapshots,
                pitching: &pitching,
                order: pitchingOrder,
                regulationInnings: document.rules.regulationInnings
            )
        }

        let battingBySide = splitBatting(batting, order: battingOrder)
        let pitchingBySide = SideValues(
            away: pitchingOrder.away.compactMap { pitching[$0] },
            home: pitchingOrder.home.compactMap { pitching[$0] }
        )

        return BoxScore(
            lineScore: state.lineScore,
            totals: totals,
            batting: battingBySide,
            pitching: pitchingBySide,
            teams: document.teams,
            isFinal: state.isFinal
        )
    }

    // MARK: - Snapshots

    private struct Snapshot {
        var away: Int
        var home: Int
        var pitchers: SideValues<UUID?>
    }

    // MARK: - Roster bookkeeping

    private static func registerStarters(
        document: GameDocument,
        state: GameState,
        batting: inout [UUID: BattingLine],
        pitching: inout [UUID: PitchingLine],
        battingOrder: inout [UUID],
        pitchingOrder: inout SideValues<[UUID]>
    ) {
        for side in Side.allCases {
            let lineup = state.lineups[side]
            for (index, slot) in lineup.slots.enumerated() {
                guard let player = document.player(id: slot.playerID) else { continue }
                batting[slot.playerID] = BattingLine(
                    player: player,
                    side: side,
                    battingSlot: index,
                    position: slot.position
                )
                battingOrder.append(slot.playerID)
            }
            if let pitcherID = lineup.currentPitcherID, let player = document.player(id: pitcherID) {
                var line = PitchingLine(player: player, side: side)
                line.isStarter = true
                pitching[pitcherID] = line
                pitchingOrder[side].append(pitcherID)
            }
        }
    }

    /// Picks up anyone who entered via substitution since the last event.
    private static func registerNewFaces(
        document: GameDocument,
        state: GameState,
        eventIndex: Int,
        batting: inout [UUID: BattingLine],
        pitching: inout [UUID: PitchingLine],
        battingOrder: inout [UUID],
        pitchingOrder: inout SideValues<[UUID]>
    ) {
        for side in Side.allCases {
            let lineup = state.lineups[side]

            for (index, slot) in lineup.slots.enumerated() where batting[slot.playerID] == nil {
                guard let player = document.player(id: slot.playerID) else { continue }
                var line = BattingLine(
                    player: player,
                    side: side,
                    battingSlot: index,
                    position: slot.position
                )
                line.isSubstitute = true
                batting[slot.playerID] = line
                battingOrder.append(slot.playerID)
            }

            if let pitcherID = lineup.currentPitcherID, pitching[pitcherID] == nil {
                guard let player = document.player(id: pitcherID) else { continue }
                var line = PitchingLine(player: player, side: side)
                line.enteredAtEventIndex = eventIndex
                line.leadOnEntry = (side == .away ? state.awayRuns - state.homeRuns : state.homeRuns - state.awayRuns)
                pitching[pitcherID] = line
                pitchingOrder[side].append(pitcherID)
            }
        }
    }

    private static func record(
        _ appearance: PlateAppearanceResult,
        into batting: inout [UUID: BattingLine],
        pitching: inout [UUID: PitchingLine],
        document: GameDocument
    ) {
        let outcome = appearance.outcome

        if batting[appearance.batterID] != nil {
            batting[appearance.batterID]?.notations.append(appearance.notation)
            batting[appearance.batterID]?.rbis += appearance.rbis

            if outcome.isAtBat {
                batting[appearance.batterID]?.atBats += 1
            }
            if outcome.isHit {
                batting[appearance.batterID]?.hits += 1
                switch outcome.hitKind {
                case .double: batting[appearance.batterID]?.doubles += 1
                case .triple: batting[appearance.batterID]?.triples += 1
                case .homeRun: batting[appearance.batterID]?.homeRuns += 1
                default: break
                }
            }
            if case .walk = outcome {
                batting[appearance.batterID]?.walks += 1
            }
            if case .strikeout = outcome {
                batting[appearance.batterID]?.strikeouts += 1
            }
        }

        guard pitching[appearance.pitcherID] != nil else { return }
        pitching[appearance.pitcherID]?.battersFaced += 1
        pitching[appearance.pitcherID]?.outsRecorded += appearance.outsRecorded
        if outcome.isHit {
            pitching[appearance.pitcherID]?.hits += 1
            if outcome.hitKind == .homeRun {
                pitching[appearance.pitcherID]?.homeRuns += 1
            }
        }
        if case .walk = outcome {
            pitching[appearance.pitcherID]?.walks += 1
        }
        if case .strikeout(_, let uncaught) = outcome, !uncaught {
            pitching[appearance.pitcherID]?.strikeouts += 1
        }
    }

    /// Groups the lines by team and orders them the way a scorebook page reads:
    /// slot one down to slot nine, each starter followed by whoever replaced
    /// them. Appearance order breaks ties so the result is deterministic.
    private static func splitBatting(
        _ batting: [UUID: BattingLine],
        order: [UUID]
    ) -> SideValues<[BattingLine]> {
        var away: [(appearance: Int, line: BattingLine)] = []
        var home: [(appearance: Int, line: BattingLine)] = []

        for (appearance, id) in order.enumerated() {
            guard let line = batting[id] else { continue }
            switch line.side {
            case .away: away.append((appearance, line))
            case .home: home.append((appearance, line))
            }
        }

        func ordered(_ entries: [(appearance: Int, line: BattingLine)]) -> [BattingLine] {
            entries
                .sorted { lhs, rhs in
                    if lhs.line.battingSlot != rhs.line.battingSlot {
                        return lhs.line.battingSlot < rhs.line.battingSlot
                    }
                    return lhs.appearance < rhs.appearance
                }
                .map { $0.line }
        }

        return SideValues(away: ordered(away), home: ordered(home))
    }

    private static func markFinishers(pitching: inout [UUID: PitchingLine], order: SideValues<[UUID]>) {
        for side in Side.allCases {
            if let last = order[side].last {
                pitching[last]?.finishedGame = true
            }
        }
    }

    // MARK: - Decisions

    /// Win, loss and save, following the rulebook closely enough for a
    /// scorebook: the decisive run is the one that gave the winner a lead they
    /// never gave back.
    private static func assignDecisions(
        snapshots: [Snapshot],
        pitching: inout [UUID: PitchingLine],
        order: SideValues<[UUID]>,
        regulationInnings: Int
    ) {
        guard let final = snapshots.last, final.away != final.home else { return }
        let winner: Side = final.away > final.home ? .away : .home
        let loser = winner.opponent

        func leadsAt(_ snapshot: Snapshot) -> Bool {
            let winnerRuns = winner == .away ? snapshot.away : snapshot.home
            let loserRuns = winner == .away ? snapshot.home : snapshot.away
            return winnerRuns > loserRuns
        }

        // Walk back to the last moment the winner was not ahead; the next
        // snapshot is where the lead was taken for good.
        var decisiveIndex = 0
        for index in stride(from: snapshots.count - 1, through: 0, by: -1) where !leadsAt(snapshots[index]) {
            decisiveIndex = index + 1
            break
        }
        guard decisiveIndex < snapshots.count else { return }
        let decisive = snapshots[decisiveIndex]

        if let losingPitcher = decisive.pitchers[loser] {
            pitching[losingPitcher]?.decision = .loss
        }

        guard var winningPitcher = decisive.pitchers[winner] else { return }

        // A starter who didn't go five gets no win; it passes to the most
        // effective reliever who followed.
        if pitching[winningPitcher]?.isStarter == true,
           (pitching[winningPitcher]?.outsRecorded ?? 0) < regulationInnings / 2 * 3 + 3 {
            let relievers = order[winner]
                .filter { $0 != winningPitcher }
                .compactMap { pitching[$0] }
            if let best = relievers.max(by: { $0.outsRecorded < $1.outsRecorded }) {
                winningPitcher = best.id
            }
        }
        pitching[winningPitcher]?.decision = .win

        // Save: finished the game, didn't win it, and either protected a lead
        // of three or fewer or threw at least three innings.
        if let closerID = order[winner].last,
           closerID != winningPitcher,
           let closer = pitching[closerID],
           closer.outsRecorded > 0 {
            let protectedSmallLead = closer.leadOnEntry > 0 && closer.leadOnEntry <= 3
            if protectedSmallLead || closer.outsRecorded >= 9 {
                pitching[closerID]?.decision = .save
            }
        }
    }
}
