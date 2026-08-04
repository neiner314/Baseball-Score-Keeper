import Foundation

/// Which of the three layouts from the design set is showing.
enum ScoringLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Pitch-first, flips to the field view when a ball is put in play.
    case pitchFirst
    /// Everything on one scrolling sheet.
    case singleSheet
    /// One-handed thumb cluster with a big scoreboard count.
    case thumbCluster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pitchFirst: "Pitch-first, flips to field view"
        case .singleSheet: "Everything on one scrolling sheet"
        case .thumbCluster: "One-handed thumb cluster"
        }
    }

    var shortTitle: String {
        switch self {
        case .pitchFirst: "Pitch-first"
        case .singleSheet: "Full sheet"
        case .thumbCluster: "One-handed"
        }
    }

    var symbolName: String {
        switch self {
        case .pitchFirst: "figure.baseball"
        case .singleSheet: "list.bullet.rectangle"
        case .thumbCluster: "hand.point.up.left.fill"
        }
    }

    /// The two thumb-driven layouts share the flick dock.
    var usesFlickDock: Bool { self != .singleSheet }
}

enum NotationDetail: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 1B, F5, 6-3, K
    case standard
    /// Adds trajectory and location: G6-3, F8 (deep), L7
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard notation"
        case .full: "Full detail"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: "1B, F5, 6-3, K"
        case .full: "+ trajectory: grounder, liner, fly, pop"
        }
    }
}

/// The "what do you want to track" screen. Every toggle here removes UI from
/// the live scoring screen rather than just hiding data — the point is that
/// the fewer things you track, the less there is to hit.
struct TrackingSettings: Codable, Hashable, Sendable {
    var trackPitchVelocity: Bool = true
    var trackPitchLocation: Bool = false
    var trackBallLocation: Bool = true
    var trackPitchType: Bool = true
    var trackFoulAndPitchCounts: Bool = true
    var notationDetail: NotationDetail = .standard
    var preferredLayout: ScoringLayout = .pitchFirst
    var handedness: Handedness = .right
    var hapticsEnabled: Bool = true
    var spokenConfirmations: Bool = false
    /// Skip the result ring and score every ball in play as an out at the
    /// selected fielder. Fastest possible no-look mode.
    var assumeOutOnDialRelease: Bool = false

    static let `default` = TrackingSettings()

    /// The one-handed dock only shows what is being tracked, so a scorer who
    /// turned everything off gets nothing but the pitch pad.
    var showsVelocityRow: Bool { trackPitchVelocity }
    var showsPitchTypeRow: Bool { trackPitchType }
}

/// A whole game as it lives on disk: the roster, the settings in force, and
/// the append-only event log everything else is derived from.
struct GameDocument: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var venue: String
    var teams: SideValues<TeamRoster>
    var rules: GameRules
    var settings: TrackingSettings
    var startingLineups: SideValues<LineupState>
    var events: [RecordedEvent]

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        venue: String = "",
        teams: SideValues<TeamRoster>,
        rules: GameRules = .standard,
        settings: TrackingSettings = .default,
        startingLineups: SideValues<LineupState>,
        events: [RecordedEvent] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.venue = venue
        self.teams = teams
        self.rules = rules
        self.settings = settings
        self.startingLineups = startingLineups
        self.events = events
    }

    var title: String {
        "\(teams.away.abbreviation) @ \(teams.home.abbreviation)"
    }

    func player(id: UUID) -> Player? {
        teams.away.player(id: id) ?? teams.home.player(id: id)
    }

    func side(ofPlayer id: UUID) -> Side? {
        if teams.away.player(id: id) != nil { return .away }
        if teams.home.player(id: id) != nil { return .home }
        return nil
    }
}
