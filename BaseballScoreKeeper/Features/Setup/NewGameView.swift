import SwiftUI

/// Game setup. Everything is prefilled so a scorer who arrives at first pitch
/// can hit Start and fix the names between innings.
struct NewGameView: View {
    var onStart: (GameDocument) -> Void
    /// Opens straight into the league importer — the menu's "Import Game" tile.
    var startWithImport: Bool = false
    /// Pre-loads the away side, used when starting a game from a saved team.
    var initialAway: TeamRoster?

    @Environment(\.dismiss) private var dismiss

    @State private var away = GameFactory.placeholderRoster(name: "Away", abbreviation: "AWY")
    @State private var home = GameFactory.placeholderRoster(name: "Home", abbreviation: "HME")
    @State private var venue = ""
    @State private var usesDH = true
    @State private var regulationInnings = 9
    @State private var settings = AppPreferences.defaultTrackingSettings
    @State private var showsGameImport = false
    @State private var importingSide: Side?
    @State private var loadingSide: Side?
    @State private var importedSetup: RemoteGameSetup?
    @State private var didApplyInitial = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    title

                    SettingsGroup("Start from a league feed", footer: importFooter) {
                        ActionRow(
                            "Import a game",
                            detail: "Pulls both rosters and the posted lineup",
                            symbol: "arrow.down.circle"
                        ) {
                            showsGameImport = true
                        }
                    }

                    SettingsGroup("Teams") {
                        TeamFields(roster: $away, label: "Away")
                        Divider().overlay(Theme.hairline)
                        TeamFields(roster: $home, label: "Home")
                    }

                    SettingsGroup(
                        "Lineups",
                        footer: "Pasting works for any league — one line per player as number, name, position."
                    ) {
                        NavigationLink {
                            RosterEditorView(roster: $away)
                        } label: {
                            NavigationRowLabel(away.name, value: "\(away.players.count) players")
                        }
                        Divider().overlay(Theme.hairline)
                        NavigationLink {
                            RosterEditorView(roster: $home)
                        } label: {
                            NavigationRowLabel(home.name, value: "\(home.players.count) players")
                        }
                        Divider().overlay(Theme.hairline)
                        ActionRow("Load away from My Teams", symbol: "person.crop.rectangle.stack") {
                            loadingSide = .away
                        }
                        ActionRow("Load home from My Teams", symbol: "person.crop.rectangle.stack") {
                            loadingSide = .home
                        }
                        Divider().overlay(Theme.hairline)
                        ActionRow("Paste \(away.name) roster", symbol: "doc.on.clipboard") {
                            importingSide = .away
                        }
                        ActionRow("Paste \(home.name) roster", symbol: "doc.on.clipboard") {
                            importingSide = .home
                        }
                        Divider().overlay(Theme.hairline)
                        ActionRow("Save \(away.name) to My Teams", symbol: "square.and.arrow.down") {
                            saveToMyTeams(away)
                        }
                        ActionRow("Save \(home.name) to My Teams", symbol: "square.and.arrow.down") {
                            saveToMyTeams(home)
                        }
                    }

                    SettingsGroup("Rules") {
                        FieldRow(label: "Venue", placeholder: "Optional", text: $venue)
                        Divider().overlay(Theme.hairline)
                        SettingsToggle(
                            "Designated hitter",
                            detail: "The pitcher doesn't bat",
                            isOn: $usesDH
                        )
                        Divider().overlay(Theme.hairline)
                        StepperRow(
                            label: "Regulation innings",
                            value: $regulationInnings,
                            range: 3...12
                        )
                    }

                    SettingsGroup("Scoring style", footer: "You can change any of this mid-game.") {
                        SegmentedRow(
                            options: ScoringLayout.allCases,
                            selection: $settings.preferredLayout,
                            label: \.shortTitle
                        )
                        SegmentedRow(
                            options: Handedness.allCases,
                            selection: $settings.handedness,
                            label: \.label
                        )
                        SegmentedRow(
                            options: AppAppearance.allCases,
                            selection: $settings.appearance,
                            label: \.label
                        )
                    }

                    startButton
                }
                .padding(.horizontal, Theme.Metrics.screenMargin)
                .padding(.bottom, 32)
            }
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showsGameImport) {
                GameImportView { setup in
                    apply(setup)
                }
            }
            .sheet(item: $importingSide) { side in
                RosterImportView(teamLabel: side == .away ? "away roster" : "home roster") { roster in
                    setRoster(roster, for: side)
                }
            }
            .sheet(item: $loadingSide) { side in
                SavedTeamPickerView { roster in
                    setRoster(roster, for: side)
                }
            }
            .onAppear(perform: applyInitialState)
        }
    }

    /// Runs once: drops in a team started from the library, and jumps straight
    /// to the importer if that's the tile we came in on.
    private func applyInitialState() {
        guard !didApplyInitial else { return }
        didApplyInitial = true
        if let initialAway { away = initialAway }
        if startWithImport { showsGameImport = true }
    }

    private func setRoster(_ roster: TeamRoster, for side: Side) {
        switch side {
        case .away: away = roster
        case .home: home = roster
        }
    }

    private func saveToMyTeams(_ roster: TeamRoster) {
        Task { try? await TeamStore.shared.save(SavedTeam(roster: roster)) }
        Haptics.shared.commit(enabled: settings.hapticsEnabled)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEW GAME")
                .font(Theme.Typeface.overline(11))
                .tracking(2)
                .foregroundStyle(Theme.tertiaryText)
            Text("\(away.abbreviation) @ \(home.abbreviation)")
                .font(Theme.Typeface.display(34))
                .foregroundStyle(Theme.primaryText)
        }
        .padding(.top, 8)
    }

    private var startButton: some View {
        Button {
            start()
        } label: {
            Text("START SCORING")
                .font(Theme.Typeface.label(15, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accent)
                )
        }
        .buttonStyle(.plain)
    }

    private var importFooter: String {
        if let importedSetup {
            let lineups = importedSetup.lineups == nil
                ? "Lineups aren't posted yet — rosters are in, pick the nine below."
                : "Rosters and the posted lineup are in."
            return "Imported \(importedSetup.game.title). \(lineups)"
        }
        return "MLB only — see the importer for why. Any other league can be pasted in below."
    }

    private func apply(_ setup: RemoteGameSetup) {
        importedSetup = setup
        away = setup.teams.away
        home = setup.teams.home
        if !setup.venue.isEmpty { venue = setup.venue }
    }

    private func start() {
        var rules = GameRules.standard
        rules.usesDesignatedHitter = usesDH
        rules.regulationInnings = regulationInnings

        // An imported game keeps its provenance so the official scoring can be
        // fetched back later, and keeps the posted lineup if there was one.
        if let importedSetup, importedSetup.teams.away == away, importedSetup.teams.home == home {
            onStart(GameFactory.game(from: importedSetup, rules: rules, settings: settings))
            return
        }

        onStart(
            GameFactory.newGame(
                away: away,
                home: home,
                venue: venue,
                rules: rules,
                settings: settings
            )
        )
    }
}

// MARK: - Rows

private struct TeamFields: View {
    @Binding var roster: TeamRoster
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(Theme.Typeface.overline(10))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 46, alignment: .leading)

            TextField("Team name", text: $roster.name)
                .font(Theme.Typeface.label(15))
                .foregroundStyle(Theme.primaryText)

            TextField("ABB", text: $roster.abbreviation)
                .font(Theme.Typeface.label(15, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .textInputAutocapitalization(.characters)
                .frame(width: 58)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
        }
        .padding(.vertical, 11)
    }
}

private struct FieldRow: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.Typeface.label(15))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            TextField(placeholder, text: $text)
                .font(Theme.Typeface.label(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}

private struct StepperRow: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(label)
                    .font(Theme.Typeface.label(15))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(value)")
                    .font(Theme.Typeface.score(16))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ActionRow: View {
    var title: String
    var detail: String?
    var symbol: String
    var action: () -> Void

    init(_ title: String, detail: String? = nil, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typeface.label(15))
                        .foregroundStyle(Theme.primaryText)
                    if let detail {
                        Text(detail)
                            .font(Theme.Typeface.caption())
                            .foregroundStyle(Theme.tertiaryText)
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

private struct NavigationRowLabel: View {
    var title: String
    var value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.Typeface.label(15))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.tertiaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Editable roster. Order matters — the first nine are the batting order.
///
/// This one stays a `List`: drag-to-reorder and swipe-to-delete are worth more
/// here than a bespoke look, and the stock chrome is pushed out of the way.
struct RosterEditorView: View {
    @Binding var roster: TeamRoster

    var body: some View {
        List {
            Section {
                ForEach($roster.players) { $player in
                    PlayerRow(player: $player)
                        .listRowBackground(Theme.surface)
                }
                .onMove { source, destination in
                    roster.players.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    roster.players.remove(atOffsets: offsets)
                }
            } header: {
                Text("Batting order & bench")
            } footer: {
                Text("Drag to reorder. The first nine bat; everyone else starts on the bench.")
            }

            Button {
                roster.players.append(
                    Player(number: "", name: "", primaryPosition: .designatedHitter)
                )
            } label: {
                Label("Add player", systemImage: "plus.circle.fill")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(roster.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}

private struct PlayerRow: View {
    @Binding var player: Player

    var body: some View {
        HStack(spacing: 10) {
            TextField("#", text: $player.number)
                .frame(width: 38)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)

            TextField("Name", text: $player.name)

            Picker("", selection: $player.primaryPosition) {
                ForEach(Position.allCases) { position in
                    Text(position.abbreviation).tag(position)
                }
            }
            .labelsHidden()
            .frame(width: 80)
        }
    }
}
