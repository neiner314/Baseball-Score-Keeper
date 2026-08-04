import XCTest
@testable import BaseballScoreKeeper

/// The scorebook is built by watching the engine rather than by re-deriving the
/// rules, so these tests are mostly about whether it watches correctly: does a
/// runner's box keep filling in after the at-bat that opened it?
final class ScorebookTests: XCTestCase {

    private func page(_ driver: GameDriver, _ side: Side) -> ScorebookPage {
        ScorebookBuilder.build(document: driver.document)[side]
    }

    private func cell(_ driver: GameDriver, side: Side, slot: Int, inning: Int) -> ScorebookCell? {
        page(driver, side).rows.first { $0.slot == slot }?.cells(inning: inning).first
    }

    // MARK: - Boxes open

    func testStrikeoutFillsTheBoxWithAnOutNumber() {
        var driver = GameDriver()
        driver.strikeout()

        let box = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertEqual(box?.notation, "K")
        XCTAssertEqual(box?.outNumber, 1)
        XCTAssertEqual(box?.basesAdvanced, 0)
        XCTAssertTrue(box?.batterWasRetired == true)
    }

    func testSecondOutIsNumberedTwo() {
        var driver = GameDriver()
        driver.strikeout()
        driver.strikeout()

        XCTAssertEqual(cell(driver, side: .away, slot: 1, inning: 1)?.outNumber, 2)
    }

    func testSingleShadesOneBase() {
        var driver = GameDriver()
        driver.single()

        let box = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertEqual(box?.notation, "1B")
        XCTAssertEqual(box?.reached, .first)
        XCTAssertEqual(box?.basesAdvanced, 1)
        XCTAssertNil(box?.outNumber)
    }

    func testHomeRunGoesAllTheWayAround() {
        var driver = GameDriver()
        driver.homeRun()

        let box = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertEqual(box?.basesAdvanced, 4)
        XCTAssertTrue(box?.didScore == true)
        XCTAssertEqual(box?.rbis, 1)
    }

    // MARK: - Boxes keep filling in afterwards

    /// The heart of it: the leadoff man's box is closed as a single, and then
    /// the next batter's home run is what turns it into a run.
    func testRunnerBoxFillsInWhenALaterBatterDrivesThemIn() {
        var driver = GameDriver()
        driver.single()
        driver.homeRun()

        let leadoff = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertEqual(leadoff?.notation, "1B", "the notation stays what the batter did")
        XCTAssertTrue(leadoff?.didScore == true, "but the diamond closes when they score")
        XCTAssertEqual(leadoff?.basesAdvanced, 4)
        XCTAssertEqual(leadoff?.rbis, 0, "the RBI belongs to the batter who drove them in")

        XCTAssertEqual(page(driver, .away).runsByInning[1], 2)
        XCTAssertEqual(page(driver, .away).totalRuns, 2)
    }

    func testRunnerAdvancesPartWayAndStops() {
        var driver = GameDriver()
        driver.single()
        driver.single()

        let leadoff = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertEqual(leadoff?.reached, .second)
        XCTAssertEqual(leadoff?.basesAdvanced, 2)
        XCTAssertFalse(leadoff?.didScore == true)
    }

    func testStrandedRunnersAreMarkedLeftOnBase() {
        var driver = GameDriver()
        driver.single()
        driver.strikeout()
        driver.strikeout()
        driver.strikeout()

        let leadoff = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertTrue(leadoff?.wasLeftOnBase == true)
        XCTAssertEqual(page(driver, .away).leftOnBaseByInning[1], 1)
        XCTAssertEqual(page(driver, .away).totalLeftOnBase, 1)
    }

    func testRunnerErasedOnADoublePlayIsMarkedRetired() {
        var driver = GameDriver()
        driver.single()
        driver.play(
            .doublePlay(
                fielders: [.shortstop, .secondBase, .firstBase],
                batted: BattedBall(trajectory: .grounder)
            )
        )

        let leadoff = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertTrue(leadoff?.wasRetiredOnBases == true)
        XCTAssertFalse(leadoff?.didScore == true)

        let batter = cell(driver, side: .away, slot: 1, inning: 1)
        XCTAssertEqual(batter?.notation, "6-4-3 DP")
        XCTAssertEqual(batter?.outNumber, 2, "the batter is the back end of the relay")
    }

    func testCaughtStealingRetiresTheRunnersBox() {
        var driver = GameDriver()
        driver.single()
        driver.apply(.caughtStealing(from: .first))

        let leadoff = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertTrue(leadoff?.wasRetiredOnBases == true)
    }

    func testStolenBaseAdvancesTheBox() {
        var driver = GameDriver()
        driver.single()
        driver.apply(.stolenBase(from: .first))

        let leadoff = cell(driver, side: .away, slot: 0, inning: 1)
        XCTAssertEqual(leadoff?.reached, .second)
    }

    // MARK: - Page shape

    func testRowsExistForEverySlotBeforeAnyoneBats() {
        let driver = GameDriver()
        XCTAssertEqual(page(driver, .away).rows.count, 9)
        XCTAssertEqual(page(driver, .home).rows.count, 9)
    }

    func testEachTeamOnlyGetsItsOwnPlays() {
        var driver = GameDriver()
        driver.homeRun()
        driver.retireSide()

        XCTAssertEqual(page(driver, .away).totalRuns, 1)
        XCTAssertEqual(page(driver, .home).totalRuns, 0)
        XCTAssertNil(cell(driver, side: .home, slot: 0, inning: 1))
    }

    func testHitsAreCountedOnThePage() {
        var driver = GameDriver()
        driver.single()
        driver.single()
        driver.homeRun()

        XCTAssertEqual(page(driver, .away).totalHits, 3)
    }

    func testBattingAroundGivesASlotTwoBoxesInOneInning() {
        var driver = GameDriver()
        // Nine walks scores one and leaves the bases loaded, then the leadoff
        // man comes up again in the same inning.
        for _ in 0..<10 { driver.walk() }

        let boxes = page(driver, .away).rows.first { $0.slot == 0 }?.cells(inning: 1)
        XCTAssertEqual(boxes?.count, 2)
    }

    func testSecondInningOpensANewColumn() {
        var driver = GameDriver()
        driver.retireSide()
        driver.retireSide()
        driver.single()

        // Three strikeouts in the first means the order is up to the fourth
        // slot when the away team bats again.
        XCTAssertTrue(page(driver, .away).innings.contains(2))
        XCTAssertEqual(cell(driver, side: .away, slot: 3, inning: 2)?.notation, "1B")
        XCTAssertNil(cell(driver, side: .away, slot: 0, inning: 2))
    }
}
