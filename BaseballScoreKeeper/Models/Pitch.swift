import Foundation

/// What a single pitch did. Everything the count depends on is here; what
/// happened *after* a ball was put in play is a `PlayOutcome`.
enum PitchOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case ball
    case calledStrike
    case swingingStrike
    case foul
    case inPlay
    case hitByPitch
    case wildPitch
    case passedBall

    var id: String { rawValue }

    var isStrike: Bool {
        switch self {
        case .calledStrike, .swingingStrike, .foul: true
        default: false
        }
    }

    /// A wild pitch or passed ball is also a ball on the count.
    var countsAsBall: Bool {
        switch self {
        case .ball, .wildPitch, .passedBall: true
        default: false
        }
    }

    var shortLabel: String {
        switch self {
        case .ball: "Ball"
        case .calledStrike: "Call"
        case .swingingStrike: "Miss"
        case .foul: "Foul"
        case .inPlay: "In Play"
        case .hitByPitch: "HBP"
        case .wildPitch: "WP"
        case .passedBall: "PB"
        }
    }

    var spokenLabel: String {
        switch self {
        case .ball: "ball"
        case .calledStrike: "called strike"
        case .swingingStrike: "swinging strike"
        case .foul: "foul"
        case .inPlay: "in play"
        case .hitByPitch: "hit by pitch"
        case .wildPitch: "wild pitch"
        case .passedBall: "passed ball"
        }
    }

    /// What this call becomes if a challenge overturns it. Only the umpire's
    /// location calls can be challenged — a swing and miss or a foul is not a
    /// judgement about the strike zone, so neither is reviewable.
    var challengeReversal: PitchOutcome? {
        switch self {
        case .ball: .calledStrike
        case .calledStrike: .ball
        default: nil
        }
    }

    var isChallengeable: Bool { challengeReversal != nil }

    /// Scorebook mark for the pitch sequence strip.
    var mark: String {
        switch self {
        case .ball: "B"
        case .calledStrike: "C"
        case .swingingStrike: "S"
        case .foul: "F"
        case .inPlay: "X"
        case .hitByPitch: "H"
        case .wildPitch: "W"
        case .passedBall: "P"
        }
    }
}

enum PitchType: String, Codable, CaseIterable, Identifiable, Sendable {
    case fastball
    case sinker
    case cutter
    case slider
    case curveball
    case changeup
    case splitter
    case knuckleball

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .fastball: "FB"
        case .sinker: "SI"
        case .cutter: "CT"
        case .slider: "SL"
        case .curveball: "CB"
        case .changeup: "CH"
        case .splitter: "SP"
        case .knuckleball: "KN"
        }
    }

    /// The six shown on the quick-pick row; the rest live behind "more".
    static var common: [PitchType] {
        [.fastball, .sinker, .cutter, .slider, .curveball, .changeup]
    }
}

/// A normalized point on the field or in the strike zone. Kept as plain
/// `Double`s so the model layer never has to import CoreGraphics.
struct FieldLocation: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

struct Pitch: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var outcome: PitchOutcome
    var velocity: Int?
    var type: PitchType?
    /// Where it crossed the plate, normalized to the strike-zone box.
    var location: FieldLocation?
    /// Set when this pitch was challenged. If the challenge was won, `outcome`
    /// already holds the corrected call — this is what marks the pitch in the
    /// sequence strip so the correction is visible rather than silent.
    var challengeResult: ChallengeResult?

    init(
        id: UUID = UUID(),
        outcome: PitchOutcome,
        velocity: Int? = nil,
        type: PitchType? = nil,
        location: FieldLocation? = nil,
        challengeResult: ChallengeResult? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.velocity = velocity
        self.type = type
        self.location = location
        self.challengeResult = challengeResult
    }
}
