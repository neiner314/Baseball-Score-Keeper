import Foundation

/// Wire types for MLB's public Stats API.
///
/// Everything is optional on purpose. This is a documented-by-community API
/// with no published schema guarantee, so a field disappearing should degrade
/// one row rather than fail the whole import.
enum MLBStatsDTO {

    // MARK: Shared

    /// A value the feed sometimes sends as a string and sometimes as a number.
    ///
    /// Jersey numbers, position codes and batting-order slots are all written
    /// as quoted strings in the raw JSON, but typed wrappers around this API
    /// model some of them as integers — so at least one of the two is coercing,
    /// and it isn't clear which. `decodeIfPresent` throws on a type mismatch
    /// rather than returning nil, so guessing wrong wouldn't drop a field, it
    /// would fail the entire boxscore. Accepting both costs nothing.
    struct LooseString: Decodable, Hashable, Sendable {
        var value: String

        init(_ value: String) {
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let string = try? container.decode(String.self) {
                value = string
            } else if let int = try? container.decode(Int.self) {
                value = String(int)
            } else if let double = try? container.decode(Double.self) {
                value = String(Int(double))
            } else {
                value = ""
            }
        }
    }

    struct NamedEntity: Decodable, Sendable {
        var id: Int?
        var name: String?
        var abbreviation: String?
        var fullName: String?
        var link: String?
    }

    struct PositionDTO: Decodable, Sendable {
        var code: LooseString?
        var name: String?
        var type: String?
        var abbreviation: String?
    }

    struct PersonDTO: Decodable, Sendable {
        var id: Int?
        var fullName: String?
        var primaryNumber: LooseString?
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
        var jerseyNumber: LooseString?
        var position: PositionDTO?
        /// "100" is the first slot's starter, "101" the first substitute in it.
        var battingOrder: LooseString?
    }

    // MARK: Roster

    struct RosterResponse: Decodable, Sendable {
        var roster: [RosterEntry]?
    }

    struct RosterEntry: Decodable, Sendable {
        var person: PersonDTO?
        var jerseyNumber: LooseString?
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

    // MARK: Pitch arsenal

    /// `people(...)` hydrated with the `pitchArsenal` pitching stat. Each split
    /// is one pitch the pitcher throws, with how often and how hard.
    struct PeopleResponse: Decodable, Sendable {
        var people: [PersonStatsDTO]?
    }

    struct PersonStatsDTO: Decodable, Sendable {
        var id: Int?
        var stats: [StatGroupDTO]?
    }

    struct StatGroupDTO: Decodable, Sendable {
        var splits: [StatSplitDTO]?
    }

    struct StatSplitDTO: Decodable, Sendable {
        var stat: ArsenalStatDTO?
    }

    struct ArsenalStatDTO: Decodable, Sendable {
        var type: PitchTypeCodeDTO?
        var averageSpeed: Double?
        var count: Int?
    }

    struct PitchTypeCodeDTO: Decodable, Sendable {
        var code: String?
        var description: String?
    }

    // MARK: Season hitting

    /// `people(...)` hydrated with the `season` hitting stat. The rate stats
    /// come as strings (".287"), the counting stats as numbers, so both go
    /// through `LooseString`.
    struct HittingResponse: Decodable, Sendable {
        var people: [HittingPerson]?
    }

    struct HittingPerson: Decodable, Sendable {
        var stats: [HittingGroup]?
    }

    struct HittingGroup: Decodable, Sendable {
        var splits: [HittingSplit]?
    }

    struct HittingSplit: Decodable, Sendable {
        var stat: HittingStatDTO?
    }

    struct HittingStatDTO: Decodable, Sendable {
        var avg: LooseString?
        var obp: LooseString?
        var homeRuns: LooseString?
        var rbi: LooseString?
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

extension PitchType {
    /// Maps MLB's pitch-type codes onto the eight the app tracks. The feed
    /// carries more shapes than a scorebook cares about — a sweeper and a
    /// slurve both go down as a slider — so several codes fold onto one type.
    /// An unknown code returns nil rather than guessing.
    init?(mlbArsenalCode code: String?) {
        switch code?.uppercased() {
        case "FF", "FA": self = .fastball
        case "SI", "FT": self = .sinker
        case "FC": self = .cutter
        case "SL", "ST", "SV": self = .slider
        case "CU", "KC", "CS": self = .curveball
        case "CH", "SC": self = .changeup
        case "FS", "FO": self = .splitter
        case "KN": self = .knuckleball
        default: return nil
        }
    }
}
