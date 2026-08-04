import SwiftUI

/// Pulls a game's rosters and posted lineup off the league feed, so nobody has
/// to type twenty-six names before first pitch.
struct GameImportView: View {
    var onImport: (RemoteGameSetup) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var league: League = .mlb
    @State private var date = Date()
    @State private var games: [RemoteGame] = []
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("League", selection: $league) {
                        ForEach(League.allCases) { option in
                            Text(option.shortName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(league.sourceNote)
                }

                if league.hasLiveProvider {
                    Section("Date") {
                        DatePicker("Games on", selection: $date, displayedComponents: .date)
                        Button {
                            Task { await loadGames() }
                        } label: {
                            Label("Find games", systemImage: "magnifyingglass")
                        }
                        .disabled(isLoading)
                    }

                    if isLoading {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading…").foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(Theme.miss)
                        }
                    }

                    if !games.isEmpty {
                        Section("Games") {
                            ForEach(games) { game in
                                Button {
                                    Task { await importGame(game) }
                                } label: {
                                    GameRow(game: game)
                                }
                                .buttonStyle(.plain)
                                .disabled(isImporting)
                            }
                        }
                    }
                } else {
                    Section {
                        Text(
                            "\(league.shortName) has no free roster feed. Build each team once from the "
                                + "roster importer on the new-game screen and it's reusable all season."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Import Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing rosters…")
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.surface)
                        )
                }
            }
        }
    }

    // MARK: - Loading

    private func loadGames() async {
        guard let provider = LeagueDirectory.provider(for: league) else {
            errorMessage = RosterProviderError.leagueHasNoLiveProvider(league).localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        games = []
        defer { isLoading = false }

        do {
            games = try await provider.games(on: date)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importGame(_ game: RemoteGame) async {
        guard let provider = LeagueDirectory.provider(for: game.league) else { return }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let setup = try await provider.setup(for: game)
            onImport(setup)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GameRow: View {
    var game: RemoteGame

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(game.away.abbreviation) @ \(game.home.abbreviation)")
                    .font(Theme.Typeface.label(15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let start = game.startTime {
            parts.append(start.formatted(date: .omitted, time: .shortened))
        }
        if !game.statusDescription.isEmpty { parts.append(game.statusDescription) }
        if !game.venue.isEmpty { parts.append(game.venue) }
        return parts.joined(separator: " · ")
    }
}

/// Paste-in roster import, for the leagues with nothing to call.
struct RosterImportView: View {
    var teamLabel: String
    var onImport: (TeamRoster) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var abbreviation = ""
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Team name", text: $name)
                    TextField("Abbreviation", text: $abbreviation)
                        .textInputAutocapitalization(.characters)
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .font(.system(size: 13, design: .monospaced))
                } header: {
                    Text("Players")
                } footer: {
                    Text("One player per line: number, name, position.\n\n17, Shohei Ohtani, DH\n11, Yoshinobu Yamamoto, P")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(Theme.miss)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Import \(teamLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { runImport() }
                }
            }
        }
    }

    private func runImport() {
        do {
            let roster = try RosterFile.parse(text, teamName: name, abbreviation: abbreviation)
            onImport(roster)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
