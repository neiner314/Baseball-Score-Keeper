import SwiftUI

/// One thumb key that captures both the pitch type and its velocity in a
/// single continuous gesture.
///
/// Press and the pitcher's arsenal fans out in an arc above the pad, leaning
/// toward the middle of the screen where the thumb naturally travels. Slide
/// toward a pitch and it lights up. Stay on it for a beat and the pad locks to
/// that pitch and turns into a velocity scrubber: a number appears beside the
/// thumb, and sweeping up the arc raises it, down lowers it. Lift, and both are
/// armed for the next pitch recorded.
///
/// This replaces the old "pitch detail" menu, which asked for two separate taps
/// out of scrolling preset rows and was too slow to be worth using live.
struct PitchTypeVelocityPad: View {
    /// The pitches this pitcher throws, most-thrown first. Laid out clockwise
    /// around the top of the pad in that order.
    var arsenal: [PitchType]
    var tracksType: Bool
    var tracksVelocity: Bool
    var diameter: CGFloat = 76
    /// +1 for a right thumb (cluster in the bottom-right), -1 for a left. The
    /// fan and the velocity bubble lean the opposite way, toward centre.
    var mirror: CGFloat = 1
    var hapticsEnabled: Bool = true
    /// What's armed right now, drawn at rest so the scorer can see it without
    /// pressing.
    var armedType: PitchType?
    var armedVelocity: Int?
    /// Called on release with whatever was chosen. A nil type means velocity
    /// only; a nil velocity means the thumb lifted before scrubbing one.
    var onCommit: (PitchType?, Int?) -> Void
    /// A tap that never chose anything clears what's armed.
    var onClear: () -> Void

    private enum Phase { case idle, selecting, velocity }

    @State private var phase: Phase = .idle
    /// Thumb offset from the pad centre, in screen points (down is +y).
    @State private var finger: CGSize = .zero
    @State private var didMove = false
    @State private var selection: PitchType?
    @State private var lockedType: PitchType?
    @State private var liveVelocity = Self.baseVelocity
    /// The thumb's vertical offset at the moment velocity mode began, so the
    /// scrubber measures change from where the finger already was rather than
    /// jumping.
    @State private var anchorY: CGFloat = 0
    @State private var lockTask: Task<Void, Never>?

    private static let baseVelocity = 90
    private static let minVelocity = 55
    private static let maxVelocity = 106
    /// Screen points of thumb travel per mph. A full comfortable arc is ~120pt,
    /// which at this rate covers the whole believable range.
    private static let pointsPerMph: CGFloat = 3.2

    private let selectThreshold: CGFloat = 30
    private let lockDelay: Double = 0.32

    private var fanRadius: CGFloat { diameter / 2 + 42 }
    private var isActive: Bool { phase != .idle }

    var body: some View {
        padSurface
            .overlay(alignment: .center) { fanOverlay }
            .overlay(alignment: .center) { velocityBubble }
            .contentShape(Circle())
            .gesture(gesture)
            .zIndex(isActive ? 30 : 0)
            .accessibilityElement()
            .accessibilityLabel(Text("Pitch type and velocity"))
            .accessibilityValue(Text(restLabel))
            .accessibilityHint(Text("Swipe to a pitch, hold to set its speed"))
            .accessibilityActions {
                ForEach(arsenal, id: \.self) { type in
                    Button(type.abbreviation) { onCommit(type, nil) }
                }
                Button("Clear") { onClear() }
            }
    }

    // MARK: - Pad

    private var padSurface: some View {
        ZStack {
            Circle()
                .fill(Theme.controlBody)
                .overlay(Circle().fill(padTint.opacity(isActive ? 0.34 : 0.16)))
                .overlay(Circle().strokeBorder(padTint.opacity(isActive ? 0.9 : 0.5), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .glow(padTint, radius: isActive ? 16 : 8, opacity: isActive ? 0.55 : 0.3)

            padContents
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isActive ? 1.05 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isActive)
    }

    @ViewBuilder
    private var padContents: some View {
        switch phase {
        case .velocity:
            VStack(spacing: 1) {
                if let lockedType {
                    Text(lockedType.abbreviation)
                        .font(Theme.Typeface.label(12, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text("MPH")
                    .font(Theme.Typeface.overline(8))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .selecting:
            Text("SWIPE")
                .font(Theme.Typeface.overline(9))
                .tracking(1.2)
                .foregroundStyle(padTint)
        case .idle:
            restContents
        }
    }

    @ViewBuilder
    private var restContents: some View {
        if armedType != nil || armedVelocity != nil {
            VStack(spacing: 1) {
                Text(armedType?.abbreviation ?? "—")
                    .font(Theme.Typeface.label(15, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                if let armedVelocity {
                    Text("\(armedVelocity)")
                        .font(Theme.Typeface.score(12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        } else {
            VStack(spacing: 1) {
                Text(tracksType ? "PITCH" : "SPEED")
                    .font(Theme.Typeface.overline(9))
                    .tracking(1.2)
                if tracksType {
                    Text("TYPE")
                        .font(Theme.Typeface.overline(9))
                        .tracking(1.2)
                }
            }
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var padTint: Color {
        (armedType != nil || armedVelocity != nil || isActive) ? Theme.accent : Theme.neutral
    }

    private var restLabel: String {
        var parts: [String] = []
        if let armedType { parts.append(armedType.abbreviation) }
        if let armedVelocity { parts.append("\(armedVelocity)") }
        return parts.isEmpty ? "not set" : parts.joined(separator: " ")
    }

    // MARK: - Fan of arsenal chips

    @ViewBuilder
    private var fanOverlay: some View {
        if phase != .idle && tracksType {
            ZStack {
                ForEach(Array(arsenal.enumerated()), id: \.element) { index, type in
                    let offset = chipOffset(index: index, count: arsenal.count)
                    ArsenalChip(
                        type: type,
                        isHighlighted: (phase == .velocity ? lockedType : selection) == type,
                        isDimmed: phase == .velocity && lockedType != type
                    )
                    .offset(x: offset.width, y: offset.height)
                }
            }
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    /// Chips spread across a ~200° arc over the top of the pad. The arc leans
    /// toward the screen's centre — up and inward — so the labels sit where the
    /// thumb can flick to them and never off the near edge.
    private func chipOffset(index: Int, count: Int) -> CGSize {
        let angle = chipAngle(index: index, count: count)
        return CGSize(
            width: cos(angle) * fanRadius * mirror,
            height: -sin(angle) * fanRadius
        )
    }

    /// Radians, math convention (0 = toward centre-side horizontal, +π/2 = up).
    private func chipAngle(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return .pi / 2 }
        let start: CGFloat = 20 * .pi / 180    // just above the inward horizontal
        let end: CGFloat = 200 * .pi / 180     // just past straight up, outward
        let t = CGFloat(index) / CGFloat(count - 1)
        return start + t * (end - start)
    }

    // MARK: - Velocity bubble

    @ViewBuilder
    private var velocityBubble: some View {
        if phase == .velocity {
            Text("\(liveVelocity)")
                .font(Theme.Typeface.score(22))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.accent))
                .shadow(color: Theme.accent.opacity(0.5), radius: 10, y: 2)
                // Ride alongside the thumb, nudged toward centre so the number
                // clears the fingertip rather than hiding under it.
                .offset(x: finger.width - 46 * mirror, y: finger.height)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Gesture

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if phase == .idle { begin() }
                finger = value.translation
                if hypot(value.translation.width, value.translation.height) > 6 { didMove = true }

                switch phase {
                case .selecting: updateSelection()
                case .velocity: updateVelocity()
                case .idle: break
                }
            }
            .onEnded { _ in end() }
    }

    private func begin() {
        didMove = false
        selection = nil
        lockedType = nil
        liveVelocity = Self.baseVelocity
        Haptics.shared.tap(enabled: hapticsEnabled)

        if tracksType {
            phase = .selecting
        } else {
            // Velocity-only: no type to pick, so the scrubber is live at once.
            phase = .velocity
            anchorY = 0
        }
    }

    private func updateSelection() {
        let hit = selectionForCurrentFinger()
        guard hit != selection else { return }
        selection = hit
        if hit != nil { Haptics.shared.zoneChanged(enabled: hapticsEnabled) }
        scheduleLock()
    }

    /// The arsenal pitch whose angle is closest to the thumb's, once the thumb
    /// is far enough out to count as a swipe. Nil near the centre.
    private func selectionForCurrentFinger() -> PitchType? {
        guard hypot(finger.width, finger.height) >= selectThreshold, !arsenal.isEmpty else {
            return nil
        }
        // Undo the mirror so the comparison is always in the chips' own frame.
        let fingerAngle = atan2(-finger.height, finger.width * mirror)
        var best: PitchType?
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for (index, type) in arsenal.enumerated() {
            let delta = angularDistance(fingerAngle, chipAngle(index: index, count: arsenal.count))
            if delta < bestDelta {
                bestDelta = delta
                best = type
            }
        }
        return best
    }

    private func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var delta = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta = 2 * .pi - delta }
        return delta
    }

    /// Arms the velocity scrubber once the thumb has dwelled on one pitch.
    /// Restarts whenever the selection changes, so sliding across the fan never
    /// locks the wrong pitch.
    private func scheduleLock() {
        lockTask?.cancel()
        guard tracksVelocity, let target = selection else { return }
        lockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(lockDelay * 1_000_000_000))
            guard !Task.isCancelled, phase == .selecting, selection == target else { return }
            lock(on: target)
        }
    }

    private func lock(on type: PitchType) {
        lockedType = type
        anchorY = finger.height
        liveVelocity = Self.baseVelocity
        withAnimation(.easeOut(duration: 0.15)) { phase = .velocity }
        Haptics.shared.holdArmed(enabled: hapticsEnabled)
    }

    private func updateVelocity() {
        // Up the screen is more negative y, so a smaller y than the anchor is a
        // higher speed — exactly "the higher you move your thumb, the bigger."
        let delta = Int(((anchorY - finger.height) / Self.pointsPerMph).rounded())
        let value = min(max(Self.baseVelocity + delta, Self.minVelocity), Self.maxVelocity)
        guard value != liveVelocity else { return }
        liveVelocity = value
        Haptics.shared.zoneChanged(enabled: hapticsEnabled)
    }

    private func end() {
        lockTask?.cancel()
        lockTask = nil

        switch phase {
        case .velocity:
            if lockedType == nil && !didMove {
                // Velocity-only tap that never scrubbed: treat as a clear.
                Haptics.shared.cancelled(enabled: hapticsEnabled)
                onClear()
            } else {
                Haptics.shared.commit(enabled: hapticsEnabled)
                onCommit(lockedType, liveVelocity)
            }
        case .selecting:
            if let selection {
                Haptics.shared.commit(enabled: hapticsEnabled)
                onCommit(selection, nil)
            } else {
                Haptics.shared.cancelled(enabled: hapticsEnabled)
                onClear()
            }
        case .idle:
            break
        }

        reset()
    }

    private func reset() {
        phase = .idle
        finger = .zero
        didMove = false
        selection = nil
        lockedType = nil
    }
}

/// One pitch in the fan.
private struct ArsenalChip: View {
    var type: PitchType
    var isHighlighted: Bool
    var isDimmed: Bool

    var body: some View {
        Text(type.abbreviation)
            .font(Theme.Typeface.label(13, weight: .heavy))
            .foregroundStyle(isHighlighted ? .white : Theme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(Theme.controlBody)
                    .overlay(Capsule().fill(Theme.accent.opacity(isHighlighted ? 0.9 : 0.18)))
            }
            .overlay(
                Capsule().strokeBorder(Theme.accent.opacity(isHighlighted ? 0 : 0.55), lineWidth: 1.5)
            )
            .scaleEffect(isHighlighted ? 1.16 : 1)
            .opacity(isDimmed ? 0.35 : 1)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .glow(Theme.accent, radius: isHighlighted ? 14 : 0, opacity: isHighlighted ? 0.7 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isHighlighted)
            .animation(.easeOut(duration: 0.15), value: isDimmed)
    }
}
