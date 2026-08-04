import SwiftUI
import UIKit

/// Colors and metrics shared by every screen.
///
/// The scoring colors are fixed in both appearances on purpose: green always
/// means ball, red always means swinging strike. Muscle memory beats theming.
enum Theme {

    // MARK: - Action colors

    static let ball = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let calledStrike = Color(red: 0.96, green: 0.47, blue: 0.19)
    static let miss = Color(red: 0.89, green: 0.22, blue: 0.27)
    static let foul = Color(red: 0.94, green: 0.78, blue: 0.20)
    static let inPlay = Color(red: 0.20, green: 0.55, blue: 0.98)
    static let hitByPitch = Color(red: 0.61, green: 0.42, blue: 0.93)
    static let neutral = Color(red: 0.45, green: 0.47, blue: 0.52)

    static func color(for outcome: PitchOutcome) -> Color {
        switch outcome {
        case .ball: ball
        case .calledStrike: calledStrike
        case .swingingStrike: miss
        case .foul: foul
        case .inPlay: inPlay
        case .hitByPitch: hitByPitch
        case .wildPitch, .passedBall: neutral
        }
    }

    // MARK: - Surfaces

    static let background = dynamic(
        light: UIColor(white: 0.97, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)
    )

    static let surface = dynamic(
        light: .white,
        dark: UIColor(red: 0.086, green: 0.090, blue: 0.102, alpha: 1)
    )

    static let surfaceRaised = dynamic(
        light: UIColor(white: 0.98, alpha: 1),
        dark: UIColor(red: 0.129, green: 0.133, blue: 0.149, alpha: 1)
    )

    static let hairline = dynamic(
        light: UIColor(white: 0.88, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.10)
    )

    static let primaryText = dynamic(light: UIColor(white: 0.07, alpha: 1), dark: .white)

    static let secondaryText = dynamic(
        light: UIColor(white: 0.45, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.55)
    )

    static let fieldGrass = dynamic(
        light: UIColor(red: 0.78, green: 0.89, blue: 0.79, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.24, blue: 0.17, alpha: 1)
    )

    static let fieldDirt = dynamic(
        light: UIColor(red: 0.85, green: 0.72, blue: 0.60, alpha: 1),
        dark: UIColor(red: 0.32, green: 0.24, blue: 0.19, alpha: 1)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Metrics

    enum Metrics {
        /// Diameter of the primary pad in the thumb cluster.
        static let primaryPad: CGFloat = 92
        static let secondaryPad: CGFloat = 74
        /// How far a finger must travel before a touch counts as a flick.
        static let flickThreshold: CGFloat = 26
        static let cornerRadius: CGFloat = 18
        static let cardPadding: CGFloat = 14
    }

    // MARK: - Type

    enum Typeface {
        static func score(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
        }

        static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func caption() -> Font {
            .system(size: 11, weight: .semibold, design: .rounded)
        }
    }
}

extension View {
    /// Standard card treatment used across the dense sheet layout.
    func scorecardSurface(cornerRadius: CGFloat = Theme.Metrics.cornerRadius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}
