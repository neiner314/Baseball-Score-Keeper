import SwiftUI

/// The five zones of a flick key: rest, plus the four cardinal directions.
enum FlickDirection: String, CaseIterable, Hashable, Sendable {
    case center
    case up
    case down
    case left
    case right

    /// Classifies a drag. Anything shorter than `threshold` is a plain tap,
    /// and beyond that the dominant axis wins — the same rule a Japanese
    /// flick keyboard uses, which is what makes it learnable without looking.
    static func from(translation: CGSize, threshold: CGFloat) -> FlickDirection {
        let dx = translation.width
        let dy = translation.height
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= threshold else { return .center }

        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .down : .up
    }

    /// Unit offset used to lay the option chips out around the pad.
    var unitOffset: CGSize {
        switch self {
        case .center: CGSize(width: 0, height: 0)
        case .up: CGSize(width: 0, height: -1)
        case .down: CGSize(width: 0, height: 1)
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        }
    }

    var accessibilityName: String {
        switch self {
        case .center: "tap"
        case .up: "flick up"
        case .down: "flick down"
        case .left: "flick left"
        case .right: "flick right"
        }
    }
}

struct FlickOption: Hashable {
    var title: String
    var tint: Color

    init(_ title: String, tint: Color) {
        self.title = title
        self.tint = tint
    }
}

/// A single thumb key that resolves to one of five flick actions, plus an
/// optional press-and-hold.
///
/// Press and the options fan out around your thumb; slide toward one and it
/// lights up and ticks; lift to commit. Lifting on a direction with no option
/// cancels, so an accidental drag off the pad costs nothing.
///
/// The hold is for actions you'd hate to trigger by mistake. It needs the
/// thumb to stay still for `holdDuration`, shows a ring filling the whole
/// time, and thumps distinctly when it arms — and sliding away at any point
/// disarms it and hands the gesture back to the flick directions.
struct FlickPad: View {
    var title: String
    var diameter: CGFloat = Theme.Metrics.primaryPad
    var options: [FlickDirection: FlickOption]
    /// Set to enable press-and-hold. Nil means holding does nothing.
    var holdOption: FlickOption?
    var holdDuration: Double = 0.55
    /// Draws the direction colors around the pad's rim while at rest.
    var showsDirectionHints: Bool = false
    var hapticsEnabled: Bool = true
    var onCommit: (FlickDirection) -> Void
    var onHold: (() -> Void)?

    @State private var isPressing = false
    @State private var current: FlickDirection = .center
    @State private var isHoldArmed = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    /// A short grace period before the ring starts filling, so an ordinary
    /// quick tap doesn't flash a progress indicator every single pitch.
    private let holdLeadIn: Double = 0.15

    private var threshold: CGFloat { Theme.Metrics.flickThreshold }
    private var restingOption: FlickOption? { options[.center] }

    var body: some View {
        padSurface
            .overlay(alignment: .center) { fanOverlay }
            .contentShape(Circle())
            .gesture(flickGesture)
            .zIndex(isPressing ? 20 : 0)
            .accessibilityElement()
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text("Tap, flick toward an option, or hold"))
            .accessibilityActions {
                ForEach(FlickDirection.allCases, id: \.self) { direction in
                    if let option = options[direction] {
                        Button(option.title) { onCommit(direction) }
                    }
                }
                if let holdOption, let onHold {
                    Button(holdOption.title) { onHold() }
                }
            }
    }

    // MARK: - Pad

    private var padSurface: some View {
        ZStack {
            Circle()
                .fill(padFill)
                .overlay(Circle().strokeBorder(padStroke, lineWidth: 2))
                .shadow(color: .black.opacity(isPressing ? 0.35 : 0.2), radius: isPressing ? 14 : 8, y: 4)

            if showsDirectionHints && !isPressing {
                hintDots
            }

            holdRing

            Text(isHoldArmed ? (holdOption?.title ?? title) : title)
                .font(Theme.Typeface.label(diameter > 84 ? 15 : 13, weight: .bold))
                .foregroundStyle(labelColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressing ? 1.06 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressing)
        .animation(.easeOut(duration: 0.15), value: isHoldArmed)
    }

    private var padFill: Color {
        if isHoldArmed {
            return holdOption?.tint ?? Theme.hitByPitch
        }
        return (restingOption?.tint ?? Theme.neutral).opacity(0.20)
    }

    private var padStroke: Color {
        if isHoldArmed {
            return holdOption?.tint ?? Theme.hitByPitch
        }
        return restingOption?.tint ?? Theme.hairline
    }

    private var labelColor: Color {
        isHoldArmed ? .white : (restingOption?.tint ?? Theme.primaryText)
    }

    /// The four flick colors sitting on the rim where their gesture points, so
    /// "green is to the left" is readable before you ever press.
    private var hintDots: some View {
        ZStack {
            ForEach(FlickDirection.allCases.filter { $0 != .center }, id: \.self) { direction in
                if let option = options[direction] {
                    Circle()
                        .fill(option.tint)
                        .frame(width: 7, height: 7)
                        .offset(
                            x: direction.unitOffset.width * (diameter / 2 - 11),
                            y: direction.unitOffset.height * (diameter / 2 - 11)
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var holdRing: some View {
        if holdOption != nil, isPressing {
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(
                    holdOption?.tint ?? Theme.hitByPitch,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: diameter - 5, height: diameter - 5)
        }
    }

    // MARK: - Fan overlay

    /// How far the chips sit from the pad. Bounded rather than purely
    /// proportional so the outermost chip still fits on screen when the pad is
    /// parked in a bottom corner.
    private var horizontalFanDistance: CGFloat { min(max(diameter * 0.85, 68), 82) }
    private var verticalFanDistance: CGFloat { min(max(diameter * 0.78, 62), 74) }

    @ViewBuilder
    private var fanOverlay: some View {
        if isPressing {
            ZStack {
                ForEach(FlickDirection.allCases.filter { $0 != .center }, id: \.self) { direction in
                    if let option = options[direction] {
                        FlickChip(
                            option: option,
                            isActive: current == direction && !isHoldArmed
                        )
                        .offset(
                            x: direction.unitOffset.width * horizontalFanDistance,
                            y: direction.unitOffset.height * verticalFanDistance
                        )
                    }
                }
            }
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    // MARK: - Gesture

    private var flickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    Haptics.shared.tap(enabled: hapticsEnabled)
                    beginHold()
                }

                let direction = FlickDirection.from(translation: value.translation, threshold: threshold)
                guard direction != current else { return }
                current = direction

                // Any real movement means this isn't a hold.
                if direction != .center {
                    cancelHold()
                }
                if options[direction] != nil {
                    Haptics.shared.zoneChanged(enabled: hapticsEnabled)
                }
            }
            .onEnded { _ in
                let committed = current
                let wasArmed = isHoldArmed
                endPress()

                if wasArmed, let onHold {
                    Haptics.shared.commit(enabled: hapticsEnabled)
                    onHold()
                    return
                }

                guard options[committed] != nil else {
                    Haptics.shared.cancelled(enabled: hapticsEnabled)
                    return
                }
                Haptics.shared.commit(enabled: hapticsEnabled)
                onCommit(committed)
            }
    }

    // MARK: - Hold

    private func beginHold() {
        guard holdOption != nil, onHold != nil else { return }

        holdProgress = 0
        withAnimation(.linear(duration: holdDuration).delay(holdLeadIn)) {
            holdProgress = 1
        }

        holdTask = Task { @MainActor in
            let nanoseconds = UInt64((holdDuration + holdLeadIn) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            isHoldArmed = true
            Haptics.shared.holdArmed(enabled: hapticsEnabled)
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHoldArmed = false
        withAnimation(.easeOut(duration: 0.12)) {
            holdProgress = 0
        }
    }

    private func endPress() {
        holdTask?.cancel()
        holdTask = nil
        isPressing = false
        current = .center
        isHoldArmed = false
        holdProgress = 0
    }
}

/// One option in the fan.
private struct FlickChip: View {
    var option: FlickOption
    var isActive: Bool

    var body: some View {
        Text(option.title)
            .font(Theme.Typeface.label(13, weight: .bold))
            .foregroundStyle(isActive ? .white : option.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isActive ? option.tint : Theme.surfaceRaised)
            )
            .overlay(
                Capsule().strokeBorder(option.tint.opacity(isActive ? 0 : 0.6), lineWidth: 1.5)
            )
            .scaleEffect(isActive ? 1.14 : 1)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isActive)
    }
}
