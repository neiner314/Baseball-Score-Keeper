import Foundation
import Observation

/// The single source of truth for a game in progress.
///
/// The UI never edits `state` — it appends events, and state is whatever the
/// engine says the log adds up to. That is what makes undo trivial: drop the
/// last event and replay.
@MainActor
@Observable
final class GameStore {
    private(set) var document: GameDocument
    private(set) var state: GameState
    /// Short description of the last thing that happened, for the toast and
    /// the announcer.
    private(set) var lastHeadline: String = ""
    private(set) var lastPlateAppearance: PlateAppearanceResult?
    /// Set when a ball is in play and the scorer still owes us a result.
    private(set) var isAwaitingPlayResult = false

    private var redoStack: [[RecordedEvent]] = []
    private var activeGroupID: UUID?

    var settings: TrackingSettings {
        get { document.settings }
        set {
            document.settings = newValue
            AppPreferences.defaultTrackingSettings = newValue
            persist()
        }
    }

    var teams: SideValues<TeamRoster> { document.teams }

    init(document: GameDocument) {
        self.document = document
        self.state = ScoringEngine.replay(document: document)
        self.isAwaitingPlayResult = Self.awaitingResult(in: document)
    }

    // MARK: - Reading

    var currentBatter: Player? {
        state.currentBatterID.flatMap { document.player(id: $0) }
    }

    var currentPitcher: Player? {
        state.currentPitcherID.flatMap { document.player(id: $0) }
    }

    var currentBatterPosition: Position? {
        guard let id = state.currentBatterID else { return nil }
        return state.battingLineup.slots.first { $0.playerID == id }?.position
    }

    func player(id: UUID) -> Player? { document.player(id: id) }

    func runnerOnBase(_ base: Base) -> Player? {
        state.bases[base].flatMap { document.player(id: $0.playerID) }
    }

    var canUndo: Bool { !document.events.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// The pitch marks for the current at-bat: B, C, S, F, X.
    var currentAtBatMarks: [String] {
        state.currentAtBatPitches.map(\.outcome.mark)
    }

    func buildBoxScore() -> BoxScore {
        BoxScoreBuilder.build(document: document)
    }

    /// The scorebook pages, rebuilt from the log. Cheap enough to call from a
    /// view body — it's the same fold the live state comes from.
    func buildScorebook() -> SideValues<ScorebookPage> {
        ScorebookBuilder.build(document: document)
    }

    // MARK: - Recording

    /// Opens an undo group. Everything recorded until `endGroup` is treated as
    /// one action — the ball-in-play flow records a pitch and a play, and the
    /// scorer thinks of that as a single thing they did.
    func beginGroup() {
        activeGroupID = UUID()
    }

    func endGroup() {
        activeGroupID = nil
    }

    func record(_ event: GameEvent) {
        let recorded = RecordedEvent(event: event, groupID: activeGroupID)
        document.events.append(recorded)

        let result: ApplyResult?
        if event.requiresFullReplay {
            // A challenge changes a pitch that has already been folded in, so
            // the log has to be re-read from the top.
            let rebuilt = ScoringEngine.replayDetailed(document: document)
            state = rebuilt.state
            result = rebuilt.last
        } else {
            let applied = ScoringEngine.apply(event, to: state, document: document)
            state = applied.state
            result = applied
        }

        if let result {
            lastHeadline = result.headline
            if let appearance = result.plateAppearance {
                lastPlateAppearance = appearance
            }
            announce(result)
        }
        redoStack.removeAll()

        updateAwaitingFlag(for: event)
        persist()
    }

    func recordPitch(
        outcome: PitchOutcome,
        velocity: Int? = nil,
        type: PitchType? = nil,
        location: FieldLocation? = nil
    ) {
        record(
            .pitch(
                Pitch(
                    outcome: outcome,
                    velocity: settings.trackPitchVelocity ? velocity : nil,
                    type: settings.trackPitchType ? type : nil,
                    location: settings.trackPitchLocation ? location : nil
                )
            )
        )
    }

    func recordPlay(_ outcome: PlayOutcome, manualAdvances: [ManualAdvance]? = nil) {
        record(.play(outcome, manualAdvances: manualAdvances))
    }

    func substitute(_ substitution: Substitution) {
        record(.substitution(substitution))
    }

    // MARK: - Challenges

    /// The call currently open to challenge, if any.
    ///
    /// A challenge has to be immediate, so this is only the pitch just thrown
    /// — and only if it was the umpire's judgement on location and hasn't
    /// already been challenged.
    var challengeablePitch: Pitch? {
        guard document.rules.usesChallenges, settings.trackChallenges else { return nil }

        for recorded in document.events.reversed() {
            switch recorded.event {
            case .challenge:
                // This pitch has had its review already.
                return nil
            case .pitch(let pitch):
                return pitch.outcome.isChallengeable ? pitch : nil
            default:
                return nil
            }
        }
        return nil
    }

    var challengesRemaining: SideValues<Int> { state.challengesRemaining }

    /// The team a given challenger belongs to right now.
    func challengingSide(for role: ChallengeRole) -> Side {
        role.side(battingSide: state.battingSide)
    }

    func canChallenge(as role: ChallengeRole) -> Bool {
        challengeablePitch != nil && state.challengesRemaining[challengingSide(for: role)] > 0
    }

    /// Who would most likely be challenging this call. A strike called on your
    /// hitter is the batter's to contest; a ball called on your pitcher is the
    /// battery's.
    var suggestedChallengeRole: ChallengeRole {
        challengeablePitch?.outcome == .calledStrike ? .batter : .catcher
    }

    func recordChallenge(role: ChallengeRole, result: ChallengeResult) {
        guard let pitch = challengeablePitch else { return }
        record(
            .challenge(
                Challenge(role: role, result: result, originalOutcome: pitch.outcome)
            )
        )
    }

    // MARK: - Undo / redo

    func undo() {
        guard let last = document.events.last else { return }

        var removed: [RecordedEvent] = []
        if let groupID = last.groupID {
            while let candidate = document.events.last, candidate.groupID == groupID {
                removed.insert(candidate, at: 0)
                document.events.removeLast()
            }
        } else {
            removed = [document.events.removeLast()]
        }

        redoStack.append(removed)
        rebuild()
        Haptics.shared.undo(enabled: settings.hapticsEnabled)
        lastHeadline = "Undone"
    }

    func redo() {
        guard let group = redoStack.popLast() else { return }
        document.events.append(contentsOf: group)
        rebuild()
        lastHeadline = "Redone"
    }

    private func rebuild() {
        state = ScoringEngine.replay(document: document)
        isAwaitingPlayResult = Self.awaitingResult(in: document)
        lastPlateAppearance = nil
        persist()
    }

    // MARK: - Awaiting a batted-ball result

    /// A pitch put in play leaves the at-bat open until a play is recorded.
    /// Scanning backwards from the end tells us whether we're in that gap.
    private static func awaitingResult(in document: GameDocument) -> Bool {
        for recorded in document.events.reversed() {
            switch recorded.event {
            case .play:
                return false
            case .pitch(let pitch):
                if pitch.outcome == .inPlay { return true }
                return false
            default:
                continue
            }
        }
        return false
    }

    private func updateAwaitingFlag(for event: GameEvent) {
        switch event {
        case .pitch(let pitch):
            isAwaitingPlayResult = pitch.outcome == .inPlay
        case .play:
            isAwaitingPlayResult = false
        default:
            break
        }
    }

    // MARK: - Feedback

    private func announce(_ result: ApplyResult) {
        Haptics.shared.feedback(for: result, enabled: settings.hapticsEnabled)
        if settings.spokenConfirmations {
            Announcer.shared.say(result.headline)
        }
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = document
        AppPreferences.lastGameID = snapshot.id
        Task {
            try? await GameArchive.shared.save(snapshot)
        }
    }
}
