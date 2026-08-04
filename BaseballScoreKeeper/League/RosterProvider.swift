import Foundation

/// A game as a provider describes it, before the scorer commits to it.
struct RemoteGame: Identifiable, Hashable, Sendable {
    var id: String
    var league: League
    var startTime: Date?
    var venue: String
    var away: RemoteTeam
    var home: RemoteTeam
    var statusDescription: String

    var title: String { "\(away.abbreviation) @ \(home.abbreviation)" }
}

struct RemoteTeam: Hashable, Sendable {
    var externalID: String
    var name: String
    var abbreviation: String
}

/// Everything needed to start scoring a game that came from somewhere else.
struct RemoteGameSetup: Sendable {
    var game: RemoteGame
    var teams: SideValues<TeamRoster>
    /// Nil when the lineup card hasn't been posted yet — rosters still import,
    /// and the scorer picks the nine.
    var lineups: SideValues<LineupState>?
    var venue: String
}

enum RosterProviderError: LocalizedError, Sendable {
    case leagueHasNoLiveProvider(League)
    case noGamesScheduled
    case badResponse(Int)
    case transport(String)
    case malformedData(String)

    var errorDescription: String? {
        switch self {
        case .leagueHasNoLiveProvider(let league):
            "\(league.shortName) doesn't publish a free roster API. Import a roster file instead."
        case .noGamesScheduled:
            "No games scheduled on that date."
        case .badResponse(let code):
            "The server replied \(code)."
        case .transport(let message):
            "Couldn't reach the server: \(message)"
        case .malformedData(let message):
            "Unexpected data: \(message)"
        }
    }
}

/// Where rosters come from. One conformance per league, so a league with no
/// API is a missing conformance rather than a special case threaded through
/// the app.
protocol RosterProvider: Sendable {
    var league: League { get }
    func games(on date: Date) async throws -> [RemoteGame]
    func setup(for game: RemoteGame) async throws -> RemoteGameSetup
}

/// Fetches the official scoring back so it can be diffed against the scorer's.
protocol OfficialScoringProvider: Sendable {
    func officialPlays(gameID: String) async throws -> [OfficialPlay]
}

enum LeagueDirectory {
    static func provider(for league: League) -> RosterProvider? {
        switch league {
        case .mlb: return MLBStatsProvider()
        case .npb, .kbo, .other: return nil
        }
    }

    static func officialScoringProvider(for league: League) -> OfficialScoringProvider? {
        switch league {
        case .mlb: return MLBStatsProvider()
        case .npb, .kbo, .other: return nil
        }
    }
}
