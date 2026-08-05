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

    static let ball = Color(hex: 0x35E08D)
    static let calledStrike = Color(hex: 0xFFA94D)
    static let miss = Color(hex: 0xFF5C7A)
    static let foul = Color(hex: 0xFFD84D)
    static let inPlay = Color(hex: 0x4CC9FF)
    static let hitByPitch = Color(hex: 0xB892FF)
    static let neutral = Color(hex: 0x8E97A8)

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

    // MARK: - Ground

    /// The app sits on a lit gradient rather than flat black — night sky at the
    /// top, stadium glow toward the bottom where your hands are. Flat neutral
    /// grey is safe and reads as dead; a ground with depth is what makes the
    /// frosted panels above it look like they're floating.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [skyTop, skyMid, skyBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let skyTop = dynamic(
        light: UIColor(hex: 0xEEF3F9),
        dark: UIColor(hex: 0x080D17)
    )

    static let skyMid = dynamic(
        light: UIColor(hex: 0xE2ECF6),
        dark: UIColor(hex: 0x0D1E33)
    )

    static let skyBottom = dynamic(
        light: UIColor(hex: 0xD3E4F2),
        dark: UIColor(hex: 0x143650)
    )

    /// A soft pool of light behind the scoreboard. Sells the depth more than
    /// the gradient does on its own.
    static var stadiumGlow: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(0.16), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 420
        )
    }

    // MARK: - Surfaces

    /// The flat fallbacks, still used where a material would be wrong — inside
    /// dense grids, behind sheets, as chip fills.
    static let background = dynamic(
        light: UIColor(hex: 0xEDF2F8),
        dark: UIColor(hex: 0x080D17)
    )

    static let surface = dynamic(
        light: UIColor(white: 1, alpha: 1),
        dark: UIColor(hex: 0x121B29)
    )

    static let surfaceRaised = dynamic(
        light: UIColor(white: 0.94, alpha: 1),
        dark: UIColor(hex: 0x1B2839)
    )

    static let surfaceHigh = dynamic(
        light: UIColor(white: 0.90, alpha: 1),
        dark: UIColor(hex: 0x27384D)
    )

    static let hairline = dynamic(
        light: UIColor(white: 0.84, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.10)
    )

    /// The body of a tinted control — dark and translucent, so the lit ground
    /// still shows through and the tint reads as light rather than paint.
    static let controlBody = dynamic(
        light: UIColor(white: 1, alpha: 0.72),
        dark: UIColor(hex: 0x0C1420).withAlphaComponent(0.62)
    )

    /// Panel edges catch the light at the top and fall away at the bottom,
    /// which is what makes a flat rectangle read as a pane of glass.
    static var glassEdge: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.22),
                Color.white.opacity(0.06),
                Color.white.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

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
        light: UIColor(red: 0.78, green: 0.91, blue: 0.79, alpha: 1),
        dark: UIColor(hex: 0x1F4229)
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
    /// Standard panel: frosted glass over the lit ground, with an edge that
    /// catches the light at the top. One treatment for every card in the app,
    /// so nothing looks bolted on.
    func scorecardSurface(
        cornerRadius: CGFloat = Theme.Metrics.cornerRadius,
        fill: Color = Theme.surface
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill.opacity(0.28))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.glassEdge, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    /// A tinted control: the color as light rather than as paint. A dark
    /// translucent body, a wash of the hue, a bright rim, bright text, and a
    /// bloom underneath.
    ///
    /// Six solid saturated rectangles in a row read as a toy. The same six lit
    /// from within read as instruments, and the color still means what it meant.
    ///
    /// Deliberately *not* `.ultraThinMaterial`: a screen can carry seventeen of
    /// these, and seventeen live blur passes is a real frame cost for an effect
    /// that's invisible over a smooth gradient. The big panels get the real
    /// frosting; controls get a translucent fill that looks the same here.
    func luminousFill(
        _ tint: Color,
        cornerRadius: CGFloat = 12,
        isProminent: Bool = false
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.controlBody)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(isProminent ? 0.40 : 0.20))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(isProminent ? 0.9 : 0.55), lineWidth: 1)
        )
        .shadow(color: tint.opacity(isProminent ? 0.45 : 0.22), radius: isProminent ? 14 : 8, y: 3)
    }

    /// Same idea for anything round.
    func luminousCircle(_ tint: Color, isProminent: Bool = false) -> some View {
        background {
            Circle()
                .fill(Theme.controlBody)
                .overlay(Circle().fill(tint.opacity(isProminent ? 0.40 : 0.20)))
        }
        .overlay(
            Circle().strokeBorder(tint.opacity(isProminent ? 0.9 : 0.55), lineWidth: 1)
        )
        .shadow(color: tint.opacity(isProminent ? 0.45 : 0.22), radius: isProminent ? 14 : 8, y: 3)
    }

    /// Same idea again, for pills.
    func luminousCapsule(_ tint: Color, isProminent: Bool = false) -> some View {
        background {
            Capsule()
                .fill(Theme.controlBody)
                .overlay(Capsule().fill(tint.opacity(isProminent ? 0.30 : 0.14)))
        }
        .overlay(
            Capsule().strokeBorder(tint.opacity(isProminent ? 0.8 : 0.40), lineWidth: 1)
        )
    }

    /// A bloom around something that should look lit from within.
    func glow(_ tint: Color, radius: CGFloat = 12, opacity: Double = 0.55) -> some View {
        shadow(color: tint.opacity(opacity), radius: radius)
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
