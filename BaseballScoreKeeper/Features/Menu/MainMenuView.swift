import SwiftUI

/// The home screen. The app used to drop you straight onto the game-setup form;
/// now it opens here, on a set of tiles that carry the same lit-glass look as
/// the scoring screens, so the whole app reads as one piece.
struct MainMenuView: View {
    /// Hands a chosen or freshly built game up to the root, which swaps the menu
    /// out for the scoring screen.
    var onStartGame: (GameDocument) -> Void
    /// App-wide colour scheme, shared with the root so a change in Settings
    /// takes effect everywhere at once.
    @Binding var appearance: AppAppearance

    @State private var resumable: GameDocument?
    @State private var newGameMode: NewGameMode?
    @State private var route: [Route] = []

    private enum NewGameMode: Identifiable {
        case custom, importGame
        var id: Int { hashValue }
    }

    private enum Route: Hashable {
        case scorebook, teams, settings
    }

    var body: some View {
        NavigationStack(path: $route) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let resumable {
                        resumeCard(resumable)
                    }

                    tileGrid
                }
                .padding(.horizontal, Theme.Metrics.screenMargin)
                .padding(.vertical, 20)
            }
            .appBackground()
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .scorebook:
                    SavedGamesView(onOpenGame: onStartGame)
                case .teams:
                    TeamsView(onStartGame: onStartGame)
                case .settings:
                    GlobalSettingsView(appearance: $appearance)
                }
            }
        }
        .fullScreenCover(item: $newGameMode) { mode in
            NewGameView(onStart: onStartGame, startWithImport: mode == .importGame)
        }
        .task { await loadResumable() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BASEBALL")
                .font(Theme.Typeface.overline(12))
                .tracking(4)
                .foregroundStyle(Theme.tertiaryText)
            Text("Scorekeeper")
                .font(Theme.Typeface.display(38))
                .foregroundStyle(Theme.primaryText)
        }
        .padding(.top, 8)
    }

    // MARK: - Resume

    /// The most recent unfinished game, pulled to the top so picking up where
    /// you left off is one tap and not a hunt through the archive.
    private func resumeCard(_ document: GameDocument) -> some View {
        Button {
            onStartGame(document)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .luminousCircle(Theme.accent, isProminent: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RESUME")
                        .font(Theme.Typeface.overline(9))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text(document.title)
                        .font(Theme.Typeface.label(18, weight: .heavy))
                        .foregroundStyle(Theme.primaryText)
                    Text(document.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scorecardSurface()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tiles

    private var tileGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            MenuTile(symbol: "baseball.fill", title: "Custom Game", subtitle: "Set up your own", tint: Theme.inPlay) {
                newGameMode = .custom
            }
            MenuTile(symbol: "arrow.down.circle.fill", title: "Import Game", subtitle: "MLB & NPB feeds", tint: Theme.ball) {
                newGameMode = .importGame
            }
            MenuTile(symbol: "book.closed.fill", title: "My Scorebook", subtitle: "Games you've scored", tint: Theme.foul) {
                route.append(.scorebook)
            }
            MenuTile(symbol: "person.3.fill", title: "My Teams", subtitle: "Saved rosters", tint: Theme.hitByPitch) {
                route.append(.teams)
            }
            MenuTile(symbol: "slider.horizontal.3", title: "Settings", subtitle: "Defaults & look", tint: Theme.neutral) {
                route.append(.settings)
            }
        }
    }

    // MARK: - Loading

    private func loadResumable() async {
        guard let id = AppPreferences.lastGameID else { return }
        guard let document = try? await GameArchive.shared.load(id: id) else { return }
        // A game only counts as resumable if it's actually under way and hasn't
        // already ended.
        guard !document.events.isEmpty else { return }
        resumable = ScoringEngine.replay(document: document).isFinal ? nil : document
    }
}

/// One square on the menu: a lit icon over a title and a one-line hint.
struct MenuTile: View {
    var symbol: String
    var title: String
    var subtitle: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .luminousCircle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typeface.label(17, weight: .heavy))
                        .foregroundStyle(Theme.primaryText)
                    Text(subtitle)
                        .font(Theme.Typeface.caption())
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(Theme.Metrics.cardPadding)
            .scorecardSurface()
        }
        .buttonStyle(.plain)
    }
}
