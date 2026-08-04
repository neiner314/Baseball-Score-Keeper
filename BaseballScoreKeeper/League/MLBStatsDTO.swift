import Foundation

/// Wire types for MLB's public Stats API.
///
/// Everything is optional on purpose. This is a documented-by-community API
/// with no published schema guarantee, so a field disappearing should degrade
/// one row rather than fail the whole import.
enum MLBStatsDTO {

    // MARK: Shared

    struct NamedEntity: Decodable, Sendable {
        var id: Int?
        var name: String?
        var abbreviation: String?
        var fullName: String?
        var link: String?
    }

    struct PositionDTO: Decodable, Sendable {
        var code: String?
        var name: String?
        var type: String?
        var abbreviation: String?
    }

    struct PersonDTO: Decodable, Sendable {
        var id: Int?
        var fullName: String?
        var primaryNumber: String?
    }

    // MARK: Schedule

    struct ScheduleResponse: Decodable, Sendable {
        var dates: [ScheduleDate]?
    }

    struct ScheduleDate: Decodable, Sendable {
        var date: String?
        var games: [ScheduleGame]?
    }

    struct ScheduleGame: Decodable, Sendable {
        var gamePk: Int?
        var gameDate: String?
        var status: StatusDTO?
        var teams: ScheduleMatchup?
        var venue: NamedEntity?
    }

    struct StatusDTO: Decodable, Sendable {
        var detailedState: String?
        var abstractGameState: String?
    }

    struct ScheduleMatchup: Decodable, Sendable {
        var away: ScheduleSide?
        var home: ScheduleSide?
    }

    struct ScheduleSide: Decodable, Sendable {
        var team: NamedEntity?
        var score: Int?
    }

    // MARK: Boxscore

    struct BoxscoreResponse: Decodable, Sendable {
        var teams: BoxscoreTeams?
    }

    struct BoxscoreTeams: Decodable, Sendable {
        var away: BoxscoreTeam?
        var home: BoxscoreTeam?
    }

    struct BoxscoreTeam: Decodable, Sendable {
        var team: NamedEntity?
        /// Keyed by "ID660271" — the numeric id with a prefix.
        var players: [String: BoxscorePlayer]?
        var batters: [Int]?
        var pitchers: [Int]?
        var bench: [Int]?
        var bullpen: [Int]?
        var battingOrder: [Int]?
    }

    struct BoxscorePlayer: Decodable, Sendable {
        var person: PersonDTO?
        var jerseyNumber: String?
        var position: PositionDTO?
        /// "100" is the first slot's starter, "101" the first substitute in it.
        var battingOrder: String?
    }

    // MARK: Roster

    struct RosterResponse: Decodable, Sendable {
        var roster: [RosterEntry]?
    }

    struct RosterEntry: Decodable, Sendable {
        var person: PersonDTO?
        var jerseyNumber: String?
        var position: PositionDTO?
    }

    // MARK: Play by play

    struct PlayByPlayResponse: Decodable, Sendable {
        var allPlays: [PlayDTO]?
    }

    struct PlayDTO: Decodable, Sendable {
        var result: PlayResultDTO?
        var about: PlayAboutDTO?
        var matchup: PlayMatchupDTO?
    }

    struct PlayResultDTO: Decodable, Sendable {
        var type: String?
        var event: String?
        var eventType: String?
        var description: String?
        var rbi: Int?
        var isOut: Bool?
    }

    struct PlayAboutDTO: Decodable, Sendable {
        var atBatIndex: Int?
        var halfInning: String?
        var inning: Int?
        var isComplete: Bool?
    }

    struct PlayMatchupDTO: Decodable, Sendable {
        var batter: PersonDTO?
        var pitcher: PersonDTO?
    }
}

extension Position {
    /// Maps MLB's position coding onto scorebook numbering. The numeric codes
    /// line up already; the letter codes (utility, two-way) don't map to a
    /// single spot on the field, so those fall through to the abbreviation.
    init?(mlbCode: String?, abbreviation: String?) {
        if let mlbCode, let numeric = Int(mlbCode), let position = Position(rawValue: numeric) {
            self = position
            return
        }
        guard let abbreviation else { return nil }
        guard let match = Position.allCases.first(where: { $0.abbreviation == abbreviation.uppercased() }) else {
            return nil
        }
        self = match
    }
}
