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
    @State private var showsGameImport = false
    @State private var importingSide: Side?
    @State private var importedSetup: RemoteGameSetup?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showsGameImport = true
                    } label: {
                        Label("Import a game", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    Text(importFooter)
                }

                Section("Teams") {
                    TeamFields(roster: $away, label: "Away")
                    TeamFields(roster: $home, label: "Home")
                }

                Section {
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
                    Button {
                        importingSide = .away
                    } label: {
                        Label("Paste \(away.name) roster", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        importingSide = .home
                    } label: {
                        Label("Paste \(home.name) roster", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Lineups")
                } footer: {
                    Text("Pasting works for any league — one line per player as number, name, position.")
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
            .sheet(isPresented: $showsGameImport) {
                GameImportView { setup in
                    apply(setup)
                }
            }
            .sheet(item: $importingSide) { side in
                RosterImportView(teamLabel: side == .away ? "away roster" : "home roster") { roster in
                    switch side {
                    case .away: away = roster
                    case .home: home = roster
                    }
                }
            }
        }
    }

    private var importFooter: String {
        if let importedSetup {
            let lineups = importedSetup.lineups == nil
                ? "Lineups aren't posted yet — rosters are in, pick the nine below."
                : "Rosters and the posted lineup are in."
            return "Imported \(importedSetup.game.title). \(lineups)"
        }
        return "Pull rosters and the posted lineup from the league feed. MLB only — see the importer for why."
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
