import SwiftUI

/// "What do you want to track?" — the screen that decides how much UI the live
/// scoring screen has to carry.
///
/// Turning something off removes the control rather than greying it out, which
/// is the whole point: fewer things to hit means less looking.
///
/// Built out of plain cards rather than a grouped `Form`, because a stock
/// settings list drags its own light-mode chrome and inset styling along with
/// it and makes the app look like every other app.
struct TrackingSettingsView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsGroup(
                        "What do you want to track?",
                        footer: "Turn off anything you don't need — the live scoring screen adapts instantly."
                    ) {
                        SettingsToggle(
                            "Pitch velocity",
                            detail: "Log MPH on every pitch",
                            isOn: $store.settings.trackPitchVelocity
                        )
                        SettingsToggle(
                            "Ball location",
                            detail: "Mark where the ball went, for the spray chart",
                            isOn: $store.settings.trackBallLocation
                        )
                        SettingsToggle(
                            "Pitch type",
                            detail: "FB, SL, CH …",
                            isOn: $store.settings.trackPitchType
                        )
                        SettingsToggle(
                            "Foul & pitch counts",
                            detail: "Running foul tally per at-bat",
                            isOn: $store.settings.trackFoulAndPitchCounts
                        )
                        SettingsToggle(
                            "Strike-zone location",
                            detail: "Where it crossed the plate",
                            isOn: $store.settings.trackPitchLocation
                        )
                        SettingsToggle(
                            "Ball-strike challenges",
                            detail: "Review a call right after it's made",
                            isOn: $store.settings.trackChallenges
                        )
                    }

                    SettingsGroup("Appearance") {
                        SegmentedRow(
                            options: AppAppearance.allCases,
                            selection: $store.settings.appearance,
                            label: \.label
                        )
                    }

                    SettingsGroup("Notation detail") {
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

                    SettingsGroup("Layout") {
                        ForEach(ScoringLayout.allCases) { layout in
                            ChoiceRow(
                                title: layout.shortTitle,
                                subtitle: layout.title,
                                isSelected: store.settings.preferredLayout == layout
                            ) {
                                store.settings.preferredLayout = layout
                            }
                        }
                    }

                    SettingsGroup(
                        "One-handed mode",
                        footer: "Ball flicks left, strike flicks right — the way the count is written. That mapping doesn't mirror."
                    ) {
                        SegmentedRow(
                            options: Handedness.allCases,
                            selection: $store.settings.handedness,
                            label: \.label
                        )
                        SettingsToggle(
                            "Haptic feedback",
                            detail: "Feel each zone and every result",
                            isOn: $store.settings.hapticsEnabled
                        )
                        SettingsToggle(
                            "Speak confirmations",
                            detail: "Says the call out loud, ducks other audio",
                            isOn: $store.settings.spokenConfirmations
                        )
                        SettingsToggle(
                            "Drag straight to an out",
                            detail: "Releasing the dial on a fielder scores it as an out with no result ring",
                            isOn: $store.settings.assumeOutOnDialRelease
                        )
                    }

                    SettingsGroup("Rules") {
                        InfoRow("Regulation innings", "\(store.document.rules.regulationInnings)")
                        InfoRow(
                            "Designated hitter",
                            store.document.rules.usesDesignatedHitter ? "Yes" : "No"
                        )
                        InfoRow("Challenges per team", "\(store.document.rules.challengesPerTeam)")
                        InfoRow(
                            "Challenges left",
                            "\(store.teams.away.abbreviation) \(store.challengesRemaining.away)  ·  "
                                + "\(store.teams.home.abbreviation) \(store.challengesRemaining.home)"
                        )
                    }
                }
                .padding(.horizontal, Theme.Metrics.screenMargin)
                .padding(.vertical, 16)
            }
            .background(Theme.background)
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

// MARK: - Building blocks

/// A titled card. Rows inside are separated by hairlines rather than by gaps,
/// so a group reads as one object.
struct SettingsGroup<Content: View>: View {
    var title: String
    var footer: String?
    var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(title)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, Theme.Metrics.cardPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scorecardSurface()

            if let footer {
                Text(footer)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typeface.label(15))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.accent)
        .padding(.vertical, 11)
    }
}

struct ChoiceRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typeface.label(15))
                        .foregroundStyle(Theme.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typeface.caption())
                            .foregroundStyle(Theme.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InfoRow: View {
    var label: String
    var value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typeface.label(15))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.Typeface.label(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}

/// A pill-style segmented control, because the stock one can't be made to sit
/// quietly on a dark card.
struct SegmentedRow<Option: Hashable & Identifiable>: View {
    var options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(Theme.Typeface.label(13, weight: .semibold))
                        .foregroundStyle(
                            selection == option ? Theme.background : Theme.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == option ? Theme.accent : Theme.surfaceRaised)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }
}
