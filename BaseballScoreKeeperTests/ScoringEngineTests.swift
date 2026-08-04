import XCTest
@testable import BaseballScoreKeeper

final class ScoringEngineTests: XCTestCase {

    // MARK: - Count

    func testBallsAndStrikesAccumulate() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.pitch(.calledStrike)

        XCTAssertEqual(driver.state.balls, 1)
        XCTAssertEqual(driver.state.strikes, 1)
    }

    func testFourBallsPutsBatterOnFirstAndResetsCount() {
        var driver = GameDriver()
        let batter = driver.state.currentBatterID
        driver.walk()

        XCTAssertEqual(driver.state.bases.first?.playerID, batter)
        XCTAssertEqual(driver.state.balls, 0)
        XCTAssertEqual(driver.state.strikes, 0)
        XCTAssertNotEqual(driver.state.currentBatterID, batter, "the order should have moved on")
    }

    func testThreeStrikesRecordsAnOut() {
        var driver = GameDriver()
        driver.strikeout()

        XCTAssertEqual(driver.state.outs, 1)
        XCTAssertTrue(driver.state.bases.isEmpty)
    }

    func testFoulWithTwoStrikesDoesNotStrikeOut() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.pitch(.calledStrike)
        driver.pitch(.foul)
        driver.pitch(.foul)

        XCTAssertEqual(driver.state.strikes, 2)
        XCTAssertEqual(driver.state.outs, 0)
    }

    func testFoulBelowTwoStrikesCounts() {
        var driver = GameDriver()
        driver.pitch(.foul)

        XCTAssertEqual(driver.state.strikes, 1)
    }

    // MARK: - Half innings

    func testThreeOutsFlipsTheHalfInning() {
        var driver = GameDriver()
        driver.strikeout()
        driver.strikeout()
        driver.strikeout()

        XCTAssertEqual(driver.state.half, .bottom)
        XCTAssertEqual(driver.state.inning, 1)
        XCTAssertEqual(driver.state.outs, 0)
    }

    func testBottomHalfEndingAdvancesTheInning() {
        var driver = GameDriver()
        driver.retireSide()
        driver.retireSide()

        XCTAssertEqual(driver.state.inning, 2)
        XCTAssertEqual(driver.state.half, .top)
    }

    func testStrandedRunnersCountAsLeftOnBase() {
        var driver = GameDriver()
        driver.walk()
        driver.walk()
        driver.strikeout()
        driver.strikeout()
        driver.strikeout()

        XCTAssertEqual(driver.state.leftOnBase.away, 2)
    }

    // MARK: - Advancement

    func testSingleMovesEveryRunnerUpOneBase() {
        var driver = GameDriver()
        driver.walk()
        let runner = driver.state.bases.first?.playerID
        driver.single()

        XCTAssertEqual(driver.state.bases.second?.playerID, runner)
        XCTAssertNotNil(driver.state.bases.first)
        XCTAssertEqual(driver.awayRuns, 0)
    }

    func testWalkOnlyAdvancesForcedRunners() {
        var driver = GameDriver()
        // Runner to second with nobody on first: a walk must not move them.
        driver.play(.hit(.double, batted: nil, fielder: .leftField))
        let runner = driver.state.bases.second?.playerID
        driver.walk()

        XCTAssertEqual(driver.state.bases.second?.playerID, runner)
        XCTAssertNotNil(driver.state.bases.first)
    }

    func testBasesLoadedWalkForcesInARun() {
        var driver = GameDriver()
        driver.walk()
        driver.walk()
        driver.walk()
        XCTAssertTrue(driver.state.bases.areLoaded)

        driver.walk()
        XCTAssertEqual(driver.awayRuns, 1)
        XCTAssertTrue(driver.state.bases.areLoaded)
    }

    func testHomeRunScoresEveryone() {
        var driver = GameDriver()
        driver.walk()
        driver.walk()
        driver.homeRun()

        XCTAssertEqual(driver.awayRuns, 3)
        XCTAssertTrue(driver.state.bases.isEmpty)
    }

    func testTripleClearsTheBasesAndLeavesTheBatterOnThird() {
        var driver = GameDriver()
        driver.walk()
        driver.play(.hit(.triple, batted: nil, fielder: .rightField))

        XCTAssertEqual(driver.awayRuns, 1)
        XCTAssertNotNil(driver.state.bases.third)
        XCTAssertNil(driver.state.bases.first)
    }

    func testManualAdvanceOverridesTheDefault() {
        var driver = GameDriver()
        driver.walk()
        // Hold the runner at second instead of letting them take third.
        driver.play(
            .hit(.single, batted: nil, fielder: .centerField),
            advances: [ManualAdvance(from: .first, to: .second)]
        )

        XCTAssertNotNil(driver.state.bases.second)
        XCTAssertNil(driver.state.bases.third)
    }

    // MARK: - Outs and runs interacting

    func testSacrificeFlyScoresTheRunnerFromThird() {
        var driver = GameDriver()
        driver.play(.hit(.triple, batted: nil, fielder: .rightField))
        driver.play(.sacrificeFly(fielder: .centerField))

        XCTAssertEqual(driver.awayRuns, 1)
        XCTAssertEqual(driver.state.outs, 1)
    }

    func testThirdOutOnTheBatterCancelsRunsFromThePlay() {
        var driver = GameDriver()
        driver.strikeout()
        driver.strikeout()
        driver.play(.hit(.triple, batted: nil, fielder: .rightField))
        XCTAssertEqual(driver.state.outs, 2)

        // Runner tries to score on a ground out for the third out.
        driver.play(
            .fieldOut(fielders: [.shortstop, .firstBase], batted: BattedBall(trajectory: .grounder)),
            advances: [ManualAdvance(from: .third, to: .home)]
        )

        XCTAssertEqual(driver.awayRuns, 0, "no run scores when the batter is retired for the third out")
        XCTAssertEqual(driver.state.half, .bottom)
    }

    func testDoublePlayRetiresBatterAndRunnerOnFirst() {
        var driver = GameDriver()
        driver.walk()
        driver.play(.doublePlay(fielders: [.shortstop, .secondBase, .firstBase], batted: BattedBall(trajectory: .grounder)))

        XCTAssertEqual(driver.state.outs, 2)
        XCTAssertTrue(driver.state.bases.isEmpty)
    }

    func testFieldersChoiceRetiresTheLeadForcedRunner() {
        var driver = GameDriver()
        driver.walk()
        driver.play(.fieldersChoice(fielders: [.shortstop, .secondBase], batted: BattedBall(trajectory: .grounder)))

        XCTAssertEqual(driver.state.outs, 1)
        XCTAssertNotNil(driver.state.bases.first, "the batter is safe at first")
        XCTAssertNil(driver.state.bases.second)
    }

    // MARK: - Errors and earned runs

    func testErrorPutsTheBatterOnAndChargesTheDefence() {
        var driver = GameDriver()
        driver.play(.error(fielder: .shortstop, batted: BattedBall(trajectory: .grounder), basesAwarded: 1))

        XCTAssertNotNil(driver.state.bases.first)
        XCTAssertEqual(driver.state.errors.home, 1, "the fielding team is charged")
        XCTAssertEqual(driver.state.outs, 0)
    }

    func testRunnerWhoReachedOnAnErrorScoresAnUnearnedRun() {
        var driver = GameDriver()
        driver.play(.error(fielder: .shortstop, batted: nil, basesAwarded: 1))
        let result = driver.play(.hit(.homeRun, batted: nil, fielder: .centerField))

        XCTAssertEqual(result.runs.count, 2)
        let unearned = result.runs.filter { !$0.isEarned }
        XCTAssertEqual(unearned.count, 1, "only the runner who reached on the error is unearned")
    }

    // MARK: - Baserunning events

    func testStolenBaseMovesTheRunner() {
        var driver = GameDriver()
        driver.walk()
        driver.apply(.stolenBase(from: .first))

        XCTAssertNil(driver.state.bases.first)
        XCTAssertNotNil(driver.state.bases.second)
    }

    func testStealingHomeScores() {
        var driver = GameDriver()
        driver.play(.hit(.triple, batted: nil, fielder: .rightField))
        driver.apply(.stolenBase(from: .third))

        XCTAssertEqual(driver.awayRuns, 1)
        XCTAssertTrue(driver.state.bases.isEmpty)
    }

    func testCaughtStealingRecordsAnOut() {
        var driver = GameDriver()
        driver.walk()
        driver.apply(.caughtStealing(from: .first))

        XCTAssertEqual(driver.state.outs, 1)
        XCTAssertTrue(driver.state.bases.isEmpty)
    }

    func testWildPitchAdvancesRunnersAndAddsABall() {
        var driver = GameDriver()
        driver.walk()
        driver.pitch(.wildPitch)

        XCTAssertNotNil(driver.state.bases.second)
        XCTAssertNil(driver.state.bases.first)
        XCTAssertEqual(driver.state.balls, 1)
    }

    func testHitByPitchEndsThePlateAppearance() {
        var driver = GameDriver()
        driver.pitch(.hitByPitch)

        XCTAssertNotNil(driver.state.bases.first)
        XCTAssertEqual(driver.state.balls, 0)
    }

    // MARK: - Endings

    func testHomeTeamLeadingAfterTheTopOfTheNinthEndsTheGame() {
        var driver = GameDriver()
        driver.advance(toInning: 1, half: .bottom)
        driver.homeRun()
        driver.retireSide()

        driver.advance(toInning: 9, half: .top)
        XCTAssertFalse(driver.state.isFinal)

        driver.retireSide()
        XCTAssertTrue(driver.state.isFinal, "the home team never bats in the bottom of the ninth")
    }

    func testWalkOffEndsTheGameImmediately() {
        var driver = GameDriver()
        // Away scores one in the first so the game is not already decided.
        driver.homeRun()
        driver.retireSide()

        driver.advance(toInning: 9, half: .bottom)
        XCTAssertFalse(driver.state.isFinal)

        driver.homeRun()
        driver.homeRun()
        XCTAssertTrue(driver.state.isFinal)
        XCTAssertGreaterThan(driver.homeRuns, driver.awayRuns)
    }

    func testTieAfterNineContinuesIntoExtras() {
        var driver = GameDriver()
        driver.advance(toInning: 10, half: .top)

        XCTAssertFalse(driver.state.isFinal)
        XCTAssertEqual(driver.state.inning, 10)
    }

    func testExtraInningRunnerIsPlacedOnSecond() {
        var driver = GameDriver(extraInningRunner: true)
        driver.advance(toInning: 10, half: .top)

        XCTAssertNotNil(driver.state.bases.second)
        XCTAssertEqual(driver.state.bases.second?.reachedOnError, true, "a placed runner is never earned")
    }

    func testUnplayedHalfInningStaysNilInTheLineScore() {
        var driver = GameDriver()
        driver.pitch(.ball)

        XCTAssertEqual(driver.state.lineScore[0].away, 0)
        XCTAssertNil(driver.state.lineScore[0].home, "the home team has not batted yet")
    }

    // MARK: - Replay

    func testReplayReproducesTheSameState() {
        var driver = GameDriver()
        driver.walk()
        driver.single()
        driver.strikeout()
        driver.homeRun()

        let replayed = ScoringEngine.replay(document: driver.document)
        XCTAssertEqual(replayed, driver.state)
    }

    // MARK: - Substitutions

    func testPitchingChangeSwapsTheManOnTheMound() {
        var driver = GameDriver()
        let starter = driver.state.lineups.home.currentPitcherID
        let reliever = driver.document.teams.home.players.last { $0.primaryPosition == .pitcher }

        XCTAssertNotNil(reliever)
        driver.apply(
            .substitution(
                Substitution(
                    side: .home,
                    kind: .pitchingChange,
                    incomingPlayerID: reliever!.id,
                    outgoingPlayerID: starter,
                    battingSlot: nil,
                    position: .pitcher,
                    runnerBase: nil
                )
            )
        )

        XCTAssertEqual(driver.state.lineups.home.currentPitcherID, reliever?.id)
        XCTAssertNotEqual(driver.state.lineups.home.currentPitcherID, starter)
    }

    func testPinchRunnerTakesOverTheBase() {
        var driver = GameDriver()
        driver.walk()
        let original = driver.state.bases.first?.playerID
        let bench = driver.document.teams.away.players.last { $0.name.contains("Bench") }
        XCTAssertNotNil(bench)

        driver.apply(
            .substitution(
                Substitution(
                    side: .away,
                    kind: .pinchRunner,
                    incomingPlayerID: bench!.id,
                    outgoingPlayerID: original,
                    battingSlot: 0,
                    position: .designatedHitter,
                    runnerBase: .first
                )
            )
        )

        XCTAssertEqual(driver.state.bases.first?.playerID, bench?.id)
        XCTAssertNotEqual(driver.state.bases.first?.playerID, original)
    }
}
