import SwiftUI

/// "My Teams" — a library of reusable rosters. Building a team is the slow part
/// of setting up a non-league game and it barely changes over a season, so a
/// team assembled once is kept here to drop straight into the next game.
struct TeamsView: View {
    var onStartGame: (GameDocument) -> Void

    @State private var teams: [SavedTeam] = []
    @State private var loaded = false
    @State private var showsImport = false
    @State private var startingFrom: SavedTeam?

    var body: some View {
        Group {
            if teams.isEmpty && loaded {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(teams) { team in
                            Button {
                                startingFrom = team
                            } label: {
                                SavedTeamRow(team: team)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                        }
                        .onDelete(perform: delete)
                    } footer: {
                        Text("Tap a team to start a game with it. Save teams from the game-setup screen, or import one with + above.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .appBackground()
        .navigationTitle("My Teams")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsImport = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showsImport) {
            RosterImportView(teamLabel: "a team") { roster in
                Task { await add(roster) }
            }
        }
        .fullScreenCover(item: $startingFrom) { team in
            NewGameView(onStart: onStartGame, initialAway: team.roster)
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            Text("No saved teams")
                .font(Theme.Typeface.label(17, weight: .heavy))
                .foregroundStyle(Theme.primaryText)
            Text("Import a roster with + above, or save one from a game you're setting up.")
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func load() async {
        teams = await TeamStore.shared.allTeams()
        loaded = true
    }

    private func add(_ roster: TeamRoster) async {
        try? await TeamStore.shared.save(SavedTeam(roster: roster))
        await load()
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { teams[$0] }
        teams.remove(atOffsets: offsets)
        Task {
            for team in doomed {
                try? await TeamStore.shared.delete(id: team.id)
            }
        }
    }
}

/// A modal list for pulling a saved team into a side of a new game.
struct SavedTeamPickerView: View {
    var onPick: (TeamRoster) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var teams: [SavedTeam] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if teams.isEmpty && loaded {
                    Text("No saved teams yet. Save one from here or import in My Teams.")
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(teams) { team in
                            Button {
                                onPick(team.roster)
                                dismiss()
                            } label: {
                                SavedTeamRow(team: team)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .appBackground()
            .navigationTitle("Choose a team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            teams = await TeamStore.shared.allTeams()
            loaded = true
        }
    }
}

private struct SavedTeamRow: View {
    var team: SavedTeam

    var body: some View {
        HStack(spacing: 12) {
            Text(team.roster.abbreviation)
                .font(Theme.Typeface.label(14, weight: .heavy))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 52, height: 40)
                .luminousFill(Theme.accent, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.roster.name)
                    .font(Theme.Typeface.label(16, weight: .heavy))
                    .foregroundStyle(Theme.primaryText)
                Text("\(team.roster.players.count) players")
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
