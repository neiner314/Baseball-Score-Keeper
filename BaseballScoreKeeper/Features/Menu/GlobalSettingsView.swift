import SwiftUI

/// App-wide defaults, edited from the main menu when no game is open.
///
/// These are the same knobs the in-game settings screen offers, minus anything
/// that only means something mid-game (challenges remaining, the rulebook).
/// Whatever's set here is what a new game starts from, and the look applies at
/// once across the whole app.
struct GlobalSettingsView: View {
    @Binding var appearance: AppAppearance

    @State private var settings = AppPreferences.defaultTrackingSettings
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.default.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsGroup("Appearance") {
                    SegmentedRow(
                        options: AppAppearance.allCases,
                        selection: $settings.appearance,
                        label: \.label
                    )
                }

                SettingsGroup("Language") {
                    ForEach(AppLanguage.allCases) { language in
                        ChoiceRow(
                            title: language.label,
                            subtitle: nil,
                            isSelected: languageCode == language.rawValue
                        ) {
                            languageCode = language.rawValue
                        }
                    }
                }

                SettingsGroup(
                    "Default layout",
                    footer: "The scoring screen a new game opens with. You can still switch mid-game."
                ) {
                    ForEach(ScoringLayout.allCases) { layout in
                        ChoiceRow(
                            title: layout.shortTitle,
                            subtitle: layout.title,
                            isSelected: settings.preferredLayout == layout
                        ) {
                            settings.preferredLayout = layout
                        }
                    }
                }

                SettingsGroup(
                    "What to track",
                    footer: "Turn off anything you don't need — the scoring screen drops the control for it."
                ) {
                    SettingsToggle("Pitch velocity", detail: "Log MPH on every pitch", isOn: $settings.trackPitchVelocity)
                    SettingsToggle("Pitch type", detail: "FB, SL, CH …", isOn: $settings.trackPitchType)
                    SettingsToggle("Ball location", detail: "Mark where the ball went, for the spray chart", isOn: $settings.trackBallLocation)
                    SettingsToggle("Foul & pitch counts", detail: "Running foul tally per at-bat", isOn: $settings.trackFoulAndPitchCounts)
                    SettingsToggle("Ball-strike challenges", detail: "Review a call right after it's made", isOn: $settings.trackChallenges)
                }

                SettingsGroup(
                    "One-handed mode",
                    footer: "Ball flicks left, strike flicks right — the way the count is written. That mapping doesn't mirror."
                ) {
                    SegmentedRow(
                        options: Handedness.allCases,
                        selection: $settings.handedness,
                        label: \.label
                    )
                    SettingsToggle("Haptic feedback", detail: "Feel each zone and every result", isOn: $settings.hapticsEnabled)
                    SettingsToggle("Speak confirmations", detail: "Says the call out loud, ducks other audio", isOn: $settings.spokenConfirmations)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenMargin)
            .padding(.vertical, 16)
        }
        .appBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings) { _, newValue in
            AppPreferences.defaultTrackingSettings = newValue
            appearance = newValue.appearance
        }
    }
}

/// The language the whole app renders in, chosen in Settings and applied live at
/// the root by overriding the environment locale.
///
/// The cases match the localizations shipped in the string catalog. Each
/// language names itself in its own tongue, so it's findable no matter what the
/// app currently reads as.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case japanese = "ja"
    case korean = "ko"

    static let storageKey = "appLanguage"

    /// The language a fresh install starts in, before anything's been chosen.
    static let `default` = AppLanguage.english

    var id: String { rawValue }

    /// The locale to push into the environment.
    var locale: Locale { Locale(identifier: rawValue) }

    /// The language's name in its own language, so a speaker can spot it.
    var label: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
}
