import Foundation

enum SubstitutionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case pinchHitter
    case pinchRunner
    case defensive
    case pitchingChange
    case positionSwitch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pinchHitter: "Pinch Hitter"
        case .pinchRunner: "Pinch Runner"
        case .defensive: "Defensive Sub"
        case .pitchingChange: "Pitching Change"
        case .positionSwitch: "Position Switch"
        }
    }

    var abbreviation: String {
        switch self {
        case .pinchHitter: "PH"
        case .pinchRunner: "PR"
        case .defensive: "DEF"
        case .pitchingChange: "P"
        case .positionSwitch: "POS"
        }
    }
}

struct Substitution: Codable, Hashable, Sendable {
    var side: Side
    var kind: SubstitutionKind
    var incomingPlayerID: UUID
    var outgoingPlayerID: UUID?
    /// Batting order slot being filled. nil for a pure position switch of a
    /// player already in the order.
    var battingSlot: Int?
    var position: Position
    /// For a pinch runner: which base the replaced runner is standing on.
    var runnerBase: Base?
}

enum GameEvent: Codable, Hashable, Sendable {
    case pitch(Pitch)
    case play(PlayOutcome, manualAdvances: [ManualAdvance]?)
    case stolenBase(from: Base)
    case caughtStealing(from: Base)
    case pickoff(from: Base)
    case balk
    case wildPitchAdvance
    case passedBallAdvance
    case defensiveIndifference(from: Base)
    case substitution(Substitution)
    /// A ball-strike challenge against the pitch that immediately preceded it.
    case challenge(Challenge)
    /// Manual half-inning end, for the rare case the scorer needs to force it.
    case endHalfInning
    case endGame

    var isPitch: Bool {
        if case .pitch = self { return true }
        return false
    }

    var isPlay: Bool {
        if case .play = self { return true }
        return false
    }

    var isSubstitution: Bool {
        if case .substitution = self { return true }
        return false
    }

    var isChallenge: Bool {
        if case .challenge = self { return true }
        return false
    }

    /// A challenge rewrites the pitch it points at, so the log has to be
    /// folded again from the beginning rather than applied on top of the state
    /// the uncorrected pitch already produced.
    var requiresFullReplay: Bool { isChallenge }
}

struct RecordedEvent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var event: GameEvent
    /// Events the scorer performed as one action — a ball put in play and the
    /// result that followed it — share an ID so undo takes them back together.
    var groupID: UUID?

    init(id: UUID = UUID(), date: Date = Date(), event: GameEvent, groupID: UUID? = nil) {
        self.id = id
        self.date = date
        self.event = event
        self.groupID = groupID
    }
}
