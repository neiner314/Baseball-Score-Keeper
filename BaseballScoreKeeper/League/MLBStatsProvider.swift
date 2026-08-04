import Foundation

/// Rosters, lineups and official scoring from MLB's public Stats API.
///
/// No account, no key, no header. Usage is subject to MLB's copyright notice
/// (http://gdx.mlb.com/components/copyright.txt), which permits individual,
/// non-commercial use — fine for keeping score, not for shipping commercially
/// without their written permission.
///
/// Field shapes here are drawn from community documentation and cross-checked
/// against a typed Python wrapper's models rather than a published schema,
/// which is why every DTO field is optional and every mapping degrades instead
/// of throwing. The two sources disagree about whether a few values are
/// strings or numbers — see `MLBStatsDTO.LooseString`.
struct MLBStatsProvider: RosterProvider, OfficialScoringProvider {
    var league: League { .mlb }

    private let client: HTTPClient
    private let base = "https://statsapi.mlb.com/api"

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    // MARK: - Schedule

    func games(on date: Date) async throws -> [RemoteGame] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"

        guard let url = URL(
            string: "\(base)/v1/schedule?sportId=1&hydrate=team,venue&date=\(formatter.string(from: date))"
        ) else {
            throw RosterProviderError.malformedData("bad schedule URL")
        }

        let response = try await client.get(url, as: MLBStatsDTO.ScheduleResponse.self)
        let games = (response.dates ?? []).flatMap { $0.games ?? [] }
        let mapped = games.compactMap(remoteGame(from:))

        guard !mapped.isEmpty else { throw RosterProviderError.noGamesScheduled }
        return mapped
    }

    private func remoteGame(from dto: MLBStatsDTO.ScheduleGame) -> RemoteGame? {
        guard let gamePk = dto.gamePk else { return nil }

        return RemoteGame(
            id: String(gamePk),
            league: .mlb,
            startTime: dto.gameDate.flatMap(Self.parseTimestamp),
            venue: dto.venue?.name ?? "",
            away: team(from: dto.teams?.away?.team),
            home: team(from: dto.teams?.home?.team),
            statusDescription: dto.status?.detailedState ?? ""
        )
    }

    private func team(from entity: MLBStatsDTO.NamedEntity?) -> RemoteTeam {
        let name = entity?.name ?? "Unknown"
        return RemoteTeam(
            externalID: entity?.id.map(String.init) ?? "",
            name: name,
            abbreviation: entity?.abbreviation ?? Self.abbreviate(name)
        )
    }

    /// Some schedule responses omit the abbreviation, so derive a usable one
    /// rather than showing a blank chip.
    static func abbreviate(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return words.suffix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    // MARK: - Rosters and lineups

    func setup(for game: RemoteGame) async throws -> RemoteGameSetup {
        guard let boxscoreURL = URL(string: "\(base)/v1/game/\(game.id)/boxscore") else {
            throw RosterProviderError.malformedData("bad boxscore URL")
        }

        let boxscore = try await client.get(boxscoreURL, as: MLBStatsDTO.BoxscoreResponse.self)

        // The boxscore alone is thin before first pitch, so the team roster
        // endpoints fill in anyone not yet listed for the game.
        async let awayFallback = fullRoster(teamID: game.away.externalID)
        async let homeFallback = fullRoster(teamID: game.home.externalID)

        let away = buildTeam(
            box: boxscore.teams?.away,
            fallback: await awayFallback,
            summary: game.away
        )
        let home = buildTeam(
            box: boxscore.teams?.home,
            fallback: await homeFallback,
            summary: game.home
        )

        let awayLineup = buildLineup(box: boxscore.teams?.away, roster: away)
        let homeLineup = buildLineup(box: boxscore.teams?.home, roster: home)

        let lineups: SideValues<LineupState>?
        if let awayLineup, let homeLineup {
            lineups = SideValues(away: awayLineup, home: homeLineup)
        } else {
            lineups = nil
        }

        return RemoteGameSetup(
            game: game,
            teams: SideValues(away: away, home: home),
            lineups: lineups,
            venue: game.venue
        )
    }

    /// Best effort — a missing roster just means fewer bench options.
    private func fullRoster(teamID: String) async -> [MLBStatsDTO.RosterEntry] {
        guard
            !teamID.isEmpty,
            let url = URL(string: "\(base)/v1/teams/\(teamID)/roster?rosterType=active")
        else { return [] }

        let response = try? await client.get(url, as: MLBStatsDTO.RosterResponse.self)
        return response?.roster ?? []
    }

    private func buildTeam(
        box: MLBStatsDTO.BoxscoreTeam?,
        fallback: [MLBStatsDTO.RosterEntry],
        summary: RemoteTeam
    ) -> TeamRoster {
        var players: [Player] = []
        var seen: Set<String> = []

        for entry in (box?.players ?? [:]).values {
            guard
                let id = entry.person?.id,
                let name = entry.person?.fullName
            else { continue }
            let externalID = String(id)
            guard seen.insert(externalID).inserted else { continue }

            players.append(
                Player(
                    number: entry.jerseyNumber?.value ?? entry.person?.primaryNumber?.value ?? "",
                    name: name,
                    primaryPosition: Position(
                        mlbCode: entry.position?.code?.value,
                        abbreviation: entry.position?.abbreviation
                    ) ?? .designatedHitter,
                    externalID: externalID
                )
            )
        }

        for entry in fallback {
            guard
                let id = entry.person?.id,
                let name = entry.person?.fullName
            else { continue }
            let externalID = String(id)
            guard seen.insert(externalID).inserted else { continue }

            players.append(
                Player(
                    number: entry.jerseyNumber?.value ?? entry.person?.primaryNumber?.value ?? "",
                    name: name,
                    primaryPosition: Position(
                        mlbCode: entry.position?.code?.value,
                        abbreviation: entry.position?.abbreviation
                    ) ?? .designatedHitter,
                    externalID: externalID
                )
            )
        }

        players.sort { $0.name < $1.name }

        return TeamRoster(
            name: box?.team?.name ?? summary.name,
            abbreviation: box?.team?.abbreviation ?? summary.abbreviation,
            players: players,
            externalID: box?.team?.id.map(String.init) ?? summary.externalID
        )
    }

    /// Returns nil until the lineup card is actually posted.
    private func buildLineup(box: MLBStatsDTO.BoxscoreTeam?, roster: TeamRoster) -> LineupState? {
        guard let box else { return nil }

        let order = box.battingOrder ?? []
        guard order.count >= 9 else { return nil }

        var slots: [LineupState.Slot] = []
        var used: Set<UUID> = []

        for personID in order.prefix(9) {
            guard let player = roster.player(externalID: String(personID)) else { continue }
            let entry = box.players?["ID\(personID)"]
            let position = Position(
                mlbCode: entry?.position?.code?.value,
                abbreviation: entry?.position?.abbreviation
            ) ?? player.primaryPosition

            slots.append(LineupState.Slot(playerID: player.id, position: position))
            used.insert(player.id)
        }

        guard slots.count == 9 else { return nil }

        // Field assignments come from the nine in the order, plus the starting
        // pitcher, who isn't in it when a DH is used.
        var assignments: [LineupState.FieldAssignment] = []
        for slot in slots where slot.position.isFielder {
            assignments.append(
                LineupState.FieldAssignment(position: slot.position, playerID: slot.playerID)
            )
        }

        if !assignments.contains(where: { $0.position == .pitcher }),
           let starterID = box.pitchers?.first,
           let starter = roster.player(externalID: String(starterID)) {
            assignments.append(
                LineupState.FieldAssignment(position: .pitcher, playerID: starter.id)
            )
            used.insert(starter.id)
        }

        let bench = roster.players.filter { !used.contains($0.id) }.map(\.id)

        return LineupState(
            slots: slots,
            fieldAssignments: assignments,
            benchPlayerIDs: bench
        )
    }

    // MARK: - Official scoring

    func officialPlays(gameID: String) async throws -> [OfficialPlay] {
        guard let url = URL(string: "\(base)/v1/game/\(gameID)/playByPlay") else {
            throw RosterProviderError.malformedData("bad play-by-play URL")
        }

        let response = try await client.get(url, as: MLBStatsDTO.PlayByPlayResponse.self)
        return (response.allPlays ?? []).compactMap(Self.officialPlay(from:))
    }

    static func officialPlay(from dto: MLBStatsDTO.PlayDTO) -> OfficialPlay? {
        guard
            let inning = dto.about?.inning,
            let halfRaw = dto.about?.halfInning,
            dto.about?.isComplete != false
        else { return nil }

        // A play with no event type never resolved — a runner event or a
        // half-inning that ended mid plate appearance.
        guard let eventType = dto.result?.eventType, !eventType.isEmpty else { return nil }

        return OfficialPlay(
            index: dto.about?.atBatIndex ?? 0,
            inning: inning,
            half: halfRaw.lowercased() == "bottom" ? .bottom : .top,
            batterExternalID: dto.matchup?.batter?.id.map(String.init),
            batterName: dto.matchup?.batter?.fullName ?? "",
            eventType: eventType,
            eventName: dto.result?.event ?? "",
            summary: dto.result?.description ?? "",
            rbi: dto.result?.rbi ?? 0
        )
    }
}
