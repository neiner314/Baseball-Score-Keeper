import XCTest
@testable import BaseballScoreKeeper

final class RosterFileTests: XCTestCase {

    func testParsesSimpleCSV() throws {
        let text = """
        17, Shohei Ohtani, DH
        11, Yoshinobu Yamamoto, P
        5, Freddie Freeman, 1B
        """

        let roster = try RosterFile.parse(text, teamName: "Dodgers", abbreviation: "LAD")

        XCTAssertEqual(roster.name, "Dodgers")
        XCTAssertEqual(roster.abbreviation, "LAD")
        XCTAssertEqual(roster.players.count, 3)
        XCTAssertEqual(roster.players[0].number, "17")
        XCTAssertEqual(roster.players[0].name, "Shohei Ohtani")
        XCTAssertEqual(roster.players[0].primaryPosition, .designatedHitter)
        XCTAssertEqual(roster.players[1].primaryPosition, .pitcher)
        XCTAssertEqual(roster.players[2].primaryPosition, .firstBase)
    }

    func testAcceptsTabsAsWellAsCommas() throws {
        let roster = try RosterFile.parse("7\tJose Altuve\t2B", teamName: "T", abbreviation: "T")
        XCTAssertEqual(roster.players.first?.name, "Jose Altuve")
        XCTAssertEqual(roster.players.first?.primaryPosition, .secondBase)
    }

    func testSkipsAHeaderRow() throws {
        let text = """
        number,name,position
        24, Player One, SS
        """
        let roster = try RosterFile.parse(text, teamName: "T", abbreviation: "T")
        XCTAssertEqual(roster.players.count, 1)
        XCTAssertEqual(roster.players[0].name, "Player One")
    }

    func testAcceptsScorebookPositionNumbers() throws {
        let roster = try RosterFile.parse("6, Someone, 6", teamName: "T", abbreviation: "T")
        XCTAssertEqual(roster.players.first?.primaryPosition, .shortstop)
    }

    func testMissingPositionFallsBackRatherThanFailing() throws {
        let roster = try RosterFile.parse("9, No Position Given", teamName: "T", abbreviation: "T")
        XCTAssertEqual(roster.players.count, 1)
        XCTAssertEqual(roster.players[0].primaryPosition, .designatedHitter)
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try RosterFile.parse("   \n  ", teamName: "T", abbreviation: "T"))
    }

    func testGarbageInputThrows() {
        XCTAssertThrowsError(try RosterFile.parse("wat", teamName: "T", abbreviation: "T"))
    }

    func testRoundTripsThroughCSV() throws {
        let original = GameFactory.placeholderRoster(name: "Away", abbreviation: "AWY")
        let text = RosterFile.csv(for: original)
        let parsed = try RosterFile.parse(text, teamName: "Away", abbreviation: "AWY")

        XCTAssertEqual(parsed.players.count, original.players.count)
        XCTAssertEqual(parsed.players.map(\.name), original.players.map(\.name))
        XCTAssertEqual(parsed.players.map(\.primaryPosition), original.players.map(\.primaryPosition))
    }

    func testParsesTheAppsOwnJSONRoster() throws {
        let original = GameFactory.placeholderRoster(name: "Home", abbreviation: "HME")
        let data = try JSONEncoder().encode(original)
        let json = String(decoding: data, as: UTF8.self)

        let parsed = try RosterFile.parse(json, teamName: "ignored", abbreviation: "IGN")
        XCTAssertEqual(parsed.name, "Home")
        XCTAssertEqual(parsed.players.count, original.players.count)
    }
}

final class LeagueTests: XCTestCase {

    /// The state of play as researched: MLB publishes a free feed, NPB and the
    /// KBO do not. If that changes, this test is the thing to update.
    func testOnlyMLBHasALiveProvider() {
        XCTAssertTrue(League.mlb.hasLiveProvider)
        XCTAssertFalse(League.npb.hasLiveProvider)
        XCTAssertFalse(League.kbo.hasLiveProvider)
        XCTAssertFalse(League.other.hasLiveProvider)
    }

    func testProviderDirectoryMatchesTheLeagueFlags() {
        for league in League.allCases {
            let hasProvider = LeagueDirectory.provider(for: league) != nil
            XCTAssertEqual(
                hasProvider,
                league.hasLiveProvider,
                "\(league.shortName) disagrees with its own capability flag"
            )
        }
    }

    func testEveryLeagueExplainsWhereItsDataComesFrom() {
        for league in League.allCases {
            XCTAssertFalse(league.sourceNote.isEmpty, "\(league.shortName) needs a source note")
        }
    }

    func testAccuracyCheckNeedsAnImportedGame() {
        let manual = GameFactory.sampleGame()
        XCTAssertFalse(manual.supportsAccuracyCheck, "a hand-entered game has nothing to compare against")

        var imported = manual
        imported.league = .mlb
        imported.externalGameID = "745444"
        XCTAssertTrue(imported.supportsAccuracyCheck)

        var japanese = imported
        japanese.league = .npb
        XCTAssertFalse(japanese.supportsAccuracyCheck, "NPB publishes no official scoring feed")
    }
}

final class MLBStatsDecodingTests: XCTestCase {

    /// The feed's own JSON quotes these values; typed wrappers around the same
    /// API model some of them as integers. Whichever is right, decoding has to
    /// survive both — a type mismatch throws rather than yielding nil, so
    /// guessing wrong would fail the whole boxscore rather than one field.
    func testLooseStringDecodesFromAQuotedValue() throws {
        let json = Data(#"{"jerseyNumber":"17","battingOrder":"100"}"#.utf8)
        let player = try JSONDecoder().decode(MLBStatsDTO.BoxscorePlayer.self, from: json)

        XCTAssertEqual(player.jerseyNumber?.value, "17")
        XCTAssertEqual(player.battingOrder?.value, "100")
    }

    func testLooseStringDecodesFromANumber() throws {
        let json = Data(#"{"jerseyNumber":17,"battingOrder":100}"#.utf8)
        let player = try JSONDecoder().decode(MLBStatsDTO.BoxscorePlayer.self, from: json)

        XCTAssertEqual(player.jerseyNumber?.value, "17")
        XCTAssertEqual(player.battingOrder?.value, "100")
    }

    func testPositionCodeSurvivesEitherRepresentation() throws {
        let quoted = Data(#"{"position":{"code":"6","abbreviation":"SS"}}"#.utf8)
        let numeric = Data(#"{"position":{"code":6,"abbreviation":"SS"}}"#.utf8)

        let a = try JSONDecoder().decode(MLBStatsDTO.BoxscorePlayer.self, from: quoted)
        let b = try JSONDecoder().decode(MLBStatsDTO.BoxscorePlayer.self, from: numeric)

        XCTAssertEqual(Position(mlbCode: a.position?.code?.value, abbreviation: nil), .shortstop)
        XCTAssertEqual(Position(mlbCode: b.position?.code?.value, abbreviation: nil), .shortstop)
    }

    func testMissingOptionalFieldsDecodeToNil() throws {
        let json = Data(#"{"person":{"id":1,"fullName":"Someone"}}"#.utf8)
        let player = try JSONDecoder().decode(MLBStatsDTO.BoxscorePlayer.self, from: json)

        XCTAssertNil(player.jerseyNumber)
        XCTAssertNil(player.battingOrder)
        XCTAssertEqual(player.person?.fullName, "Someone")
    }

    /// The team-level batting order is an array of person ids — that's what the
    /// lineup is actually built from.
    func testBoxscoreTeamDecodesTheBattingOrder() throws {
        let json = Data(#"""
        {"team":{"id":147,"name":"New York Yankees","abbreviation":"NYY"},
         "battingOrder":[665862,592450],
         "pitchers":[543037],
         "players":{"ID665862":{"person":{"id":665862,"fullName":"Jazz Chisholm Jr."},
                                "jerseyNumber":"13",
                                "position":{"code":"4","abbreviation":"2B"}}}}
        """#.utf8)

        let team = try JSONDecoder().decode(MLBStatsDTO.BoxscoreTeam.self, from: json)

        XCTAssertEqual(team.battingOrder, [665862, 592450])
        XCTAssertEqual(team.pitchers, [543037])
        XCTAssertEqual(team.team?.abbreviation, "NYY")
        XCTAssertEqual(team.players?["ID665862"]?.person?.fullName, "Jazz Chisholm Jr.")
        XCTAssertEqual(
            Position(
                mlbCode: team.players?["ID665862"]?.position?.code?.value,
                abbreviation: nil
            ),
            .secondBase
        )
    }

    /// An unexpected shape yields an empty value rather than throwing, so one
    /// odd field can't take the import down with it.
    func testUnexpectedShapeDegradesToEmpty() throws {
        let json = Data(#"{"jerseyNumber":{"nested":true}}"#.utf8)
        let player = try JSONDecoder().decode(MLBStatsDTO.BoxscorePlayer.self, from: json)

        XCTAssertEqual(player.jerseyNumber?.value, "")
    }
}

final class MLBStatsMappingTests: XCTestCase {

    func testPositionCodesMapToScorebookNumbers() {
        XCTAssertEqual(Position(mlbCode: "1", abbreviation: "P"), .pitcher)
        XCTAssertEqual(Position(mlbCode: "6", abbreviation: "SS"), .shortstop)
        XCTAssertEqual(Position(mlbCode: "10", abbreviation: "DH"), .designatedHitter)
    }

    /// Utility and two-way players carry letter codes that don't name a single
    /// spot on the field, so the abbreviation has to carry it.
    func testLetterCodesFallBackToTheAbbreviation() {
        XCTAssertEqual(Position(mlbCode: "Y", abbreviation: "CF"), .centerField)
        XCTAssertNil(Position(mlbCode: "O", abbreviation: nil))
        XCTAssertNil(Position(mlbCode: nil, abbreviation: "???"))
    }

    func testAbbreviationFallbackForTeamsWithoutOne() {
        XCTAssertEqual(MLBStatsProvider.abbreviate("Tampa Bay Rays"), "BR")
        XCTAssertEqual(MLBStatsProvider.abbreviate("Athletics"), "ATH")
    }

    func testTimestampsParseWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(MLBStatsProvider.parseTimestamp("2026-08-03T23:05:00Z"))
        XCTAssertNotNil(MLBStatsProvider.parseTimestamp("2026-08-03T23:05:00.000Z"))
        XCTAssertNil(MLBStatsProvider.parseTimestamp("not a date"))
    }

    /// Incomplete plays and runner-only events carry no batting result, and
    /// must not be counted as plate appearances.
    func testPlaysWithoutAResultAreSkipped() {
        let noEvent = MLBStatsDTO.PlayDTO(
            result: MLBStatsDTO.PlayResultDTO(eventType: ""),
            about: MLBStatsDTO.PlayAboutDTO(atBatIndex: 3, halfInning: "top", inning: 1, isComplete: true),
            matchup: nil
        )
        XCTAssertNil(MLBStatsProvider.officialPlay(from: noEvent))

        let incomplete = MLBStatsDTO.PlayDTO(
            result: MLBStatsDTO.PlayResultDTO(eventType: "single"),
            about: MLBStatsDTO.PlayAboutDTO(atBatIndex: 4, halfInning: "top", inning: 1, isComplete: false),
            matchup: nil
        )
        XCTAssertNil(MLBStatsProvider.officialPlay(from: incomplete))
    }

    func testCompletePlayMapsToAnOfficialPlay() {
        let dto = MLBStatsDTO.PlayDTO(
            result: MLBStatsDTO.PlayResultDTO(
                type: "atBat",
                event: "Single",
                eventType: "single",
                description: "Chisholm Jr. singles to right.",
                rbi: 1,
                isOut: false
            ),
            about: MLBStatsDTO.PlayAboutDTO(
                atBatIndex: 7,
                halfInning: "bottom",
                inning: 9,
                isComplete: true
            ),
            matchup: MLBStatsDTO.PlayMatchupDTO(
                batter: MLBStatsDTO.PersonDTO(id: 665862, fullName: "Jazz Chisholm Jr."),
                pitcher: nil
            )
        )

        let play = MLBStatsProvider.officialPlay(from: dto)

        XCTAssertEqual(play?.inning, 9)
        XCTAssertEqual(play?.half, .bottom)
        XCTAssertEqual(play?.rbi, 1)
        XCTAssertEqual(play?.batterExternalID, "665862")
        XCTAssertEqual(play?.category, .single)
    }
}
