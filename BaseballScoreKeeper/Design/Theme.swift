import SwiftUI
import UIKit

/// Colors, metrics and type shared by every screen.
///
/// The app is dark by default. A scorebook is read in a dim stadium bowl or a
/// dark living room, and a white sheet at night is a flashlight in the face.
///
/// The canvas is deliberately neutral — near-black greys with no tint — so the
/// six action colors are the only saturated things on screen. That is what
/// makes a glance work: if everything is colorful, nothing reads.
///
/// The scoring colors are fixed in both appearances on purpose: green always
/// means ball, rose always means swinging strike. Muscle memory beats theming.
enum Theme {

    // MARK: - Action colors

    static let ball = Color(hex: 0x2FD98A)
    static let calledStrike = Color(hex: 0xFF9F45)
    static let miss = Color(hex: 0xFF4D6A)
    static let foul = Color(hex: 0xFFD93D)
    static let inPlay = Color(hex: 0x3FB9FF)
    static let hitByPitch = Color(hex: 0xB08CFF)
    static let neutral = Color(hex: 0x8A8F9A)

    /// The one non-semantic accent, used for selection and emphasis. Same hue
    /// as `inPlay` so the palette stays at six ideas rather than seven.
    static let accent = inPlay

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

    /// Four steps of elevation, and no more. Every panel in the app is one of
    /// these; anything that needs to stand out further earns a border, not a
    /// fifth grey.
    static let background = dynamic(
        light: UIColor(white: 0.96, alpha: 1),
        dark: UIColor(hex: 0x0A0B0D)
    )

    static let surface = dynamic(
        light: .white,
        dark: UIColor(hex: 0x131519)
    )

    static let surfaceRaised = dynamic(
        light: UIColor(white: 0.94, alpha: 1),
        dark: UIColor(hex: 0x1C1F25)
    )

    static let surfaceHigh = dynamic(
        light: UIColor(white: 0.90, alpha: 1),
        dark: UIColor(hex: 0x272B33)
    )

    static let hairline = dynamic(
        light: UIColor(white: 0.86, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.09)
    )

    static let primaryText = dynamic(light: UIColor(white: 0.06, alpha: 1), dark: .white)

    static let secondaryText = dynamic(
        light: UIColor(white: 0.42, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.56)
    )

    /// For labels that are present but should never compete — units, hints,
    /// empty-state placeholders.
    static let tertiaryText = dynamic(
        light: UIColor(white: 0.62, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.30)
    )

    static let fieldGrass = dynamic(
        light: UIColor(red: 0.80, green: 0.90, blue: 0.81, alpha: 1),
        dark: UIColor(hex: 0x16241B)
    )

    static let fieldDirt = dynamic(
        light: UIColor(red: 0.86, green: 0.74, blue: 0.62, alpha: 1),
        dark: UIColor(hex: 0x2E2119)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Metrics

    enum Metrics {
        /// Diameter of the primary pad in the thumb cluster.
        static let primaryPad: CGFloat = 96
        static let secondaryPad: CGFloat = 72
        /// How far a finger must travel before a touch counts as a flick.
        static let flickThreshold: CGFloat = 26
        static let cornerRadius: CGFloat = 20
        static let tightRadius: CGFloat = 12
        static let cardPadding: CGFloat = 16
        static let screenMargin: CGFloat = 18
    }

    // MARK: - Type

    enum Typeface {
        /// Numerals that have to line up in a column and not jump as they
        /// change: scores, counts, velocities.
        static func score(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
        }

        /// The oversized score readout on the scoreboard bar.
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
        }

        static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func caption() -> Font {
            .system(size: 11, weight: .semibold, design: .rounded)
        }

        /// Small all-caps section headers. Tracked out so they read as
        /// structure rather than as content.
        static func overline(_ size: CGFloat = 10) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        /// Scorebook cells, where a fielding chain like 6-4-3 has to stay
        /// legible at eleven points.
        static func notation(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
    }
}

// MARK: - Shared treatments

extension View {
    /// Standard panel: a raised surface with a hairline edge. One treatment for
    /// every card in the app, so nothing looks bolted on.
    func scorecardSurface(
        cornerRadius: CGFloat = Theme.Metrics.cornerRadius,
        fill: Color = Theme.surface
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }

    /// Section header treatment: small, tracked, quiet.
    func overlineStyle() -> some View {
        font(Theme.Typeface.overline())
            .tracking(1.4)
            .foregroundStyle(Theme.tertiaryText)
    }
}

/// An all-caps section label with the standard treatment.
struct Overline: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .overlineStyle()
    }
}

extension AppAppearance {
    /// nil hands the decision back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
