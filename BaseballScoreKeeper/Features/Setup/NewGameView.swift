import SwiftUI

/// Game setup. Everything is prefilled so a scorer who arrives at first pitch
/// can hit Start and fix the names between innings.
struct NewGameView: View {
    var onStart: (GameDocument) -> Void

    @State private var away = GameFactory.placeholderRoster(name: "Away", abbreviation: "AWY")
    @State private var home = GameFactory.placeholderRoster(name: "Home", abbreviation: "HME")
    @State private var venue = ""
    @State private var usesDH = true
    @State private var regulationInnings = 9
    @State private var settings = AppPreferences.defaultTrackingSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Teams") {
                    TeamFields(roster: $away, label: "Away")
                    TeamFields(roster: $home, label: "Home")
                }

                Section("Lineups") {
                    NavigationLink {
                        RosterEditorView(roster: $away)
                    } label: {
                        LabeledContent(away.name, value: "\(away.players.count) players")
                    }
                    NavigationLink {
                        RosterEditorView(roster: $home)
                    } label: {
                        LabeledContent(home.name, value: "\(home.players.count) players")
                    }
                }

                Section("Rules") {
                    TextField("Venue", text: $venue)
                    Toggle("Designated hitter", isOn: $usesDH)
                    Stepper("Innings: \(regulationInnings)", value: $regulationInnings, in: 3...12)
                }

                Section {
                    Picker("Layout", selection: $settings.preferredLayout) {
                        ForEach(ScoringLayout.allCases) { layout in
                            Text(layout.shortTitle).tag(layout)
                        }
                    }
                    Picker("Thumb", selection: $settings.handedness) {
                        ForEach(Handedness.allCases) { hand in
                            Text(hand.label).tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Scoring style")
                } footer: {
                    Text("You can change any of this mid-game from Settings.")
                }
            }
            .navigationTitle("New Game")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }
                }
            }
        }
    }

    private func start() {
        var rules = GameRules.standard
        rules.usesDesignatedHitter = usesDH
        rules.regulationInnings = regulationInnings

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

private struct TeamFields: View {
    @Binding var roster: TeamRoster
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            TextField("\(label) team", text: $roster.name)
            Divider()
            TextField("ABB", text: $roster.abbreviation)
                .textInputAutocapitalization(.characters)
                .frame(width: 62)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Editable roster. Order matters — the first nine are the batting order.
struct RosterEditorView: View {
    @Binding var roster: TeamRoster

    var body: some View {
        List {
            Section {
                ForEach($roster.players) { $player in
                    PlayerRow(player: $player)
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
        }
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
