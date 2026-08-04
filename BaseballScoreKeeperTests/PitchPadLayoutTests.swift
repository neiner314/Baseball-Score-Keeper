import XCTest
@testable import BaseballScoreKeeper

final class PitchPadLayoutTests: XCTestCase {

    // MARK: - The count axis

    func testBallIsALeftFlick() {
        XCTAssertEqual(PitchPadLayout.outcome(for: .left), .ball)
    }

    func testStrikeIsARightFlick() {
        let outcome = PitchPadLayout.outcome(for: .right)
        XCTAssertEqual(outcome, .swingingStrike)
        XCTAssertEqual(outcome?.isStrike, true)
    }

    /// The whole point of the mapping: the horizontal axis reads the way a
    /// count is written, balls on the left and strikes on the right.
    func testHorizontalAxisMatchesTheScoreboard() {
        XCTAssertEqual(PitchPadLayout.outcome(for: .left)?.countsAsBall, true)
        XCTAssertEqual(PitchPadLayout.outcome(for: .left)?.isStrike, false)

        XCTAssertEqual(PitchPadLayout.outcome(for: .right)?.isStrike, true)
        XCTAssertEqual(PitchPadLayout.outcome(for: .right)?.countsAsBall, false)
    }

    /// Up traces where a tipped ball actually goes — up and back over the
    /// catcher. Down is the ball settling into the zone untouched.
    func testVerticalAxisFollowsTheBall() {
        XCTAssertEqual(PitchPadLayout.outcome(for: .up), .foul)
        XCTAssertEqual(PitchPadLayout.outcome(for: .down), .calledStrike)
    }

    func testBothVerticalFlicksAreStrikes() {
        XCTAssertEqual(PitchPadLayout.outcome(for: .up)?.isStrike, true)
        XCTAssertEqual(PitchPadLayout.outcome(for: .down)?.isStrike, true)
    }

    /// The four flicks are the four things a pitch can do, each exactly once.
    func testEveryFlickIsADistinctOutcome() {
        let outcomes = [FlickDirection.up, .down, .left, .right]
            .compactMap { PitchPadLayout.outcome(for: $0) }

        XCTAssertEqual(outcomes.count, 4)
        XCTAssertEqual(Set(outcomes).count, 4, "no two flicks may record the same thing")
        XCTAssertEqual(
            Set(outcomes),
            [.ball, .calledStrike, .swingingStrike, .foul]
        )
    }

    /// Ball is the only gesture on the pad that adds to the balls column, so
    /// there is exactly one leftward flick and everything else is a strike.
    func testBallIsTheOnlyNonStrikeFlick() {
        let flicks: [FlickDirection] = [.up, .down, .left, .right]
        let nonStrikes = flicks.filter { PitchPadLayout.outcome(for: $0)?.isStrike == false }
        XCTAssertEqual(nonStrikes, [.left])
    }

    // MARK: - Tap

    func testTapIsBallInPlay() {
        XCTAssertEqual(PitchPadLayout.outcome(for: .center), .inPlay)
    }

    /// A tap opens the fielder dial rather than writing anything, so brushing
    /// the pad costs a dismissal instead of an undo.
    func testTapDoesNotRecordImmediately() {
        XCTAssertFalse(PitchPadLayout.recordsImmediately(.center))
    }

    func testEveryFlickRecordsImmediately() {
        for direction in [FlickDirection.up, .down, .left, .right] {
            XCTAssertTrue(
                PitchPadLayout.recordsImmediately(direction),
                "\(direction) should write a pitch straight away"
            )
        }
    }

    // MARK: - Hit by pitch

    func testHitByPitchIsTheHeldOutcome() {
        XCTAssertEqual(PitchPadLayout.heldOutcome, .hitByPitch)
    }

    /// Hit by pitch ends the plate appearance, so it must not be reachable by
    /// any flick — only by a deliberate press-and-hold.
    func testHitByPitchIsUnreachableByFlicking() {
        for direction in FlickDirection.allCases {
            XCTAssertNotEqual(
                PitchPadLayout.outcome(for: direction),
                .hitByPitch,
                "\(direction) must not record a hit by pitch"
            )
        }
    }

    func testHoldIsLongEnoughToBeDeliberate() {
        XCTAssertGreaterThanOrEqual(PitchPadLayout.holdDuration, 0.4)
    }

    // MARK: - Presentation

    func testEveryDirectionHasALabelledOption() {
        for direction in FlickDirection.allCases {
            XCTAssertNotNil(
                PitchPadLayout.options[direction],
                "\(direction) needs a chip or the pad would silently cancel"
            )
        }
    }

    func testOptionLabelsMatchTheOutcomes() {
        XCTAssertEqual(PitchPadLayout.options[.left]?.title, "Ball")
        XCTAssertEqual(PitchPadLayout.options[.right]?.title, "Miss")
        XCTAssertEqual(PitchPadLayout.options[.up]?.title, "Foul")
        XCTAssertEqual(PitchPadLayout.options[.down]?.title, "Call")
        XCTAssertEqual(PitchPadLayout.options[.center]?.title, "In Play")
        XCTAssertEqual(PitchPadLayout.holdOption.title, "HBP")
    }

    // MARK: - Interaction with the engine

    func testFlickingLeftFourTimesWalksTheBatter() {
        var driver = GameDriver()
        guard let ball = PitchPadLayout.outcome(for: .left) else {
            return XCTFail("left flick should map to a pitch")
        }

        for _ in 0..<4 { driver.pitch(ball) }

        XCTAssertNotNil(driver.state.bases.first)
        XCTAssertEqual(driver.state.balls, 0)
    }

    func testFlickingRightThreeTimesStrikesHimOut() {
        var driver = GameDriver()
        guard let strike = PitchPadLayout.outcome(for: .right) else {
            return XCTFail("right flick should map to a pitch")
        }

        for _ in 0..<3 { driver.pitch(strike) }

        XCTAssertEqual(driver.state.outs, 1)
    }

    /// A full count is three balls and two strikes — three left flicks and two
    /// right ones, reading 3-2 exactly as the scoreboard shows it.
    func testThreeLeftAndTwoRightIsAFullCount() {
        var driver = GameDriver()
        for _ in 0..<3 { driver.pitch(.ball) }
        for _ in 0..<2 { driver.pitch(.calledStrike) }

        XCTAssertTrue(driver.state.isFullCount)
        XCTAssertEqual(driver.state.countLabel, "3-2")
    }
}
