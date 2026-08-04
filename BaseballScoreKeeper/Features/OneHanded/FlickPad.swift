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

/// A single thumb key that resolves to one of five actions.
///
/// Press and the options fan out around your thumb; slide toward one and it
/// lights up and ticks; lift to commit. Lifting on a direction with no option
/// cancels, so an accidental drag off the pad costs nothing.
struct FlickPad: View {
    var title: String
    var diameter: CGFloat = Theme.Metrics.primaryPad
    var options: [FlickDirection: FlickOption]
    var hapticsEnabled: Bool = true
    var isProminent: Bool = false
    var onCommit: (FlickDirection) -> Void

    @State private var isPressing = false
    @State private var current: FlickDirection = .center

    private var threshold: CGFloat { Theme.Metrics.flickThreshold }
    private var restingOption: FlickOption? { options[.center] }
    private var activeOption: FlickOption? { options[current] }

    var body: some View {
        padSurface
            .overlay(alignment: .center) { fanOverlay }
            .contentShape(Circle())
            .gesture(flickGesture)
            .zIndex(isPressing ? 20 : 0)
            .accessibilityElement()
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text("Tap, or flick toward an option"))
            .accessibilityActions {
                ForEach(FlickDirection.allCases, id: \.self) { direction in
                    if let option = options[direction] {
                        Button(option.title) { onCommit(direction) }
                    }
                }
            }
    }

    // MARK: - Pad

    private var padSurface: some View {
        ZStack {
            Circle()
                .fill(padFill)
                .overlay(
                    Circle().strokeBorder(
                        isProminent ? Theme.inPlay : Color.clear,
                        lineWidth: 2
                    )
                )
                .shadow(color: .black.opacity(isPressing ? 0.35 : 0.2), radius: isPressing ? 14 : 8, y: 4)

            Text(title)
                .font(Theme.Typeface.label(diameter > 84 ? 15 : 13, weight: .bold))
                .foregroundStyle(isProminent ? Theme.inPlay : .white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPressing ? 1.06 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressing)
    }

    private var padFill: Color {
        if isProminent {
            return Theme.inPlay.opacity(0.16)
        }
        return restingOption?.tint ?? Theme.neutral
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
                            isActive: current == direction
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
                }
                let direction = FlickDirection.from(translation: value.translation, threshold: threshold)
                guard direction != current else { return }
                current = direction
                if options[direction] != nil {
                    Haptics.shared.zoneChanged(enabled: hapticsEnabled)
                }
            }
            .onEnded { _ in
                let committed = current
                isPressing = false
                current = .center

                guard options[committed] != nil else {
                    Haptics.shared.cancelled(enabled: hapticsEnabled)
                    return
                }
                Haptics.shared.commit(enabled: hapticsEnabled)
                onCommit(committed)
            }
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
