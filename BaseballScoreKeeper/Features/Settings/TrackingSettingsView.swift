import SwiftUI

/// "What do you want to track?" — the screen that decides how much UI the live
/// scoring screen has to carry.
///
/// Turning something off removes the control rather than greying it out, which
/// is the whole point: fewer things to hit means less looking.
struct TrackingSettingsView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $store.settings.trackPitchVelocity) {
                        SettingLabel("Pitch velocity", detail: "Log MPH on every pitch")
                    }
                    Toggle(isOn: $store.settings.trackBallLocation) {
                        SettingLabel("Ball location / spray chart", detail: "Mark where the ball went")
                    }
                    Toggle(isOn: $store.settings.trackPitchType) {
                        SettingLabel("Pitch type", detail: "FB, SL, CH … plus a challenge flag")
                    }
                    Toggle(isOn: $store.settings.trackFoulAndPitchCounts) {
                        SettingLabel("Foul & pitch counts", detail: "Running foul tally per at-bat")
                    }
                    Toggle(isOn: $store.settings.trackPitchLocation) {
                        SettingLabel("Strike-zone location", detail: "Where it crossed the plate")
                    }
                    Toggle(isOn: $store.settings.trackChallenges) {
                        SettingLabel(
                            "Ball-strike challenges",
                            detail: "Review a call right after it's made"
                        )
                    }
                } header: {
                    Text("What do you want to track?")
                } footer: {
                    Text("Turn off anything you don't need — the live scoring screen adapts instantly.")
                }

                Section("Play notation detail") {
                    ForEach(NotationDetail.allCases) { option in
                        ChoiceRow(
                            title: option.title,
                            subtitle: option.subtitle,
                            isSelected: store.settings.notationDetail == option
                        ) {
                            store.settings.notationDetail = option
                        }
                    }
                }

                Section("Preferred layout") {
                    ForEach(ScoringLayout.allCases) { layout in
                        ChoiceRow(
                            title: layout.title,
                            subtitle: nil,
                            isSelected: store.settings.preferredLayout == layout
                        ) {
                            store.settings.preferredLayout = layout
                        }
                    }
                }

                Section("One-handed mode") {
                    Picker("Thumb", selection: $store.settings.handedness) {
                        ForEach(Handedness.allCases) { hand in
                            Text(hand.label).tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $store.settings.hapticsEnabled) {
                        SettingLabel("Haptic feedback", detail: "Feel each zone and every result")
                    }
                    Toggle(isOn: $store.settings.spokenConfirmations) {
                        SettingLabel("Speak confirmations", detail: "Says the call out loud, ducks other audio")
                    }
                    Toggle(isOn: $store.settings.assumeOutOnDialRelease) {
                        SettingLabel("Dial releases straight to an out", detail: "Skips the result ring — fastest no-look scoring")
                    }
                }

                Section("Rules") {
                    LabeledContent("Regulation innings", value: "\(store.document.rules.regulationInnings)")
                    LabeledContent("Designated hitter", value: store.document.rules.usesDesignatedHitter ? "Yes" : "No")
                    LabeledContent("Challenges per team", value: "\(store.document.rules.challengesPerTeam)")
                    LabeledContent(
                        "Challenges left",
                        value: "\(store.teams.away.abbreviation) \(store.challengesRemaining.away) · "
                            + "\(store.teams.home.abbreviation) \(store.challengesRemaining.home)"
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingLabel: View {
    var title: String
    var detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChoiceRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Theme.inPlay : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
