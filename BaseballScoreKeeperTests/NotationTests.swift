import XCTest
import CoreGraphics
@testable import BaseballScoreKeeper

final class NotationTests: XCTestCase {

    func testGroundOutReadsAsAFieldingChain() {
        let outcome = PlayOutcome.fieldOut(
            fielders: [.shortstop, .firstBase],
            batted: BattedBall(trajectory: .grounder)
        )
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard), "6-3")
    }

    func testFullDetailPrefixesTheTrajectory() {
        let outcome = PlayOutcome.fieldOut(
            fielders: [.shortstop, .firstBase],
            batted: BattedBall(trajectory: .liner)
        )
        XCTAssertEqual(Notation.text(for: outcome, detail: .full), "L6-3")
    }

    func testFlyBallToOneFielderReadsAsF() {
        let outcome = PlayOutcome.fieldOut(
            fielders: [.centerField],
            batted: BattedBall(trajectory: .flyBall)
        )
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard), "F8")
    }

    func testPopUpAndLineOutUseTheirOwnMarks() {
        let pop = PlayOutcome.fieldOut(fielders: [.secondBase], batted: BattedBall(trajectory: .popup))
        let liner = PlayOutcome.fieldOut(fielders: [.shortstop], batted: BattedBall(trajectory: .liner))

        XCTAssertEqual(Notation.text(for: pop, detail: .standard), "P4")
        XCTAssertEqual(Notation.text(for: liner, detail: .standard), "L6")
    }

    func testUnassistedGroundOutIsMarkedU() {
        let outcome = PlayOutcome.fieldOut(
            fielders: [.firstBase],
            batted: BattedBall(trajectory: .grounder)
        )
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard), "3U")
    }

    func testStrikeoutsDistinguishLookingFromSwinging() {
        let swinging = PlayOutcome.strikeout(looking: false, uncaught: false)
        let looking = PlayOutcome.strikeout(looking: true, uncaught: false)

        XCTAssertEqual(Notation.text(for: swinging, detail: .standard), "K")
        XCTAssertEqual(Notation.text(for: looking, detail: .standard), Notation.calledStrikeoutMark)
    }

    func testDoublePlayKeepsTheWholeChain() {
        let outcome = PlayOutcome.doublePlay(
            fielders: [.secondBase, .shortstop, .firstBase],
            batted: BattedBall(trajectory: .grounder)
        )
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard), "4-6-3 DP")
    }

    func testErrorNamesTheFielder() {
        let outcome = PlayOutcome.error(fielder: .thirdBase, batted: nil, basesAwarded: 1)
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard), "E5")
    }

    func testRunsBattedInAreAppended() {
        let outcome = PlayOutcome.hit(.double, batted: nil, fielder: .leftField)
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard, rbis: 2), "2B+2")
        XCTAssertEqual(Notation.text(for: outcome, detail: .standard, rbis: 0), "2B")
    }

    func testSacrificesUseTheirOwnMarks() {
        XCTAssertEqual(
            Notation.text(for: .sacrificeFly(fielder: .centerField), detail: .standard),
            "SF8"
        )
        XCTAssertEqual(
            Notation.text(for: .sacrificeBunt(fielders: [.pitcher, .firstBase]), detail: .standard),
            "SH 1-3"
        )
    }

    func testInningsPitchedUsesThirds() {
        XCTAssertEqual(Notation.inningsPitched(outs: 0), "0.0")
        XCTAssertEqual(Notation.inningsPitched(outs: 17), "5.2")
        XCTAssertEqual(Notation.inningsPitched(outs: 27), "9.0")
    }

    func testBattingLineFormat() {
        XCTAssertEqual(Notation.battingLine(hits: 2, atBats: 4), "2-for-4")
    }
}

final class FlickDirectionTests: XCTestCase {

    func testShortDragStaysOnTheRestingAction() {
        let direction = FlickDirection.from(
            translation: CGSize(width: 8, height: -6),
            threshold: 26
        )
        XCTAssertEqual(direction, .center)
    }

    func testDominantAxisWins() {
        XCTAssertEqual(
            FlickDirection.from(translation: CGSize(width: 40, height: -12), threshold: 26),
            .right
        )
        XCTAssertEqual(
            FlickDirection.from(translation: CGSize(width: -12, height: -40), threshold: 26),
            .up
        )
        XCTAssertEqual(
            FlickDirection.from(translation: CGSize(width: 5, height: 60), threshold: 26),
            .down
        )
        XCTAssertEqual(
            FlickDirection.from(translation: CGSize(width: -55, height: 4), threshold: 26),
            .left
        )
    }

    func testDiagonalDragsResolveRatherThanFallingThrough() {
        // Exactly diagonal: vertical wins, so a sloppy flick still commits.
        let direction = FlickDirection.from(
            translation: CGSize(width: 30, height: 30),
            threshold: 26
        )
        XCTAssertEqual(direction, .down)
    }

    func testThresholdIsInclusive() {
        let direction = FlickDirection.from(
            translation: CGSize(width: 0, height: -26),
            threshold: 26
        )
        XCTAssertEqual(direction, .up)
    }
}

final class FieldGeometryTests: XCTestCase {

    func testNearestPositionFindsTheFielderUnderTheFinger() {
        let size = CGSize(width: 300, height: 300)
        let centerFieldPoint = FieldGeometry.point(for: .centerField, in: size)
        let nudged = CGPoint(x: centerFieldPoint.x + 5, y: centerFieldPoint.y + 5)

        XCTAssertEqual(FieldGeometry.nearestPosition(to: nudged, in: size), .centerField)
    }

    func testFarAwayTouchSelectsNobodyWhenBounded() {
        let size = CGSize(width: 300, height: 300)
        let corner = CGPoint(x: 0, y: 0)

        XCTAssertNil(
            FieldGeometry.nearestPosition(to: corner, in: size, maximumDistance: 20)
        )
    }

    func testEveryFielderHasADistinctSpot() {
        let size = CGSize(width: 400, height: 400)
        var seen: Set<String> = []
        for position in Position.fielders {
            let point = FieldGeometry.point(for: position, in: size)
            seen.insert("\(Int(point.x))-\(Int(point.y))")
        }
        XCTAssertEqual(seen.count, Position.fielders.count)
    }
}
