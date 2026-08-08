import XCTest
@testable import BaseballScoreKeeper

/// The scorer has to be able to say exactly who touched the ball and in what
/// order. These pin the chain down end to end: what the ring builds, and what
/// the book ends up reading.
final class FieldingChainTests: XCTestCase {

    private func notation(_ outcome: PlayOutcome?, detail: NotationDetail = .standard) -> String {
        guard let outcome else { return "<nil>" }
        return Notation.text(for: outcome, detail: detail)
    }

    // MARK: - One fielder gets the assumed throw

    func testGrounderToShortstopBecomesSixThree() {
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.shortstop],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "6-3")
    }

    func testFirstBasemanKeepsItUnassisted() {
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.firstBase],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "3U")
    }

    func testFlyBallStaysASingleFielder() {
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.centerField],
            trajectory: .flyBall,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "F8")
    }

    func testLinerToLeftIsLSeven() {
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.leftField],
            trajectory: .liner,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "L7")
    }

    // MARK: - An explicit chain is never second-guessed

    func testThreeToOneIsRecordedAsEntered() {
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.firstBase, .pitcher],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "3-1")
    }

    func testFiveToThreeIsRecordedAsEntered() {
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.thirdBase, .firstBase],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "5-3")
    }

    /// The rundown from the original ask. Nothing about the length is special —
    /// the chain is whatever the scorer tapped.
    func testLongRundownChainSurvivesIntact() {
        let chain: [Position] = [
            .shortstop, .secondBase, .firstBase, .catcher,
            .thirdBase, .pitcher, .shortstop
        ]
        let outcome = BallInPlayChoice.out.outcome(
            chain: chain,
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "6-4-3-2-5-1-6")
    }

    func testChainIsNotPaddedWithAThrowToFirst() {
        // 6-4 alone: the force at second, nobody covering first. Adding a "-3"
        // would be inventing a throw that never happened.
        let outcome = BallInPlayChoice.out.outcome(
            chain: [.shortstop, .secondBase],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "6-4")
    }

    // MARK: - Multi-out plays

    func testDoublePlayKeepsTheEnteredChain() {
        let outcome = BallInPlayChoice.doublePlay.outcome(
            chain: [.shortstop, .secondBase, .firstBase],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "6-4-3 DP")
    }

    func testDoublePlayFromOneFielderFillsInTheUsualShape() {
        let outcome = BallInPlayChoice.doublePlay.outcome(
            chain: [.shortstop],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "6-4-3 DP")
    }

    func testTriplePlayKeepsTheEnteredChain() {
        let outcome = BallInPlayChoice.triplePlay.outcome(
            chain: [.thirdBase, .secondBase, .firstBase],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "5-4-3 TP")
    }

    func testFieldersChoiceKeepsTheEnteredChain() {
        let outcome = BallInPlayChoice.fieldersChoice.outcome(
            chain: [.pitcher, .catcher],
            trajectory: .grounder,
            location: nil
        )
        XCTAssertEqual(notation(outcome), "FC 1-2")
    }

    // MARK: - Balls nobody fielded

    func testHomeRunNeedsNoFielder() {
        let outcome = BallInPlayChoice.homeRun.outcome(
            chain: [],
            trajectory: .flyBall,
            location: nil
        )
        XCTAssertEqual(outcome?.hitKind, .homeRun)
        XCTAssertNil(outcome?.primaryFielder)
        XCTAssertEqual(notation(outcome), "HR")
    }

    func testHitsAreAvailableWithNoFielder() {
        XCTAssertFalse(BallInPlayChoice.homeRun.requiresFielder)
        XCTAssertFalse(BallInPlayChoice.single.requiresFielder)
        XCTAssertTrue(BallInPlayChoice.out.requiresFielder)
        XCTAssertTrue(BallInPlayChoice.doublePlay.requiresFielder)
    }

    func testOutcomesThatNeedAFielderRefuseAnEmptyChain() {
        for choice in BallInPlayChoice.allCases where choice.requiresFielder {
            XCTAssertNil(
                choice.outcome(chain: [], trajectory: .grounder, location: nil),
                "\(choice.rawValue) should not build an outcome with nobody fielding it"
            )
        }
    }

    // MARK: - What the ring offers

    func testRingOffersHitsAndIntentionalWalkWithNoFielder() {
        let driver = GameDriver()
        let choices = BallInPlayChoice.choices(for: driver.state, chain: [])
        XCTAssertEqual(choices, [.single, .double, .triple, .homeRun, .intentionalWalk])
    }

    func testDoublePlayIsOfferedOnlyWithARunnerToErase() {
        var driver = GameDriver()
        XCTAssertFalse(
            BallInPlayChoice.choices(for: driver.state, chain: [.shortstop]).contains(.doublePlay)
        )

        driver.single()
        XCTAssertTrue(
            BallInPlayChoice.choices(for: driver.state, chain: [.shortstop]).contains(.doublePlay)
        )
    }

    func testSacrificeFlyIsOfferedOnlyWithARunnerOnThird() {
        var driver = GameDriver()
        driver.play(.hit(.triple, batted: BattedBall(trajectory: .liner), fielder: .rightField))
        XCTAssertTrue(
            BallInPlayChoice.choices(for: driver.state, chain: [.centerField]).contains(.sacrificeFly)
        )
    }
}
