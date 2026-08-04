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
