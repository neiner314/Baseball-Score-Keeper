import Foundation
@testable import BaseballScoreKeeper

/// Test helper that drives the engine the way the app does: append an event,
/// keep the returned state, keep the log in sync so box scores can be built.
struct GameDriver {
    private(set) var document: GameDocument
    private(set) var state: GameState
    private(set) var lastResult: ApplyResult?

    init(usesDH: Bool = true, regulationInnings: Int = 9, extraInningRunner: Bool = false) {
        var rules = GameRules.standard
        rules.usesDesignatedHitter = usesDH
        rules.regulationInnings = regulationInnings
        rules.extraInningRunnerOnSecond = extraInningRunner

        let document = GameFactory.newGame(
            away: GameFactory.placeholderRoster(name: "Away", abbreviation: "AWY", usesDH: usesDH),
            home: GameFactory.placeholderRoster(name: "Home", abbreviation: "HME", usesDH: usesDH),
            rules: rules
        )
        self.document = document
        self.state = ScoringEngine.initialState(document: document)
    }

    @discardableResult
    mutating func apply(_ event: GameEvent) -> ApplyResult {
        let result = ScoringEngine.apply(event, to: state, document: document)
        state = result.state
        document.events.append(RecordedEvent(event: event))
        lastResult = result
        return result
    }

    @discardableResult
    mutating func pitch(_ outcome: PitchOutcome) -> ApplyResult {
        apply(.pitch(Pitch(outcome: outcome)))
    }

    @discardableResult
    mutating func play(_ outcome: PlayOutcome, advances: [ManualAdvance]? = nil) -> ApplyResult {
        apply(.play(outcome, manualAdvances: advances))
    }

    /// Four balls.
    mutating func walk() {
        for _ in 0..<4 { pitch(.ball) }
    }

    /// Three swinging strikes.
    mutating func strikeout() {
        for _ in 0..<3 { pitch(.swingingStrike) }
    }

    mutating func single() {
        play(.hit(.single, batted: BattedBall(trajectory: .grounder), fielder: .shortstop))
    }

    mutating func homeRun() {
        play(.hit(.homeRun, batted: BattedBall(trajectory: .flyBall), fielder: .centerField))
    }

    /// Retires the side however many outs it takes.
    mutating func retireSide() {
        let inning = state.inning
        let half = state.half
        var safety = 0
        while state.inning == inning, state.half == half, !state.isFinal, safety < 12 {
            strikeout()
            safety += 1
        }
    }

    mutating func advance(toInning inning: Int, half: Half) {
        var safety = 0
        while !(state.inning == inning && state.half == half), !state.isFinal, safety < 60 {
            retireSide()
            safety += 1
        }
    }

    var awayRuns: Int { state.awayRuns }
    var homeRuns: Int { state.homeRuns }
}
