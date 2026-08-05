import Foundation

/// Which of the two layouts is showing.
///
/// There used to be three, but two of them were the same one-handed screen with
/// a different readout on top, which is a setting rather than a layout. There
/// is now one thumb-driven screen and one two-handed screen, and they are
/// genuinely different shapes.
enum ScoringLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Thumb cluster in the bottom corner, scored without looking.
    case oneHanded
    /// Everything reachable at once on a single fixed screen. Two hands, no
    /// scrolling.
    case fullSheet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHanded: "One thumb, no looking"
        case .fullSheet: "Everything at once, two hands"
        }
    }

    var shortTitle: String {
        switch self {
        case .oneHanded: "One-handed"
        case .fullSheet: "Full sheet"
        }
    }

    var symbolName: String {
        switch self {
        case .oneHanded: "hand.point.up.left.fill"
        case .fullSheet: "square.grid.2x2"
        }
    }

    var usesFlickDock: Bool { self == .oneHanded }

    /// Migrates the three-layout era. A raw value that no longer exists would
    /// otherwise throw and take the whole saved game down with it, so the two
    /// retired cases are mapped onto the screen that replaced them.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case ScoringLayout.fullSheet.rawValue, "singleSheet":
            self = .fullSheet
        default:
            // "oneHanded", and the retired "pitchFirst" / "thumbCluster".
            self = .oneHanded
        }
    }
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

/// Light, dark, or whatever the phone is doing.
///
/// Dark is the default rather than `.system`, because the app is used in dim
/// places — a stadium bowl at night, a dark room in front of a TV — and a white
/// sheet in either is a flashlight in the face.
enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
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
    /// Ball-strike challenges. Off for leagues that don't review calls.
    var trackChallenges: Bool = true
    var notationDetail: NotationDetail = .standard
    var preferredLayout: ScoringLayout = .oneHanded
    var handedness: Handedness = .right
    var appearance: AppAppearance = .dark
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

    init() {}

    /// Decoded leniently so a game saved by an older build still opens after
    /// new options are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrackingSettings()

        func flag(_ key: CodingKeys, _ fallback: Bool) throws -> Bool {
            try container.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }

        trackPitchVelocity = try flag(.trackPitchVelocity, defaults.trackPitchVelocity)
        trackPitchLocation = try flag(.trackPitchLocation, defaults.trackPitchLocation)
        trackBallLocation = try flag(.trackBallLocation, defaults.trackBallLocation)
        trackPitchType = try flag(.trackPitchType, defaults.trackPitchType)
        trackFoulAndPitchCounts = try flag(.trackFoulAndPitchCounts, defaults.trackFoulAndPitchCounts)
        trackChallenges = try flag(.trackChallenges, defaults.trackChallenges)
        hapticsEnabled = try flag(.hapticsEnabled, defaults.hapticsEnabled)
        spokenConfirmations = try flag(.spokenConfirmations, defaults.spokenConfirmations)
        assumeOutOnDialRelease = try flag(.assumeOutOnDialRelease, defaults.assumeOutOnDialRelease)

        notationDetail = try container.decodeIfPresent(NotationDetail.self, forKey: .notationDetail)
            ?? defaults.notationDetail
        preferredLayout = try container.decodeIfPresent(ScoringLayout.self, forKey: .preferredLayout)
            ?? defaults.preferredLayout
        handedness = try container.decodeIfPresent(Handedness.self, forKey: .handedness)
            ?? defaults.handedness
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance)
            ?? defaults.appearance
    }
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
    /// Set when the game was imported. Optional so older saves still decode
    /// and so a hand-entered game simply has no provenance.
    var league: League?
    /// The game's id in the league's feed, used to fetch official scoring back.
    var externalGameID: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        venue: String = "",
        teams: SideValues<TeamRoster>,
        rules: GameRules = .standard,
        settings: TrackingSettings = .default,
        startingLineups: SideValues<LineupState>,
        events: [RecordedEvent] = [],
        league: League? = nil,
        externalGameID: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.venue = venue
        self.teams = teams
        self.rules = rules
        self.settings = settings
        self.startingLineups = startingLineups
        self.events = events
        self.league = league
        self.externalGameID = externalGameID
    }

    /// Whether this game can be checked against the league's official scoring.
    var supportsAccuracyCheck: Bool {
        guard let league, let externalGameID, !externalGameID.isEmpty else { return false }
        return league.hasOfficialScoring
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
