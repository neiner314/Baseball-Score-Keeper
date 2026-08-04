import SwiftUI

@main
struct BaseballScoreKeeperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(nil)
                .tint(Theme.inPlay)
        }
    }
}

/// Picks up where the scorer left off, or offers a new game.
struct RootView: View {
    @State private var store: GameStore?
    @State private var hasCheckedForSavedGame = false

    var body: some View {
        Group {
            if let store {
                ScoringContainerView()
                    .environment(store)
            } else if hasCheckedForSavedGame {
                NewGameView { document in
                    store = GameStore(document: document)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task {
            await restoreLastGame()
        }
    }

    /// A game in progress should survive the app being killed between innings.
    @MainActor
    private func restoreLastGame() async {
        defer { hasCheckedForSavedGame = true }
        guard store == nil, let id = AppPreferences.lastGameID else { return }
        guard let document = try? await GameArchive.shared.load(id: id) else { return }
        guard !document.events.isEmpty else { return }
        store = GameStore(document: document)
    }
}

#Preview("One-handed") {
    ScoringContainerView()
        .environment(GameStore(document: GameFactory.sampleGame()))
}
