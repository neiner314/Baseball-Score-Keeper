import SwiftUI
import UIKit

@main
struct BaseballScoreKeeperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
    }
}

/// The app is a one-handed, portrait tool everywhere except the read-only
/// scorebook, which reads far better turned sideways. Rather than open the whole
/// app to rotation, a single global lock is flipped open only while that screen
/// is on, and snapped back to portrait as it leaves.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

extension View {
    /// Permits landscape for as long as the view is on screen, returning the app
    /// to portrait when it leaves. Used only by the scorebook viewer.
    func allowsLandscape() -> some View {
        modifier(LandscapeAllowingModifier())
    }
}

private struct LandscapeAllowingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { AppDelegate.orientationLock = .allButUpsideDown }
            .onDisappear {
                AppDelegate.orientationLock = .portrait
                let scene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
                scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
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
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.default.rawValue

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
        // Override the locale for the whole tree so a language chosen in
        // Settings takes hold at once, without waiting for a relaunch.
        .environment(\.locale, selectedLocale)
    }

    private var selectedLocale: Locale {
        (AppLanguage(rawValue: languageCode) ?? .default).locale
    }
}

#Preview("One-handed") {
    ScoringContainerView()
        .environment(GameStore(document: GameFactory.sampleGame()))
        .preferredColorScheme(.dark)
}
