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
    /// Carries a fresh id the moment a grand slam clears the bases, so the live
    /// field can set off a small fireworks celebration. A new id each time lets
    /// the animation re-fire even on back-to-back slams.
    private(set) var grandSlamCelebration: UUID?

    private var redoStack: [[RecordedEvent]] = []
    private var activeGroupID: UUID?

    /// Real pitch mixes fetched from the league feed, keyed by player. Missing
    /// until fetched (or forever, for a hand-entered game) — `arsenal(for:)`
    /// falls back to a generic mix so the velocity pad always has labels.
    private var arsenalCache: [UUID: [PitchType]] = [:]

    /// Season hitting lines fetched from the league feed, keyed by player. Nil
    /// for a player until fetched, and never populated for custom games.
    private var seasonStatsCache: [UUID: SeasonHittingStats] = [:]
    /// NPB's season line is aggregated once for the whole league from its
    /// per-game files, then every batter is a dictionary lookup.
    private var npbSeasonTable: [String: SeasonHittingStats]?
    private var npbSeasonRequested = false

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

    /// The live pitching line for whoever is on the mound: innings, hits, runs,
    /// walks, strikeouts and pitch count, all folded out of the event log the
    /// same way the box score is. Nothing here is fetched — it's the scorer's
    /// own numbers, so it works offline and for non-league games too.
    var currentPitcherLine: PitchingLine? {
        guard let pitcherID = state.currentPitcherID else { return nil }
        return buildBoxScore().pitching[state.fieldingSide].first { $0.id == pitcherID }
    }

    /// The live batting line for the hitter at the plate — this game's average,
    /// home runs, RBI and the rest — read out of the same box-score fold.
    var currentBatterLine: BattingLine? {
        guard let batterID = state.currentBatterID else { return nil }
        return buildBoxScore().batting[state.battingSide].first { $0.id == batterID }
    }

    var currentBatterPosition: Position? {
        guard let id = state.currentBatterID else { return nil }
        return state.battingLineup.slots.first { $0.playerID == id }?.position
    }

    /// The hitter due up after the one at the plate.
    var onDeckBatter: Player? { dueUpBatter(slotsAhead: 1) }

    /// The hitter due up two after the one at the plate.
    var inTheHoleBatter: Player? { dueUpBatter(slotsAhead: 2) }

    /// Walks `slotsAhead` places down the batting order from the current slot,
    /// wrapping back to the top, so late in an inning on-deck rolls around to
    /// the leadoff hitter.
    private func dueUpBatter(slotsAhead: Int) -> Player? {
        let lineup = state.battingLineup
        guard !lineup.slots.isEmpty else { return nil }
        let index = (lineup.battingIndex + slotsAhead) % lineup.slots.count
        return document.player(id: lineup.slots[index].playerID)
    }

    func player(id: UUID) -> Player? { document.player(id: id) }

    /// The pitch types to label the velocity pad with. The pitcher's real mix
    /// once it's been fetched, otherwise a generic arsenal so the pad is never
    /// empty.
    func arsenal(for pitcher: Player) -> [PitchType] {
        arsenalCache[pitcher.id] ?? PitchType.defaultArsenal
    }

    /// Pulls the pitcher's real arsenal from the league feed the first time
    /// they take the mound. Best effort: a non-league game, a pitcher with no
    /// feed id, or any network failure just leaves the generic mix in place.
    func loadArsenal(for pitcher: Player) async {
        guard arsenalCache[pitcher.id] == nil else { return }
        guard let league = document.league, let externalID = pitcher.externalID else { return }
        guard let provider = LeagueDirectory.arsenalProvider(for: league) else { return }

        let season = Calendar.current.component(.year, from: document.startedAt)
        guard
            let arsenal = try? await provider.arsenal(pitcherExternalID: externalID, season: season),
            !arsenal.isEmpty
        else { return }

        arsenalCache[pitcher.id] = arsenal
    }

    /// The batter's season line for the at-bat card, once fetched. Nil for a
    /// custom game or a player the feed doesn't know.
    func seasonStats(for player: Player) -> SeasonHittingStats? {
        seasonStatsCache[player.id]
    }

    /// Pulls the batter's season line from the league feed the first time they
    /// come up. MLB is a per-player fetch; NPB aggregates the whole league's
    /// per-game files once and then serves every batter from memory. Best
    /// effort — a custom game, a missing id, or any failure just leaves the
    /// at-bat card on this game's line.
    func loadSeasonStats(for player: Player) async {
        guard seasonStatsCache[player.id] == nil else { return }
        guard let league = document.league, let externalID = player.externalID else { return }

        let season = Calendar(identifier: .gregorian).component(.year, from: document.startedAt)

        switch league {
        case .mlb:
            if let stats = try? await MLBStatsProvider().seasonHitting(
                playerExternalID: externalID,
                season: season
            ) {
                seasonStatsCache[player.id] = stats
            }
        case .npb:
            if npbSeasonTable == nil, !npbSeasonRequested {
                npbSeasonRequested = true
                npbSeasonTable = await NPBDataProvider().seasonHitting(season: season)
            }
            if let stats = npbSeasonTable?[externalID] {
                seasonStatsCache[player.id] = stats
            }
        case .kbo, .other:
            break
        }
    }

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
                // A home run that scores four can only be a bases-loaded slam:
                // three on plus the batter. That's the cue for the fireworks.
                if appearance.outcome.hitKind == .homeRun, result.runs.count == 4 {
                    grandSlamCelebration = UUID()
                }
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

    // MARK: - Resetting

    /// Wipes every recorded pitch, play and substitution and returns the game
    /// to its opening state, keeping the teams, lineups, rules and tracking
    /// settings exactly as they were set up. State is a fold over the log, so
    /// clearing the log and replaying re-derives the fresh start-of-game state.
    ///
    /// There is no undoing this — it sits outside the undo stack and clears the
    /// redo history — so the UI gates it behind a confirmation.
    func resetScoring() {
        document.events.removeAll()
        redoStack.removeAll()
        activeGroupID = nil
        state = ScoringEngine.replay(document: document)
        isAwaitingPlayResult = false
        lastPlateAppearance = nil
        grandSlamCelebration = nil
        lastHeadline = "Scoring reset"
        persist()
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

    // MARK: - Correcting the log

    /// Direct edits to the event log used by the accuracy report to fix a play
    /// scored wrong. Because state is a fold over the log, replacing one play and
    /// replaying re-derives only what genuinely flows from it and leaves every
    /// other call exactly as the scorer entered it.
    ///
    /// These sit outside the undo stack — a correction is a considered act made
    /// from a preview, not a stray tap — so they clear the redo history and can
    /// themselves be re-corrected rather than undone with the back button.

    /// Rewrites the outcome of the plate appearance the given event resolved.
    /// The event may be a `.play` or the `.pitch` that auto-resolved a strikeout,
    /// walk or hit-by-pitch; either way it becomes an explicit `.play`.
    func correctPlay(atEventIndex index: Int, to outcome: PlayOutcome, manualAdvances: [ManualAdvance]? = nil) {
        guard document.events.indices.contains(index) else { return }
        let existing = document.events[index]
        document.events[index] = RecordedEvent(
            id: existing.id,
            date: existing.date,
            event: .play(outcome, manualAdvances: manualAdvances),
            groupID: existing.groupID
        )
        rebuildAfterEdit(headline: "Play corrected")
    }

    /// Inserts a plate appearance the scorer missed. It records for whichever
    /// batter is due up at that point in the replay — the one who was skipped.
    func insertPlay(atEventIndex index: Int, outcome: PlayOutcome, manualAdvances: [ManualAdvance]? = nil) {
        let clamped = max(0, min(index, document.events.count))
        document.events.insert(
            RecordedEvent(event: .play(outcome, manualAdvances: manualAdvances)),
            at: clamped
        )
        rebuildAfterEdit(headline: "Play added")
    }

    /// Removes a plate appearance the scorer entered but the official doesn't
    /// have — the resolving event and the pitches that led up to it.
    func removePlateAppearance(terminalEventIndex index: Int) {
        guard document.events.indices.contains(index) else { return }
        let lower = plateAppearanceLowerBound(endingAt: index)
        document.events.removeSubrange(lower...index)
        rebuildAfterEdit(headline: "Play removed")
    }

    /// The base/out situation as it stood just before the plate appearance the
    /// given event resolved, so a correction that changes who scored can put the
    /// runners up on the right diamond.
    func stateBeforePlay(terminalEventIndex index: Int) -> GameState {
        guard document.events.indices.contains(index) else { return state }
        let lower = plateAppearanceLowerBound(endingAt: index)
        var prefix = document
        prefix.events = Array(document.events[0..<lower])
        return ScoringEngine.replay(document: prefix)
    }

    /// Walks back over the pitches that belong to the plate appearance resolved
    /// at `index`. The count resets every appearance, so every pitch between the
    /// previous non-pitch event and this one is part of it.
    private func plateAppearanceLowerBound(endingAt index: Int) -> Int {
        var lower = index
        while lower > 0, document.events[lower - 1].event.isPitch {
            lower -= 1
        }
        return lower
    }

    private func rebuildAfterEdit(headline: String) {
        state = ScoringEngine.replay(document: document)
        isAwaitingPlayResult = Self.awaitingResult(in: document)
        redoStack.removeAll()
        lastPlateAppearance = nil
        lastHeadline = headline
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
