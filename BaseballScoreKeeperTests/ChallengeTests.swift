import XCTest
@testable import BaseballScoreKeeper

final class ChallengeTests: XCTestCase {

    // MARK: - What can be challenged

    func testOnlyUmpireLocationCallsAreChallengeable() {
        XCTAssertTrue(PitchOutcome.ball.isChallengeable)
        XCTAssertTrue(PitchOutcome.calledStrike.isChallengeable)

        // A swing and miss, a foul and a ball in play are not judgements about
        // the strike zone, so there is nothing to review.
        XCTAssertFalse(PitchOutcome.swingingStrike.isChallengeable)
        XCTAssertFalse(PitchOutcome.foul.isChallengeable)
        XCTAssertFalse(PitchOutcome.inPlay.isChallengeable)
        XCTAssertFalse(PitchOutcome.hitByPitch.isChallengeable)
    }

    func testReversalFlipsTheCall() {
        XCTAssertEqual(PitchOutcome.ball.challengeReversal, .calledStrike)
        XCTAssertEqual(PitchOutcome.calledStrike.challengeReversal, .ball)
    }

    func testBatterChallengesForTheTeamAtBatAndTheBatteryForTheField() {
        XCTAssertEqual(ChallengeRole.batter.side(battingSide: .away), .away)
        XCTAssertEqual(ChallengeRole.pitcher.side(battingSide: .away), .home)
        XCTAssertEqual(ChallengeRole.catcher.side(battingSide: .away), .home)
    }

    // MARK: - Correcting the count

    func testOverturnedBallBecomesAStrike() {
        var driver = GameDriver()
        driver.pitch(.ball)
        XCTAssertEqual(driver.state.countLabel, "1-0")

        driver.challenge(role: .catcher, result: .stands, original: .ball)
        XCTAssertEqual(driver.state.countLabel, "1-0", "a failed challenge changes nothing")
    }

    func testWinningAChallengeCorrectsTheCount() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .overturned, original: .ball)

        XCTAssertEqual(driver.state.countLabel, "0-1", "the ball became a strike")
    }

    func testOverturnedStrikeBecomesABall() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.challenge(role: .batter, result: .overturned, original: .calledStrike)

        XCTAssertEqual(driver.state.countLabel, "1-0")
    }

    // MARK: - Undoing a plate appearance

    /// The case that makes this worth doing properly: winning a challenge on
    /// ball four means the walk never happened.
    func testOverturningBallFourUnwalksTheBatter() {
        var driver = GameDriver()
        let batter = driver.state.currentBatterID

        for _ in 0..<4 { driver.pitch(.ball) }
        XCTAssertNotNil(driver.state.bases.first, "walked, for now")
        XCTAssertNotEqual(driver.state.currentBatterID, batter)

        driver.challenge(role: .catcher, result: .overturned, original: .ball)

        XCTAssertNil(driver.state.bases.first, "the walk is undone")
        XCTAssertEqual(driver.state.currentBatterID, batter, "same man is still up")
        XCTAssertEqual(driver.state.countLabel, "3-1")
    }

    /// And the mirror: winning a challenge on strike three erases the out.
    func testOverturningStrikeThreeUnstrikesTheBatter() {
        var driver = GameDriver()
        let batter = driver.state.currentBatterID

        for _ in 0..<3 { driver.pitch(.calledStrike) }
        XCTAssertEqual(driver.state.outs, 1)

        driver.challenge(role: .batter, result: .overturned, original: .calledStrike)

        XCTAssertEqual(driver.state.outs, 0, "the strikeout is undone")
        XCTAssertEqual(driver.state.currentBatterID, batter)
        XCTAssertEqual(driver.state.countLabel, "1-2")
    }

    /// A correction that ends the at-bat rather than extending it.
    func testOverturningBallThreeIntoStrikeThreeRecordsTheOut() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.pitch(.calledStrike)
        driver.pitch(.ball)
        XCTAssertEqual(driver.state.outs, 0)

        driver.challenge(role: .catcher, result: .overturned, original: .ball)

        XCTAssertEqual(driver.state.outs, 1, "the corrected call was strike three")
        XCTAssertEqual(driver.state.countLabel, "0-0")
    }

    // MARK: - Keeping and losing challenges

    func testTeamsStartWithTheRuleBookAllowance() {
        let driver = GameDriver()
        XCTAssertEqual(driver.state.challengesRemaining.away, 2)
        XCTAssertEqual(driver.state.challengesRemaining.home, 2)
    }

    func testWinningAChallengeKeepsIt() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.challenge(role: .batter, result: .overturned, original: .calledStrike)

        XCTAssertEqual(driver.state.challengesRemaining.away, 2, "won, so not charged")
        XCTAssertEqual(driver.state.challengesRemaining.home, 2)
    }

    func testLosingAChallengeSpendsIt() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.challenge(role: .batter, result: .stands, original: .calledStrike)

        XCTAssertEqual(driver.state.challengesRemaining.away, 1)
        XCTAssertEqual(driver.state.challengesRemaining.home, 2, "the other team is untouched")
    }

    func testTheFieldingTeamIsChargedWhenTheBatteryChallenges() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .stands, original: .ball)

        XCTAssertEqual(driver.state.challengesRemaining.home, 1, "home was in the field")
        XCTAssertEqual(driver.state.challengesRemaining.away, 2)
    }

    func testChallengesCannotGoNegative() {
        var driver = GameDriver()
        for _ in 0..<5 {
            driver.pitch(.calledStrike)
            driver.challenge(role: .batter, result: .stands, original: .calledStrike)
        }
        XCTAssertEqual(driver.state.challengesRemaining.away, 0)
        XCTAssertGreaterThanOrEqual(driver.state.challengesRemaining.away, 0)
    }

    // MARK: - Extra innings

    func testExhaustedTeamsGetOneBackInExtraInnings() {
        var driver = GameDriver()
        driver.spendAwayChallenges()
        XCTAssertEqual(driver.state.challengesRemaining.away, 0)

        driver.advance(toInning: 10, half: .top)

        XCTAssertEqual(driver.state.challengesRemaining.away, 1, "spent team is topped up")
        XCTAssertEqual(driver.state.challengesRemaining.home, 2, "a team with some left keeps what it had")
    }

    /// The top-up repeats: a team that runs out again in the tenth is back to
    /// one for the eleventh, so neither side is ever without a challenge in
    /// extras.
    func testTheTopUpHappensEveryExtraInning() {
        var driver = GameDriver()
        driver.spendAwayChallenges()
        driver.advance(toInning: 10, half: .top)
        XCTAssertEqual(driver.state.challengesRemaining.away, 1)

        // Burn the replacement in the tenth.
        driver.pitch(.calledStrike)
        driver.challenge(role: .batter, result: .stands, original: .calledStrike)
        XCTAssertEqual(driver.state.challengesRemaining.away, 0)

        driver.advance(toInning: 11, half: .top)
        XCTAssertEqual(driver.state.challengesRemaining.away, 1, "topped up again for the eleventh")
    }

    /// It doesn't stack. A team still holding a challenge gets nothing extra.
    func testTheTopUpDoesNotAccumulate() {
        var driver = GameDriver()
        driver.advance(toInning: 12, half: .top)

        XCTAssertEqual(driver.state.challengesRemaining.away, 2, "never spent one, so still two")
        XCTAssertEqual(driver.state.challengesRemaining.home, 2)
    }

    func testATeamDownToOneIsNotToppedUp() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.challenge(role: .batter, result: .stands, original: .calledStrike)
        XCTAssertEqual(driver.state.challengesRemaining.away, 1)

        driver.advance(toInning: 10, half: .top)
        XCTAssertEqual(driver.state.challengesRemaining.away, 1, "one in hand is not topped back to two")
    }

    // MARK: - Marking the pitch

    func testAChallengedPitchIsFlaggedInTheSequence() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .overturned, original: .ball)

        let pitch = driver.state.currentAtBatPitches.last
        XCTAssertEqual(pitch?.challengeResult, .overturned)
        XCTAssertEqual(pitch?.outcome, .calledStrike, "the mark shows the corrected call")
    }

    func testAFailedChallengeStillFlagsThePitch() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .stands, original: .ball)

        let pitch = driver.state.currentAtBatPitches.last
        XCTAssertEqual(pitch?.challengeResult, .stands)
        XCTAssertEqual(pitch?.outcome, .ball, "the call was right, so it stands")
    }

    // MARK: - Resolution rules

    func testAChallengeOnlyReachesThePitchItFollows() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .overturned, original: .ball)

        // Only the second ball is corrected; the first is long gone.
        XCTAssertEqual(driver.state.countLabel, "1-1")
    }

    func testAChallengeWithNoPitchBeforeItDoesNothing() {
        var driver = GameDriver()
        driver.challenge(role: .batter, result: .overturned, original: .calledStrike)

        XCTAssertEqual(driver.state.countLabel, "0-0")
        XCTAssertTrue(driver.state.bases.isEmpty)
    }

    func testResolutionLeavesALogWithoutChallengesAlone() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.pitch(.calledStrike)

        let resolved = ScoringEngine.resolved(driver.document.events)
        XCTAssertEqual(resolved, driver.document.events)
    }

    // MARK: - Replay and undo

    func testReplayReproducesAChallengedGame() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .overturned, original: .ball)
        driver.pitch(.calledStrike)

        let replayed = ScoringEngine.replay(document: driver.document)
        XCTAssertEqual(replayed, driver.state)
    }

    /// Dropping the challenge event un-corrects the pitch, because the
    /// correction only ever existed in the resolved stream.
    func testRemovingTheChallengeRestoresTheOriginalCall() {
        var driver = GameDriver()
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .overturned, original: .ball)
        XCTAssertEqual(driver.state.countLabel, "0-1")

        var document = driver.document
        document.events.removeLast()
        let reverted = ScoringEngine.replay(document: document)

        XCTAssertEqual(reverted.countLabel, "1-0", "back to the umpire's call")
        XCTAssertEqual(reverted.challengesRemaining.home, 2)
    }

    // MARK: - Box score

    func testBoxScoreRecordsEachChallenge() {
        var driver = GameDriver()
        driver.pitch(.calledStrike)
        driver.challenge(role: .batter, result: .overturned, original: .calledStrike)
        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .stands, original: .ball)

        let box = BoxScoreBuilder.build(document: driver.document)
        XCTAssertEqual(box.challenges.count, 2)

        let away = box.challengeRecord(for: .away)
        XCTAssertEqual(away.won, 1)
        XCTAssertEqual(away.used, 1)

        let home = box.challengeRecord(for: .home)
        XCTAssertEqual(home.won, 0)
        XCTAssertEqual(home.used, 1)

        XCTAssertEqual(box.challengesRemaining.away, 2, "won it, kept it")
        XCTAssertEqual(box.challengesRemaining.home, 1)
    }

    func testBoxScoreCountsTheCorrectedCallForThePitcher() {
        var driver = GameDriver()
        let pitcherID = driver.state.lineups.home.currentPitcherID

        driver.pitch(.ball)
        driver.challenge(role: .catcher, result: .overturned, original: .ball)

        let box = BoxScoreBuilder.build(document: driver.document)
        let line = box.pitching.home.first { $0.player.id == pitcherID }

        XCTAssertEqual(line?.pitches, 1)
        XCTAssertEqual(line?.strikes, 1, "it counts as a strike once overturned")
    }

    func testChallengesAreDisabledWhenTheRulesSayZero() {
        var rules = GameRules.standard
        rules.challengesPerTeam = 0
        XCTAssertFalse(rules.usesChallenges)

        let document = GameFactory.newGame(
            away: GameFactory.placeholderRoster(name: "Away", abbreviation: "AWY"),
            home: GameFactory.placeholderRoster(name: "Home", abbreviation: "HME"),
            rules: rules
        )
        let state = ScoringEngine.initialState(document: document)
        XCTAssertEqual(state.challengesRemaining.away, 0)
    }

    // MARK: - Saved-game compatibility

    /// Rules and settings decode leniently, so a game saved before challenges
    /// existed still opens.
    func testOlderSavedRulesStillDecode() throws {
        let json = Data(#"{"regulationInnings":9,"usesDesignatedHitter":true,"extraInningRunnerOnSecond":false}"#.utf8)
        let rules = try JSONDecoder().decode(GameRules.self, from: json)

        XCTAssertEqual(rules.regulationInnings, 9)
        XCTAssertEqual(rules.challengesPerTeam, 2, "falls back to the current default")
    }

    func testOlderSavedSettingsStillDecode() throws {
        let json = Data(#"{"trackPitchVelocity":false,"notationDetail":"full"}"#.utf8)
        let settings = try JSONDecoder().decode(TrackingSettings.self, from: json)

        XCTAssertFalse(settings.trackPitchVelocity)
        XCTAssertEqual(settings.notationDetail, .full)
        XCTAssertTrue(settings.trackChallenges, "new options take their default")
    }
}
