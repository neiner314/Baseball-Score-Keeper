import Foundation

/// Schedules and rosters for Nippon Professional Baseball, read from the
/// community **Nippon Baseball Data Repository**, which mirrors SPAIA's data as
/// season CSVs attached to GitHub releases.
///
/// This is not an official NPB feed — there isn't one — so it's best effort and
/// for personal, non-commercial scoring. The data carries no posted lineups, so
/// an imported game brings both rosters and leaves the starting nine to the
/// scorer; and it carries no pitch arsenals or official play-by-play, so NPB
/// conforms to `RosterProvider` only.
///
/// Per the repository's request, the attribution in `League.npb.sourceNote` is
/// shown to the user on the import screen.
struct NPBDataProvider: RosterProvider {
    var league: League { .npb }

    private let client: HTTPClient
    private let base = "https://github.com/armstjc/Nippon-Baseball-Data-Repository/releases/download"

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    // MARK: - Schedule

    func games(on date: Date) async throws -> [RemoteGame] {
        let season = Self.season(for: date)
        let table = try await table(tag: "schedule", file: "\(season)_npb_schedule.csv")
        let target = Self.dayStamp(date)

        var games: [RemoteGame] = []
        for row in table.rows {
            guard
                let gameDate = table.value(row, "game_date"), gameDate.hasPrefix(target),
                let gameID = table.value(row, "game_id"),
                let awayID = table.value(row, "away_team_id"),
                let homeID = table.value(row, "home_team_id")
            else { continue }

            games.append(
                RemoteGame(
                    id: gameID,
                    league: .npb,
                    startTime: Self.parseTimestamp(gameDate),
                    venue: table.value(row, "stadium_name_jpn") ?? "",
                    away: team(
                        id: awayID,
                        name: table.value(row, "away_team_name_en"),
                        short: table.value(row, "away_team_name_en_short")
                    ),
                    home: team(
                        id: homeID,
                        name: table.value(row, "home_team_name_en"),
                        short: table.value(row, "home_team_name_en_short")
                    ),
                    statusDescription: ""
                )
            )
        }

        guard !games.isEmpty else { throw RosterProviderError.noGamesScheduled }
        return games
    }

    private func team(id: String, name: String?, short: String?) -> RemoteTeam {
        let display = (name?.isEmpty == false) ? name! : "NPB \(id)"
        let abbreviation = (short?.isEmpty == false) ? short! : String(display.prefix(3)).uppercased()
        return RemoteTeam(externalID: id, name: display, abbreviation: abbreviation)
    }

    // MARK: - Rosters

    func setup(for game: RemoteGame) async throws -> RemoteGameSetup {
        let season = game.startTime.map(Self.season(for:)) ?? Self.season(for: Date())
        let table = try await table(tag: "rosters", file: "\(season)_npb_rosters.csv")

        return RemoteGameSetup(
            game: game,
            teams: SideValues(
                away: buildTeam(from: table, summary: game.away),
                home: buildTeam(from: table, summary: game.home)
            ),
            // No lineup card in the data — the scorer picks the nine.
            lineups: nil,
            venue: game.venue
        )
    }

    private func buildTeam(from table: CSVTable, summary: RemoteTeam) -> TeamRoster {
        var players: [Player] = []
        var seen: Set<String> = []

        for row in table.rows {
            guard table.value(row, "team_id") == summary.externalID else { continue }
            // Only rows that name a playing position; managers, coaches and
            // other staff have no position and are skipped.
            guard let position = Self.position(rosterName: table.value(row, "roster_name")) else { continue }
            guard let personID = table.value(row, "person_id"), seen.insert(personID).inserted else { continue }

            // Prefer the kanji name. The feed's romaji column is auto-generated
            // and riddled with "?" where it couldn't read a rare character
            // (竹下 徠空 comes through as "Takeshita ??"), whereas the kanji is
            // always complete and is what a Japanese scorer reads anyway.
            let kanji = table.value(row, "player_name") ?? ""
            let romaji = table.value(row, "player_name_romaji") ?? ""
            players.append(
                Player(
                    number: table.value(row, "player_jersey_number") ?? "",
                    name: kanji.isEmpty ? romaji : kanji,
                    primaryPosition: position,
                    externalID: personID
                )
            )
        }

        players.sort { $0.name < $1.name }

        return TeamRoster(
            name: summary.name,
            abbreviation: summary.abbreviation,
            players: players,
            externalID: summary.externalID
        )
    }

    /// The feed's four position buckets are coarser than the scorebook's nine.
    /// Pitcher and catcher map exactly; an infielder and an outfielder land on a
    /// sensible default the scorer reassigns when they set the lineup.
    static func position(rosterName: String?) -> Position? {
        switch rosterName {
        case "投手": return .pitcher
        case "捕手": return .catcher
        case "内野手": return .shortstop
        case "外野手": return .centerField
        default: return nil
        }
    }

    // MARK: - Season hitting

    /// Aggregates every player's season hitting line from the per-game files.
    ///
    /// The feed splits a season into one file per month (`2025-04_game_stats`),
    /// so a whole season is a handful of downloads summed together. It's keyed
    /// by the player's feed id and returned in one table, because the caller
    /// wants the same season for both teams and it's wasteful to fetch twice.
    func seasonHitting(season: Int) async -> [String: SeasonHittingStats] {
        // Totals per player, summed across the season's months.
        struct Totals {
            var ab = 0, h = 0, hr = 0, rbi = 0, bb = 0, hbp = 0, sf = 0
        }
        var totals: [String: Totals] = [:]

        // NPB runs roughly February through November; missing months just 404
        // and are skipped.
        for month in 2...11 {
            let file = String(format: "%d-%02d_game_stats.csv", season, month)
            guard let table = try? await table(tag: "player_game_stats", file: file) else { continue }

            for row in table.rows {
                guard let id = table.value(row, "player_id") else { continue }
                func int(_ column: String) -> Int { Int(table.value(row, column) ?? "") ?? 0 }

                var running = totals[id] ?? Totals()
                running.ab += int("batting_AB")
                running.h += int("batting_H")
                running.hr += int("batting_HR")
                running.rbi += int("batting_RBI")
                running.bb += int("batting_BB")
                running.hbp += int("batting_HBP")
                running.sf += int("batting_SF")
                totals[id] = running
            }
        }

        var stats: [String: SeasonHittingStats] = [:]
        for (id, t) in totals {
            if let line = SeasonHittingStats(
                atBats: t.ab, hits: t.h, homeRuns: t.hr, rbis: t.rbi,
                walks: t.bb, hitByPitch: t.hbp, sacFlies: t.sf
            ) {
                stats[id] = line
            }
        }
        return stats
    }

    // MARK: - Fetch & parse

    private func table(tag: String, file: String) async throws -> CSVTable {
        guard let url = URL(string: "\(base)/\(tag)/\(file)") else {
            throw RosterProviderError.malformedData("bad NPB data URL")
        }
        let text = try await client.getText(url)
        guard let parsed = CSVTable(text) else {
            throw RosterProviderError.malformedData("empty \(file)")
        }
        return parsed
    }

    static func season(for date: Date) -> Int {
        Calendar(identifier: .gregorian).component(.year, from: date)
    }

    /// The schedule stamps each game with its Japan-time date. Matching on the
    /// calendar day the scorer picked is close enough for choosing a slate.
    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return formatter.date(from: value)
    }
}

/// A tiny header-keyed CSV reader. These feeds are plain comma-delimited files
/// with no quoted fields, so a naïve split is enough; every lookup is by column
/// name so a reordered or extended header still reads.
private struct CSVTable {
    let rows: [[String]]
    private let columns: [String: Int]

    init?(_ text: String) {
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        var lines = cleaned
            .split(whereSeparator: \.isNewline)
            .map { line in
                line
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }

        guard !lines.isEmpty else { return nil }

        let header = lines.removeFirst()
        var map: [String: Int] = [:]
        for (index, name) in header.enumerated() { map[name] = index }

        columns = map
        rows = lines
    }

    /// The value for a named column, or nil when the column is absent, the row
    /// is short, or the cell is empty.
    func value(_ row: [String], _ column: String) -> String? {
        guard let index = columns[column], index < row.count else { return nil }
        let value = row[index]
        return value.isEmpty ? nil : value
    }
}
