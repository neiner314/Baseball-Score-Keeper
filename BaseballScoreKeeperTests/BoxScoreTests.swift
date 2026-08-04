import XCTest
@testable import BaseballScoreKeeper

final class BoxScoreTests: XCTestCase {

    func testBattingLineCountsAtBatsAndHits() {
        var driver = GameDriver()
        let batterID = driver.state.currentBatterID
        driver.single()

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.batting.away.first { $0.player.id == batterID }

        XCTAssertEqual(line?.atBats, 1)
        XCTAssertEqual(line?.hits, 1)
        XCTAssertEqual(line?.summary, "1-for-1")
    }

    func testWalksAreNotAtBats() {
        var driver = GameDriver()
        let batterID = driver.state.currentBatterID
        driver.walk()

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.batting.away.first { $0.player.id == batterID }

        XCTAssertEqual(line?.atBats, 0)
        XCTAssertEqual(line?.walks, 1)
    }

    func testNotationsAccumulateInOrder() {
        var driver = GameDriver()
        let batterID = driver.state.currentBatterID

        driver.strikeout()
        driver.retireSide()   // finish the half
        driver.retireSide()   // and the home half, so the order comes back around

        // Cycle back to the same batter.
        while driver.state.currentBatterID != batterID, !driver.state.isFinal {
            driver.strikeout()
        }
        driver.play(.fieldOut(fielders: [.thirdBase], batted: BattedBall(trajectory: .flyBall)))

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.batting.away.first { $0.player.id == batterID }

        XCTAssertEqual(line?.notations.first, "K")
        XCTAssertEqual(line?.notations.last, "F5")
    }

    func testRunsAndRunsBattedInAreCredited() {
        var driver = GameDriver()
        let leadoffID = driver.state.currentBatterID
        driver.walk()
        let sluggerID = driver.state.currentBatterID
        driver.homeRun()

        let box = BoxScoreBuilder.build(document: driver.document)
        let leadoff = box.batting.away.first { $0.player.id == leadoffID }
        let slugger = box.batting.away.first { $0.player.id == sluggerID }

        XCTAssertEqual(leadoff?.runs, 1)
        XCTAssertEqual(leadoff?.rbis, 0)
        XCTAssertEqual(slugger?.runs, 1)
        XCTAssertEqual(slugger?.rbis, 2)
        XCTAssertEqual(slugger?.homeRuns, 1)
    }

    func testPitchingLineTracksOutsHitsAndStrikeouts() {
        var driver = GameDriver()
        let pitcherID = driver.state.lineups.home.currentPitcherID
        driver.strikeout()
        driver.single()
        driver.strikeout()
        driver.strikeout()

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.pitching.home.first { $0.player.id == pitcherID }

        XCTAssertEqual(line?.outsRecorded, 3)
        XCTAssertEqual(line?.inningsPitched, "1.0")
        XCTAssertEqual(line?.strikeouts, 3)
        XCTAssertEqual(line?.hits, 1)
    }

    func testPitchCountAccumulates() {
        var driver = GameDriver()
        let pitcherID = driver.state.lineups.home.currentPitcherID
        driver.strikeout()   // three pitches
        driver.walk()        // four more

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.pitching.home.first { $0.player.id == pitcherID }

        XCTAssertEqual(line?.pitches, 7)
        XCTAssertEqual(line?.strikes, 3)
    }

    func testEarnedRunsExcludeRunnersWhoReachedOnAnError() {
        var driver = GameDriver()
        let pitcherID = driver.state.lineups.home.currentPitcherID
        driver.play(.error(fielder: .shortstop, batted: nil, basesAwarded: 1))
        driver.homeRun()

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.pitching.home.first { $0.player.id == pitcherID }

        XCTAssertEqual(line?.runs, 2)
        XCTAssertEqual(line?.earnedRuns, 1)
    }

    func testTeamTotalsMatchTheLineScore() {
        var driver = GameDriver()
        driver.single()
        driver.homeRun()

        let box = BoxScoreBuilder.build(document: driver.document)

        XCTAssertEqual(box.totals.away.runs, 2)
        XCTAssertEqual(box.totals.away.hits, 2)
        XCTAssertEqual(box.totals.home.runs, 0)
    }

    func testErrorsAreChargedToTheFieldingTeam() {
        var driver = GameDriver()
        driver.play(.error(fielder: .secondBase, batted: nil, basesAwarded: 1))

        let box = BoxScoreBuilder.build(document: driver.document)
        XCTAssertEqual(box.totals.home.errors, 1)
        XCTAssertEqual(box.totals.away.errors, 0)
    }

    func testSubstituteGetsTheirOwnBattingLine() {
        var driver = GameDriver()
        let bench = driver.document.teams.away.players.last { $0.name.contains("Bench") }
        XCTAssertNotNil(bench)

        driver.apply(
            .substitution(
                Substitution(
                    side: .away,
                    kind: .pinchHitter,
                    incomingPlayerID: bench!.id,
                    outgoingPlayerID: driver.state.lineups.away.slots[0].playerID,
                    battingSlot: 0,
                    position: .designatedHitter,
                    runnerBase: nil
                )
            )
        )
        driver.single()

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.batting.away.first { $0.player.id == bench?.id }

        XCTAssertNotNil(line)
        XCTAssertTrue(line?.isSubstitute ?? false)
        XCTAssertEqual(line?.hits, 1)
    }

    func testWinAndLossAreAssignedWhenTheGameIsFinal() {
        var driver = GameDriver()
        let homePitcher = driver.state.lineups.home.currentPitcherID
        let awayPitcher = driver.state.lineups.away.currentPitcherID

        // Home scores once in the first and holds on.
        driver.retireSide()
        driver.homeRun()
        driver.retireSide()
        driver.advance(toInning: 9, half: .top)
        driver.retireSide()

        XCTAssertTrue(driver.state.isFinal)

        let box = BoxScoreBuilder.build(document: driver.document)
        let winner = box.pitching.home.first { $0.player.id == homePitcher }
        let loser = box.pitching.away.first { $0.player.id == awayPitcher }

        XCTAssertEqual(winner?.decision, .win)
        XCTAssertEqual(loser?.decision, .loss)
    }

    func testNoDecisionsWhileTheGameIsStillGoing() {
        var driver = GameDriver()
        driver.homeRun()

        let box = BoxScoreBuilder.build(document: driver.document)
        XCTAssertFalse(box.isFinal)
        XCTAssertTrue(box.pitching.home.allSatisfy { $0.decision == nil })
        XCTAssertTrue(box.pitching.away.allSatisfy { $0.decision == nil })
    }

    func testUnplayedBottomOfTheNinthShowsAsUnplayed() {
        var driver = GameDriver()
        driver.retireSide()
        driver.homeRun()
        driver.retireSide()
        driver.advance(toInning: 9, half: .top)
        driver.retireSide()

        let box = BoxScoreBuilder.build(document: driver.document)
        XCTAssertNil(box.lineScore[8].home, "the home team never came to bat in the ninth")
        XCTAssertEqual(box.lineScore[8].away, 0)
    }
}
