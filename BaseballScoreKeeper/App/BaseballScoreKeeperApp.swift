import SwiftUI

@main
struct BaseballScoreKeeperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
    }
}

/// Opens on the main menu, and swaps to the scoring screen once a game is
/// chosen or built. A game in progress survives the app being killed between
/// innings — it's saved to the archive and offered back as "Resume" on the menu
/// rather than forced open on launch.
struct RootView: View {
    @State private var store: GameStore?
    @State private var appearance: AppAppearance = AppPreferences.defaultTrackingSettings.appearance

    var body: some View {
        Group {
            if let store {
                ScoringContainerView(onExitGame: { self.store = nil })
                    .environment(store)
                    .onChange(of: store.settings.appearance) { _, newValue in
                        appearance = newValue
                    }
                    .onAppear { appearance = store.settings.appearance }
            } else {
                MainMenuView(
                    onStartGame: { document in store = GameStore(document: document) },
                    appearance: $appearance
                )
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview("One-handed") {
    ScoringContainerView()
        .environment(GameStore(document: GameFactory.sampleGame()))
        .preferredColorScheme(.dark)
}
