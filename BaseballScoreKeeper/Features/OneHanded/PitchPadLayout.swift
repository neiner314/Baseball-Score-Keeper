import SwiftUI

/// The gesture-to-outcome map for the pitch pad.
///
/// The left/right axis mirrors how a count is written and read everywhere in
/// baseball — balls first, strikes second, so a full count is 3-2. Flick left
/// for a ball, flick right for a strike.
///
/// That mapping is deliberately **not** mirrored for left-handed scorers. The
/// cluster's position moves to whichever corner the thumb lives in, but ball
/// stays left and strike stays right for everyone, because the gesture is
/// standing in for the scoreboard, not for the hand.
///
/// Hit-by-pitch is not on any flick. It is a press-and-hold, because it is
/// rare, it ends the plate appearance, and recording one by accident means
/// noticing and undoing it — the exact thing this app is supposed to avoid.
enum PitchPadLayout {

    /// How long the thumb has to stay put before hit-by-pitch arms.
    static let holdDuration: Double = 0.55

    static func outcome(for direction: FlickDirection) -> PitchOutcome? {
        switch direction {
        case .left: .ball
        case .right: .swingingStrike
        case .up: .calledStrike
        case .down: .foul
        case .center: .inPlay
        }
    }

    /// What a press-and-hold records.
    static let heldOutcome: PitchOutcome = .hitByPitch

    static var options: [FlickDirection: FlickOption] {
        [
            .left: FlickOption("Ball", tint: Theme.ball),
            .right: FlickOption("Miss", tint: Theme.miss),
            .up: FlickOption("Call", tint: Theme.calledStrike),
            .down: FlickOption("Foul", tint: Theme.foul),
            .center: FlickOption("In Play", tint: Theme.inPlay)
        ]
    }

    static var holdOption: FlickOption {
        FlickOption("HBP", tint: Theme.hitByPitch)
    }

    /// True when the gesture records a pitch outright. A centre tap doesn't —
    /// it opens the fielder dial, and nothing is written until a result is
    /// chosen, so a stray tap costs a dismissal rather than an undo.
    static func recordsImmediately(_ direction: FlickDirection) -> Bool {
        outcome(for: direction).map { $0 != .inPlay } ?? false
    }
}
