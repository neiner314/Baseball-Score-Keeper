import SwiftUI

/// "My Scorebook" — every game the archive is holding, newest first. Tap one to
/// open it back up (finished games land on their box score; games in progress
/// pick up where they left off), or swipe to throw it away.
struct SavedGamesView: View {
    var onOpenGame: (GameDocument) -> Void

    @State private var games: [GameDocument] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if games.isEmpty && loaded {
                emptyState
            } else {
                List {
                    ForEach(games) { game in
                        Button {
                            onOpenGame(game)
                        } label: {
                            SavedGameRow(document: game)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                    .onDelete(perform: delete)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .appBackground()
        .navigationTitle("My Scorebook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !games.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            Text("Nothing scored yet")
                .font(Theme.Typeface.label(17, weight: .heavy))
                .foregroundStyle(Theme.primaryText)
            Text("Games you score are saved here automatically.")
                .font(Theme.Typeface.caption())
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func load() async {
        games = await GameArchive.shared.allGames()
        loaded = true
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { games[$0] }
        games.remove(atOffsets: offsets)
        Task {
            for game in doomed {
                try? await GameArchive.shared.delete(id: game.id)
            }
        }
    }
}

/// One archived game: the matchup and score on top, when and where beneath, and
/// a tag saying whether it's final or still going.
private struct SavedGameRow: View {
    var document: GameDocument

    private var state: GameState { ScoringEngine.replay(document: document) }

    var body: some View {
        let state = self.state
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    scoreLine(document.teams.away.abbreviation, state.runs(for: .away))
                    Text("·").foregroundStyle(Theme.tertiaryText)
                    scoreLine(document.teams.home.abbreviation, state.runs(for: .home))
                }
                Text(subtitle)
                    .font(Theme.Typeface.caption())
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            statusTag(state)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func scoreLine(_ abbreviation: String, _ runs: Int) -> some View {
        HStack(spacing: 5) {
            Text(abbreviation)
                .font(Theme.Typeface.label(15, weight: .heavy))
                .foregroundStyle(Theme.primaryText)
            Text("\(runs)")
                .font(Theme.Typeface.score(15))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private func statusTag(_ state: GameState) -> some View {
        let final = state.isFinal
        Text(final ? "FINAL" : "IN PROGRESS")
            .font(Theme.Typeface.overline(8))
            .tracking(0.8)
            .foregroundStyle(final ? Theme.secondaryText : Theme.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(final ? Theme.surfaceHigh : Theme.accent)
            )
    }

    private var subtitle: String {
        var parts = [document.startedAt.formatted(date: .abbreviated, time: .shortened)]
        if !document.venue.isEmpty { parts.append(document.venue) }
        if let league = document.league { parts.append(league.shortName) }
        return parts.joined(separator: " · ")
    }
}
