import Foundation

enum HitKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case double
    case triple
    case homeRun

    var id: String { rawValue }

    /// How many bases the batter takes.
    var bases: Int {
        switch self {
        case .single: 1
        case .double: 2
        case .triple: 3
        case .homeRun: 4
        }
    }

    var abbreviation: String {
        switch self {
        case .single: "1B"
        case .double: "2B"
        case .triple: "3B"
        case .homeRun: "HR"
        }
    }

    var spokenName: String {
        switch self {
        case .single: "single"
        case .double: "double"
        case .triple: "triple"
        case .homeRun: "home run"
        }
    }
}

enum Trajectory: String, Codable, CaseIterable, Identifiable, Sendable {
    case grounder
    case liner
    case flyBall
    case popup
    case bunt

    var id: String { rawValue }

    /// Prefix used in notation: F8 (fly to center), L6, P4, G6-3.
    var notationPrefix: String {
        switch self {
        case .grounder: ""
        case .liner: "L"
        case .flyBall: "F"
        case .popup: "P"
        case .bunt: "B"
        }
    }

    var label: String {
        switch self {
        case .grounder: "Grounder"
        case .liner: "Liner"
        case .flyBall: "Fly"
        case .popup: "Pop"
        case .bunt: "Bunt"
        }
    }

    /// Fly balls and popups are catchable in the air, which is what makes a
    /// sacrifice fly (and an infield fly) possible.
    var isInAir: Bool {
        self == .flyBall || self == .popup || self == .liner
    }
}

struct BattedBall: Codable, Hashable, Sendable {
    var trajectory: Trajectory
    /// Where it landed / was fielded, in normalized field coordinates.
    var location: FieldLocation?
    var isHardHit: Bool

    init(trajectory: Trajectory, location: FieldLocation? = nil, isHardHit: Bool = false) {
        self.trajectory = trajectory
        self.location = location
        self.isHardHit = isHardHit
    }
}

/// How a plate appearance ended.
enum PlayOutcome: Codable, Hashable, Sendable {
    case strikeout(looking: Bool, uncaught: Bool)
    case walk(intentional: Bool)
    case hitByPitch
    case catchersInterference
    case hit(HitKind, batted: BattedBall?, fielder: Position?)
    case fieldOut(fielders: [Position], batted: BattedBall?)
    case error(fielder: Position, batted: BattedBall?, basesAwarded: Int)
    case fieldersChoice(fielders: [Position], batted: BattedBall?)
    case doublePlay(fielders: [Position], batted: BattedBall?)
    case triplePlay(fielders: [Position], batted: BattedBall?)
    case sacrificeFly(fielder: Position)
    case sacrificeBunt(fielders: [Position])

    /// Outs recorded by the play itself, before manual runner overrides.
    var baseOuts: Int {
        switch self {
        case .strikeout(_, let uncaught): uncaught ? 0 : 1
        case .fieldOut, .sacrificeFly, .sacrificeBunt, .fieldersChoice: 1
        case .doublePlay: 2
        case .triplePlay: 3
        case .walk, .hitByPitch, .catchersInterference, .hit, .error: 0
        }
    }

    /// True when the batter ends up on base rather than retired.
    var batterReachesBase: Bool {
        switch self {
        case .walk, .hitByPitch, .catchersInterference, .error, .fieldersChoice: true
        case .hit(let kind, _, _): kind != .homeRun
        case .strikeout(_, let uncaught): uncaught
        case .fieldOut, .doublePlay, .triplePlay, .sacrificeFly, .sacrificeBunt: false
        }
    }

    /// Counts toward the batter's official at-bats. Walks, HBP, sacrifices and
    /// catcher's interference do not.
    var isAtBat: Bool {
        switch self {
        case .walk, .hitByPitch, .catchersInterference, .sacrificeFly, .sacrificeBunt: false
        default: true
        }
    }

    var isHit: Bool {
        if case .hit = self { return true }
        return false
    }

    var hitKind: HitKind? {
        if case .hit(let kind, _, _) = self { return kind }
        return nil
    }

    /// The batter drove in whatever runs scored — unless the play was an error
    /// or a ground-into-double-play, where the rulebook denies the RBI.
    var earnsRBI: Bool {
        switch self {
        case .error, .doublePlay, .triplePlay: false
        case .strikeout(_, let uncaught): !uncaught
        default: true
        }
    }

    var isErrorPlay: Bool {
        if case .error = self { return true }
        return false
    }

    var battedBall: BattedBall? {
        switch self {
        case .hit(_, let batted, _): batted
        case .fieldOut(_, let batted): batted
        case .error(_, let batted, _): batted
        case .fieldersChoice(_, let batted): batted
        case .doublePlay(_, let batted): batted
        case .triplePlay(_, let batted): batted
        case .sacrificeFly: BattedBall(trajectory: .flyBall)
        case .sacrificeBunt: BattedBall(trajectory: .bunt)
        case .strikeout, .walk, .hitByPitch, .catchersInterference: nil
        }
    }

    /// The fielder who touched it first, for spray charts and dial feedback.
    var primaryFielder: Position? {
        switch self {
        case .hit(_, _, let fielder): fielder
        case .fieldOut(let fielders, _): fielders.first
        case .error(let fielder, _, _): fielder
        case .fieldersChoice(let fielders, _): fielders.first
        case .doublePlay(let fielders, _): fielders.first
        case .triplePlay(let fielders, _): fielders.first
        case .sacrificeFly(let fielder): fielder
        case .sacrificeBunt(let fielders): fielders.first
        case .strikeout, .walk, .hitByPitch, .catchersInterference: nil
        }
    }
}

/// Where a runner ended up. `out` means retired on the play.
enum AdvanceTarget: String, Codable, CaseIterable, Sendable {
    case first
    case second
    case third
    case home
    case out
    case held

    var base: Base? {
        switch self {
        case .first: .first
        case .second: .second
        case .third: .third
        case .home, .out, .held: nil
        }
    }
}

/// An explicit override for one runner, used when the automatic advancement
/// rules guessed wrong (a runner held at third on a single, say).
struct ManualAdvance: Codable, Hashable, Sendable {
    /// nil means the batter-runner.
    var from: Base?
    var to: AdvanceTarget

    init(from: Base?, to: AdvanceTarget) {
        self.from = from
        self.to = to
    }
}
