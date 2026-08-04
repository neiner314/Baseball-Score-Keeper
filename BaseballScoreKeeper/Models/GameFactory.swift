import Foundation

/// Builds new games and the placeholder rosters that let a scorer start
/// keeping score before they've typed a single name in.
enum GameFactory {

    /// Batting order for a lineup using a designated hitter — the pitcher
    /// doesn't bat.
    static let designatedHitterOrder: [Position] = [
        .centerField, .shortstop, .rightField, .designatedHitter,
        .firstBase, .thirdBase, .leftField, .secondBase, .catcher
    ]

    /// Batting order when the pitcher hits, ninth as tradition demands.
    static let pitcherHittingOrder: [Position] = [
        .centerField, .shortstop, .rightField, .firstBase,
        .thirdBase, .leftField, .secondBase, .catcher, .pitcher
    ]

    static func placeholderRoster(name: String, abbreviation: String, usesDH: Bool = true) -> TeamRoster {
        let order = usesDH ? designatedHitterOrder : pitcherHittingOrder

        var players: [Player] = order.enumerated().map { index, position in
            Player(
                number: "\(index + 1)",
                name: "\(abbreviation) \(position.abbreviation)",
                primaryPosition: position
            )
        }

        if usesDH {
            players.append(
                Player(number: "40", name: "\(abbreviation) P", primaryPosition: .pitcher)
            )
        }

        // A short bench so substitutions work out of the box.
        for index in 1...4 {
            players.append(
                Player(
                    number: "\(50 + index)",
                    name: "\(abbreviation) Bench \(index)",
                    primaryPosition: .designatedHitter
                )
            )
        }
        for index in 1...3 {
            players.append(
                Player(
                    number: "\(60 + index)",
                    name: "\(abbreviation) Reliever \(index)",
                    primaryPosition: .pitcher
                )
            )
        }

        return TeamRoster(name: name, abbreviation: abbreviation, players: players)
    }

    /// Turns a roster into a starting lineup: the first nine non-pitchers (or
    /// nine including the pitcher) bat, and everyone else starts on the bench.
    static func makeLineup(roster: TeamRoster, usesDH: Bool) -> LineupState {
        let order = usesDH ? designatedHitterOrder : pitcherHittingOrder

        var used: Set<UUID> = []
        var slots: [LineupState.Slot] = []

        for position in order {
            let candidate = roster.players.first {
                $0.primaryPosition == position && !used.contains($0.id)
            } ?? roster.players.first { !used.contains($0.id) && $0.primaryPosition != .pitcher }

            guard let candidate else { continue }
            used.insert(candidate.id)
            slots.append(LineupState.Slot(playerID: candidate.id, position: position))
        }

        var assignments: [LineupState.FieldAssignment] = []
        for slot in slots where slot.position.isFielder {
            assignments.append(
                LineupState.FieldAssignment(position: slot.position, playerID: slot.playerID)
            )
        }

        // With a DH the pitcher is not in the order and has to be named here.
        if usesDH {
            let pitcher = roster.players.first {
                $0.primaryPosition == .pitcher && !used.contains($0.id)
            }
            if let pitcher {
                used.insert(pitcher.id)
                assignments.append(
                    LineupState.FieldAssignment(position: .pitcher, playerID: pitcher.id)
                )
            }
        }

        let bench = roster.players.filter { !used.contains($0.id) }.map(\.id)

        return LineupState(
            slots: slots,
            fieldAssignments: assignments,
            benchPlayerIDs: bench
        )
    }

    static func newGame(
        away: TeamRoster,
        home: TeamRoster,
        venue: String = "",
        rules: GameRules = .standard,
        settings: TrackingSettings = .default,
        league: League? = nil,
        externalGameID: String? = nil,
        lineups: SideValues<LineupState>? = nil
    ) -> GameDocument {
        GameDocument(
            venue: venue,
            teams: SideValues(away: away, home: home),
            rules: rules,
            settings: settings,
            startingLineups: lineups ?? SideValues(
                away: makeLineup(roster: away, usesDH: rules.usesDesignatedHitter),
                home: makeLineup(roster: home, usesDH: rules.usesDesignatedHitter)
            ),
            league: league,
            externalGameID: externalGameID
        )
    }

    /// Builds a scoreable game straight out of an imported setup. When the
    /// lineup card hasn't been posted yet, the roster is still imported and a
    /// provisional nine is picked, which the scorer can fix before first pitch.
    static func game(
        from setup: RemoteGameSetup,
        rules: GameRules = .standard,
        settings: TrackingSettings = .default
    ) -> GameDocument {
        GameFactory.newGame(
            away: setup.teams.away,
            home: setup.teams.home,
            venue: setup.venue,
            rules: rules,
            settings: settings,
            league: setup.game.league,
            externalGameID: setup.game.id,
            lineups: setup.lineups
        )
    }

    /// A ready-to-score game, used for previews and for "just start scoring".
    static func sampleGame() -> GameDocument {
        newGame(
            away: placeholderRoster(name: "Away", abbreviation: "AWY"),
            home: placeholderRoster(name: "Home", abbreviation: "HME"),
            venue: ""
        )
    }
}
