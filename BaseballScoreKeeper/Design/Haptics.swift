import UIKit

/// Haptic vocabulary for scoring without looking.
///
/// Every gesture answers back through the thumb, and the answers are distinct
/// enough to tell apart: a light tick as you cross a flick zone, a soft thud
/// for a ball, a sharp rap for a strike, a rising double-tap for a run.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {}

    /// Call as a flick crosses into a new zone so the scorer feels the
    /// boundary without looking at the overlay.
    func zoneChanged(enabled: Bool) {
        guard enabled else { return }
        selectionGenerator.selectionChanged()
    }

    /// Warms up the engine so the first tap isn't late.
    func prepare() {
        selectionGenerator.prepare()
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    func tap(enabled: Bool) {
        guard enabled else { return }
        lightGenerator.impactOccurred()
    }

    func commit(enabled: Bool) {
        guard enabled else { return }
        mediumGenerator.impactOccurred()
    }

    func undo(enabled: Bool) {
        guard enabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    func cancelled(enabled: Bool) {
        guard enabled else { return }
        softGenerator.impactOccurred(intensity: 0.5)
    }

    /// A press-and-hold has armed. Deliberately a double thump — nothing else
    /// in the vocabulary feels like this, because the thing about to be
    /// recorded is one you'd hate to record by accident.
    func holdArmed(enabled: Bool) {
        guard enabled else { return }
        rigidGenerator.impactOccurred(intensity: 1.0)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            rigidGenerator.impactOccurred(intensity: 0.7)
        }
    }

    /// Distinct confirmation per outcome, so the pocket-scoring case still
    /// tells you what you just recorded.
    func feedback(for result: ApplyResult, enabled: Bool) {
        guard enabled else { return }

        if !result.runs.isEmpty {
            notificationGenerator.notificationOccurred(.success)
            return
        }
        if result.halfInningEnded {
            notificationGenerator.notificationOccurred(.success)
            return
        }
        if result.outsRecorded > 0 {
            rigidGenerator.impactOccurred()
            return
        }
        if let appearance = result.plateAppearance, appearance.outcome.isHit {
            mediumGenerator.impactOccurred(intensity: 1.0)
            return
        }
        lightGenerator.impactOccurred(intensity: 0.7)
    }
}
