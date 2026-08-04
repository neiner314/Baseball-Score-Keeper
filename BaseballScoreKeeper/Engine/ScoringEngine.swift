import Foundation

/// One run crossing the plate, with everything the pitching line needs.
struct ScoredRun: Codable, Hashable, Sendable {
    var runnerID: UUID
    var responsiblePitcherID: UUID
    var isEarned: Bool
    var battedInBy: UUID?
}

/// A completed plate appearance, emitted the moment an at-bat resolves.
/// The box score is built by collecting these.
struct PlateAppearanceResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var batterID: UUID
    var pitcherID: UUID
    var battingSide: Side
    var inning: Int
    var half: Half
    var outcome: PlayOutcome
    var rbis: Int
    var runs: [ScoredRun]
    var notation: String
    var pitchCount: Int
    var outsRecorded: Int

    init(
        id: UUID = UUID(),
        batterID: UUID,
        pitcherID: UUID,
        battingSide: Side,
        inning: Int,
        half: Half,
        outcome: PlayOutcome,
        rbis: Int,
        runs: [ScoredRun],
        notation: String,
        pitchCount: Int,
        outsRecorded: Int
    ) {
        self.id = id
        self.batterID = batterID
        self.pitcherID = pitcherID
        self.battingSide = battingSide
        self.inning = inning
        self.half = half
        self.outcome = outcome
        self.rbis = rbis
        self.runs = runs
        self.notation = notation
        self.pitchCount = pitchCount
        self.outsRecorded = outsRecorded
    }
}

/// Everything one event changed. The store keeps the state; the box score
/// builder keeps the rest.
struct ApplyResult: Sendable {
    var state: GameState
    var plateAppearance: PlateAppearanceResult?
    var runs: [ScoredRun] = []
    var outsRecorded: Int = 0
    var halfInningEnded: Bool = false
    var gameEnded: Bool = false
    /// Short line for the announcer and the post-play toast: "Strike two",
    /// "Ground out, 6-3", "Base hit, run scores".
    var headline: String = ""
}

/// Pure, deterministic application of events to state.
///
/// Nothing here mutates shared state or touches the UI: `apply` takes a state
/// and returns a new one, which is what makes undo a matter of dropping the
/// last event and replaying.
enum ScoringEngine {

    // MARK: - Setup

    static func initialState(document: GameDocument) -> GameState {
        var state = GameState(lineups: document.startingLineups)
        state.ensureLineScoreDepth()
        return state
    }

    /// Replays an entire event log from scratch.
    static func replay(document: GameDocument) -> GameState {
        var state = initialState(document: document)
        for recorded in document.events {
            state = apply(recorded.event, to: state, document: document).state
        }
        return state
    }

    // MARK: - Apply

    static func apply(_ event: GameEvent, to state: GameState, document: GameDocument) -> ApplyResult {
        var working = state

        // Only real game action marks a half-inning as having been played —
        // otherwise a substitution after the top of the ninth would turn the
        // home team's unplayed half from "X" into a zero.
        switch event {
        case .substitution, .endGame, .endHalfInning:
            break
        default:
            working.markHalfPlayed()
        }

        switch event {
        case .pitch(let pitch):
            return applyPitch(pitch, to: working, document: document)
        case .play(let outcome, let manualAdvances):
            return applyPlay(outcome, manualAdvances: manualAdvances, to: working, document: document)
        case .stolenBase(let base):
            return applyStolenBase(from: base, to: working, document: document)
        case .caughtStealing(let base):
            return applyRunnerRetired(from: base, to: working, document: document, headline: "Caught stealing")
        case .pickoff(let base):
            return applyRunnerRetired(from: base, to: working, document: document, headline: "Picked off")
        case .balk:
            return applyBulkAdvance(to: working, document: document, headline: "Balk")
        case .wildPitchAdvance:
            return applyBulkAdvance(to: working, document: document, headline: "Wild pitch")
        case .passedBallAdvance:
            return applyBulkAdvance(to: working, document: document, headline: "Passed ball")
        case .defensiveIndifference(let base):
            return applyStolenBase(from: base, to: working, document: document, isIndifference: true)
        case .substitution(let substitution):
            return applySubstitution(substitution, to: working, document: document)
        case .endHalfInning:
            var result = ApplyResult(state: working, plateAppearance: nil)
            result.state.outs = 3
            finishHalfInningIfNeeded(&result, document: document)
            result.headline = "End of half"
            return result
        case .endGame:
            var result = ApplyResult(state: working, plateAppearance: nil)
            result.state.isFinal = true
            result.gameEnded = true
            result.headline = "Final"
            return result
        }
    }

    // MARK: - Pitches

    private static func applyPitch(_ pitch: Pitch, to state: GameState, document: GameDocument) -> ApplyResult {
        var working = state
        working.currentAtBatPitches.append(pitch)

        switch pitch.outcome {
        case .inPlay:
            // The count doesn't move; the scorer owes us a play next.
            var result = ApplyResult(state: working, plateAppearance: nil)
            result.headline = "In play"
            return result

        case .hitByPitch:
            return applyPlay(.hitByPitch, manualAdvances: nil, to: working, document: document)

        case .ball:
            working.balls += 1
            if working.balls >= 4 {
                return applyPlay(.walk(intentional: false), manualAdvances: nil, to: working, document: document)
            }
            var result = ApplyResult(state: working, plateAppearance: nil)
            result.headline = countHeadline(balls: working.balls, strikes: working.strikes, said: pitch.outcome.spokenLabel)
            return result

        case .wildPitch, .passedBall:
            working.balls += 1
            if working.balls >= 4 {
                // Ball four already awards the batter first and pushes the
                // forced runners; advancing twice would overcount.
                return applyPlay(.walk(intentional: false), manualAdvances: nil, to: working, document: document)
            }
            // Runners move up a base on their own.
            var result = applyBulkAdvance(
                to: working,
                document: document,
                headline: pitch.outcome.spokenLabel.capitalizedFirst
            )
            if result.runs.isEmpty && working.bases.isEmpty {
                result.headline = countHeadline(
                    balls: working.balls,
                    strikes: working.strikes,
                    said: pitch.outcome.spokenLabel
                )
            }
            return result

        case .calledStrike, .swingingStrike:
            working.strikes += 1
            if working.strikes >= 3 {
                let looking = pitch.outcome == .calledStrike
                return applyPlay(
                    .strikeout(looking: looking, uncaught: false),
                    manualAdvances: nil,
                    to: working,
                    document: document
                )
            }
            var result = ApplyResult(state: working, plateAppearance: nil)
            result.headline = countHeadline(balls: working.balls, strikes: working.strikes, said: pitch.outcome.spokenLabel)
            return result

        case .foul:
            // A foul with two strikes keeps the count where it is.
            if working.strikes < 2 {
                working.strikes += 1
            }
            var result = ApplyResult(state: working, plateAppearance: nil)
            result.headline = countHeadline(balls: working.balls, strikes: working.strikes, said: "foul")
            return result
        }
    }

    private static func countHeadline(balls: Int, strikes: Int, said: String) -> String {
        "\(said.capitalizedFirst) — \(balls)-\(strikes)"
    }

    // MARK: - Plays

    private static func applyPlay(
        _ outcome: PlayOutcome,
        manualAdvances: [ManualAdvance]?,
        to state: GameState,
        document: GameDocument
    ) -> ApplyResult {
        var working = state
        let battingSide = working.battingSide
        guard
            let batterID = working.currentBatterID,
            let pitcherID = working.currentPitcherID
        else {
            return ApplyResult(state: working, plateAppearance: nil)
        }

        let resolution = resolveAdvances(
            outcome: outcome,
            manualAdvances: manualAdvances,
            bases: working.bases,
            batter: Runner(
                playerID: batterID,
                responsiblePitcherID: pitcherID,
                reachedOnError: outcome.isErrorPlay
            )
        )

        let outsRecorded = resolution.outs
        let outsAfter = working.outs + outsRecorded

        // Rule 5.08(a): no run scores when the third out retires the batter
        // before first or is a force out. Every outcome that records an out
        // here is one of those, so the third out wipes the play's runs.
        let runsCancelled = outsAfter >= 3 && outcome.baseOuts > 0
        let crossingRunners = runsCancelled ? [] : resolution.scored

        if outcome.isErrorPlay {
            // The out that should have been made — runs past it are unearned.
            working.phantomOuts += 1
            working.errors[working.fieldingSide] += 1
        }

        var scoredRuns: [ScoredRun] = []
        for (index, runner) in crossingRunners.enumerated() {
            let outsWhenScored = working.outs + working.phantomOuts + index
            let isEarned = !runner.reachedOnError && outsWhenScored < 3
            scoredRuns.append(
                ScoredRun(
                    runnerID: runner.playerID,
                    responsiblePitcherID: runner.responsiblePitcherID,
                    isEarned: isEarned,
                    battedInBy: outcome.earnsRBI ? batterID : nil
                )
            )
        }

        working.bases = resolution.bases
        working.outs = min(3, outsAfter)
        working.addRuns(scoredRuns.count, to: battingSide)

        if outcome.isHit {
            working.hits[battingSide] += 1
        }

        let rbis = outcome.earnsRBI ? scoredRuns.count : 0
        let notation = Notation.text(
            for: outcome,
            detail: document.settings.notationDetail,
            rbis: rbis
        )

        let plateAppearance = PlateAppearanceResult(
            batterID: batterID,
            pitcherID: pitcherID,
            battingSide: battingSide,
            inning: working.inning,
            half: working.half,
            outcome: outcome,
            rbis: rbis,
            runs: scoredRuns,
            notation: notation,
            pitchCount: working.currentAtBatPitches.count,
            outsRecorded: outsRecorded
        )

        working.lineups[battingSide].advanceBatter()
        working.resetCount()

        var result = ApplyResult(state: working, plateAppearance: plateAppearance)
        result.runs = scoredRuns
        result.outsRecorded = outsRecorded
        result.headline = headline(for: outcome, runs: scoredRuns.count, cancelled: runsCancelled)

        finishHalfInningIfNeeded(&result, document: document)
        checkGameEnd(&result, document: document)
        return result
    }

    // MARK: - Advancement

    private struct AdvanceResolution {
        var bases: Bases
        var scored: [Runner]
        var outs: Int
    }

    /// Works out where everyone ends up. Automatic rules first, then any
    /// manual overrides the scorer supplied.
    private static func resolveAdvances(
        outcome: PlayOutcome,
        manualAdvances: [ManualAdvance]?,
        bases: Bases,
        batter: Runner
    ) -> AdvanceResolution {
        // The batter-runner is keyed by nil — they aren't on a base yet.
        var targets: [Base?: AdvanceTarget] = [:]
        let batterKey: Base? = nil
        targets[batterKey] = defaultBatterTarget(for: outcome)

        // Then every runner already aboard.
        for base in bases.occupied {
            targets[base] = defaultRunnerTarget(for: outcome, runnerOn: base, bases: bases)
        }

        // Overrides win.
        for advance in manualAdvances ?? [] {
            targets[advance.from] = advance.to
        }

        var resulting = Bases()
        var scored: [Runner] = []
        var outs = 0

        // Lead runners resolve first so a trailing runner can't leapfrog into
        // an occupied base. The trailing `nil` is the batter-runner.
        let order: [Base?] = [Base.third, Base.second, Base.first, nil]
        for origin in order {
            guard let target = targets[origin] else { continue }
            let runner: Runner?
            if let origin {
                runner = bases[origin]
            } else {
                runner = batter
            }
            guard let runner else { continue }

            switch target {
            case .out:
                outs += 1
            case .home:
                scored.append(runner)
            case .held:
                if let origin { resulting[origin] = runner }
            case .first, .second, .third:
                if let base = target.base {
                    resulting[base] = runner
                }
            }
        }

        return AdvanceResolution(bases: resulting, scored: scored, outs: outs)
    }

    private static func defaultBatterTarget(for outcome: PlayOutcome) -> AdvanceTarget {
        switch outcome {
        case .walk, .hitByPitch, .catchersInterference, .fieldersChoice:
            return .first
        case .strikeout(_, let uncaught):
            return uncaught ? .first : .out
        case .hit(let kind, _, _):
            return Base.advancing(from: nil, by: kind.bases)
        case .error(_, _, let basesAwarded):
            return Base.advancing(from: nil, by: max(1, basesAwarded))
        case .fieldOut, .doublePlay, .triplePlay, .sacrificeFly, .sacrificeBunt:
            return .out
        }
    }

    private static func defaultRunnerTarget(
        for outcome: PlayOutcome,
        runnerOn base: Base,
        bases: Bases
    ) -> AdvanceTarget {
        let forced = bases.forcedBases.contains(base)

        switch outcome {
        case .walk, .hitByPitch, .catchersInterference:
            // Only forced runners move on a free pass.
            return forced ? Base.advancing(from: base, by: 1) : .held

        case .hit(let kind, _, _):
            return Base.advancing(from: base, by: kind.bases)

        case .error(_, _, let basesAwarded):
            return Base.advancing(from: base, by: max(1, basesAwarded))

        case .sacrificeBunt:
            return Base.advancing(from: base, by: 1)

        case .sacrificeFly:
            // Only the runner on third tags and scores by default.
            return base == .third ? .home : .held

        case .fieldersChoice:
            // The lead forced runner is the one retired.
            if let lead = bases.forcedBases.last, lead == base {
                return .out
            }
            return forced ? Base.advancing(from: base, by: 1) : .held

        case .doublePlay:
            // Standard 6-4-3 shape: the runner on first is erased along with
            // the batter. With nobody on first the trailing runner goes
            // instead. Anything else is a manual override.
            if retiredRunners(bases: bases, count: 1).contains(base) { return .out }
            return forced ? Base.advancing(from: base, by: 1) : .held

        case .triplePlay:
            if retiredRunners(bases: bases, count: 2).contains(base) { return .out }
            return .held

        case .strikeout, .fieldOut:
            return .held
        }
    }

    /// Which runners a multiple-out play erases, working up from the batter —
    /// the trailing runners are the ones a force play catches.
    private static func retiredRunners(bases: Bases, count: Int) -> Set<Base> {
        var victims: Set<Base> = []
        for base in [Base.first, .second, .third] where bases[base] != nil {
            guard victims.count < count else { break }
            victims.insert(base)
        }
        return victims
    }

    // MARK: - Baserunning events

    private static func applyStolenBase(
        from base: Base,
        to state: GameState,
        document: GameDocument,
        isIndifference: Bool = false
    ) -> ApplyResult {
        var working = state
        guard let runner = working.bases[base] else {
            return ApplyResult(state: working, plateAppearance: nil)
        }
        working.bases[base] = nil

        var scored: [ScoredRun] = []
        if let next = base.next {
            working.bases[next] = runner
        } else {
            let isEarned = !runner.reachedOnError && (working.outs + working.phantomOuts) < 3
            scored.append(
                ScoredRun(
                    runnerID: runner.playerID,
                    responsiblePitcherID: runner.responsiblePitcherID,
                    isEarned: isEarned,
                    battedInBy: nil
                )
            )
            working.addRuns(1, to: working.battingSide)
        }

        var result = ApplyResult(state: working, plateAppearance: nil)
        result.runs = scored
        result.headline = isIndifference ? "Defensive indifference" : "Stolen base"
        checkGameEnd(&result, document: document)
        return result
    }

    private static func applyRunnerRetired(
        from base: Base,
        to state: GameState,
        document: GameDocument,
        headline: String
    ) -> ApplyResult {
        var working = state
        guard working.bases[base] != nil else {
            return ApplyResult(state: working, plateAppearance: nil)
        }
        working.bases[base] = nil
        working.outs = min(3, working.outs + 1)

        var result = ApplyResult(state: working, plateAppearance: nil)
        result.outsRecorded = 1
        result.headline = headline
        finishHalfInningIfNeeded(&result, document: document)
        checkGameEnd(&result, document: document)
        return result
    }

    /// Balk, wild pitch and passed ball all push every runner up one base.
    private static func applyBulkAdvance(
        to state: GameState,
        document: GameDocument,
        headline: String
    ) -> ApplyResult {
        var working = state
        var resulting = Bases()
        var scored: [ScoredRun] = []

        for base in [Base.third, .second, .first] {
            guard let runner = working.bases[base] else { continue }
            if let next = base.next {
                resulting[next] = runner
            } else {
                let isEarned = !runner.reachedOnError && (working.outs + working.phantomOuts) < 3
                scored.append(
                    ScoredRun(
                        runnerID: runner.playerID,
                        responsiblePitcherID: runner.responsiblePitcherID,
                        isEarned: isEarned,
                        battedInBy: nil
                    )
                )
            }
        }

        working.bases = resulting
        working.addRuns(scored.count, to: working.battingSide)

        var result = ApplyResult(state: working, plateAppearance: nil)
        result.runs = scored
        result.headline = headline
        checkGameEnd(&result, document: document)
        return result
    }

    // MARK: - Substitutions

    private static func applySubstitution(
        _ substitution: Substitution,
        to state: GameState,
        document: GameDocument
    ) -> ApplyResult {
        var working = state
        var lineup = working.lineups[substitution.side]

        switch substitution.kind {
        case .pinchHitter, .pinchRunner, .defensive:
            if let slot = substitution.battingSlot, lineup.slots.indices.contains(slot) {
                lineup.slots[slot] = LineupState.Slot(
                    playerID: substitution.incomingPlayerID,
                    position: substitution.position
                )
            }
            if substitution.position.isFielder {
                lineup.assign(substitution.incomingPlayerID, to: substitution.position)
            }
            lineup.noteAppearance(substitution.incomingPlayerID)

        case .pitchingChange:
            lineup.assign(substitution.incomingPlayerID, to: .pitcher)
            // Without a DH the new pitcher also inherits a batting slot.
            if let slot = substitution.battingSlot, lineup.slots.indices.contains(slot) {
                lineup.slots[slot] = LineupState.Slot(
                    playerID: substitution.incomingPlayerID,
                    position: .pitcher
                )
            }
            lineup.noteAppearance(substitution.incomingPlayerID)

        case .positionSwitch:
            lineup.assign(substitution.incomingPlayerID, to: substitution.position)
            if let slot = lineup.slotIndex(of: substitution.incomingPlayerID) {
                lineup.slots[slot].position = substitution.position
            }
        }

        if let outgoing = substitution.outgoingPlayerID {
            lineup.benchPlayerIDs.removeAll { $0 == outgoing }
        }

        working.lineups[substitution.side] = lineup

        // A pinch runner takes over the base the replaced runner was standing on.
        if substitution.kind == .pinchRunner,
           let base = substitution.runnerBase,
           let existing = working.bases[base] {
            working.bases[base] = Runner(
                playerID: substitution.incomingPlayerID,
                responsiblePitcherID: existing.responsiblePitcherID,
                reachedOnError: existing.reachedOnError
            )
        }

        var result = ApplyResult(state: working, plateAppearance: nil)
        let name = document.player(id: substitution.incomingPlayerID)?.shortName ?? "Sub"
        result.headline = "\(substitution.kind.abbreviation) \(name)"
        return result
    }

    // MARK: - Half innings and endings

    private static func finishHalfInningIfNeeded(_ result: inout ApplyResult, document: GameDocument) {
        guard result.state.outs >= 3 else { return }
        var working = result.state

        working.leftOnBase[working.battingSide] += working.bases.runnerCount
        working.bases.clear()
        working.outs = 0
        working.phantomOuts = 0
        working.resetCount()

        let wasHalf = working.half
        working.half = wasHalf.next
        if working.half == .top {
            working.inning += 1
        }
        working.ensureLineScoreDepth()

        // Extra-innings runner on second, if the league uses it. The runner is
        // whoever made the last out, i.e. the slot before the leadoff batter.
        if document.rules.extraInningRunnerOnSecond,
           working.inning > document.rules.regulationInnings,
           let pitcherID = working.lineups[working.fieldingSide].currentPitcherID {
            let lineup = working.lineups[working.battingSide]
            let slotCount = lineup.slots.count
            if slotCount > 0 {
                let previous = (lineup.battingIndex + slotCount - 1) % slotCount
                working.bases.second = Runner(
                    playerID: lineup.slots[previous].playerID,
                    responsiblePitcherID: pitcherID,
                    reachedOnError: true // a placed runner is never an earned run
                )
            }
        }

        result.state = working
        result.halfInningEnded = true
    }

    private static func checkGameEnd(_ result: inout ApplyResult, document: GameDocument) {
        guard !result.state.isFinal else { return }
        var working = result.state
        let rules = document.rules
        let away = working.awayRuns
        let home = working.homeRuns

        if let mercy = rules.mercyRuleDifference, abs(away - home) >= mercy, working.inning >= 5 {
            working.isFinal = true
        }

        // Covers both endings on the home side: a walk-off mid-inning, and the
        // top of the ninth ending with the home team ahead so they never bat.
        if working.half == .bottom, working.inning >= rules.regulationInnings, home > away {
            working.isFinal = true
        }
        // The bottom half just ended (the half already flipped) with a decision.
        if working.half == .top, working.inning > rules.regulationInnings, away != home {
            working.isFinal = true
        }

        if working.isFinal {
            result.gameEnded = true
        }
        result.state = working
    }

    // MARK: - Headlines

    private static func headline(for outcome: PlayOutcome, runs: Int, cancelled: Bool) -> String {
        var base: String
        switch outcome {
        case .strikeout(let looking, let uncaught):
            base = uncaught ? "Strikeout, batter reaches" : (looking ? "Strikeout looking" : "Strikeout swinging")
        case .walk(let intentional):
            base = intentional ? "Intentional walk" : "Walk"
        case .hitByPitch:
            base = "Hit by pitch"
        case .catchersInterference:
            base = "Catcher's interference"
        case .hit(let kind, _, _):
            base = kind.spokenName.capitalizedFirst
        case .fieldOut(let fielders, let batted):
            let shape = batted?.trajectory.label.lowercased() ?? "out"
            let who = fielders.map { String($0.rawValue) }.joined(separator: "-")
            base = who.isEmpty ? "Out" : "\(shape.capitalizedFirst) out, \(who)"
        case .error(let fielder, _, _):
            base = "Error, \(fielder.rawValue)"
        case .fieldersChoice:
            base = "Fielder's choice"
        case .doublePlay:
            base = "Double play"
        case .triplePlay:
            base = "Triple play"
        case .sacrificeFly:
            base = "Sacrifice fly"
        case .sacrificeBunt:
            base = "Sacrifice bunt"
        }

        if cancelled {
            return base + ", inning over"
        }
        switch runs {
        case 0: return base
        case 1: return base + ", run scores"
        default: return base + ", \(runs) run\(runs == 1 ? "" : "s") score"
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
