import XCTest
@testable import BaseballScoreKeeper

final class ScoringCategoryTests: XCTestCase {

    func testAppOutcomesMapToCategories() {
        XCTAssertEqual(ScoringCategory(.hit(.single, batted: nil, fielder: nil)), .single)
        XCTAssertEqual(ScoringCategory(.hit(.homeRun, batted: nil, fielder: nil)), .homeRun)
        XCTAssertEqual(ScoringCategory(.walk(intentional: false)), .walk)
        XCTAssertEqual(ScoringCategory(.walk(intentional: true)), .walk)
        XCTAssertEqual(ScoringCategory(.strikeout(looking: true, uncaught: false)), .strikeout)
        XCTAssertEqual(ScoringCategory(.fieldOut(fielders: [.shortstop], batted: nil)), .fieldOut)
        XCTAssertEqual(ScoringCategory(.error(fielder: .shortstop, batted: nil, basesAwarded: 1)), .error)
        XCTAssertEqual(ScoringCategory(.sacrificeFly(fielder: .centerField)), .sacrificeFly)
    }

    func testMLBEventTypesMapToCategories() {
        XCTAssertEqual(ScoringCategory(mlbEventType: "single"), .single)
        XCTAssertEqual(ScoringCategory(mlbEventType: "home_run"), .homeRun)
        XCTAssertEqual(ScoringCategory(mlbEventType: "walk"), .walk)
        XCTAssertEqual(ScoringCategory(mlbEventType: "field_out"), .fieldOut)
        XCTAssertEqual(ScoringCategory(mlbEventType: "field_error"), .error)
        XCTAssertEqual(ScoringCategory(mlbEventType: "sac_fly"), .sacrificeFly)
    }

    /// Their vocabulary is finer than a scorebook's. An intentional walk is
    /// still a walk, and a strikeout that doubled off a runner is still a
    /// strikeout for the batter.
    func testFinerOfficialDistinctionsCollapseToTheSameCategory() {
        XCTAssertEqual(ScoringCategory(mlbEventType: "intent_walk"), .walk)
        XCTAssertEqual(ScoringCategory(mlbEventType: "strikeout_double_play"), .strikeout)
        XCTAssertEqual(ScoringCategory(mlbEventType: "grounded_into_double_play"), .doublePlay)
        XCTAssertEqual(ScoringCategory(mlbEventType: "force_out"), .fieldersChoice)
        XCTAssertEqual(ScoringCategory(mlbEventType: "sac_fly_double_play"), .sacrificeFly)
    }

    func testUnknownEventsFallBackRatherThanCrash() {
        XCTAssertEqual(ScoringCategory(mlbEventType: "cosmic_ray_interference"), .other)
        XCTAssertEqual(ScoringCategory(mlbEventType: ""), .other)
    }
}

final class ScoringComparatorTests: XCTestCase {

    private func official(
        index: Int,
        inning: Int,
        half: Half,
        eventType: String,
        rbi: Int = 0,
        batter: String = "Someone"
    ) -> OfficialPlay {
        OfficialPlay(
            index: index,
            inning: inning,
            half: half,
            batterExternalID: nil,
            batterName: batter,
            eventType: eventType,
            eventName: eventType,
            summary: "\(batter) \(eventType)",
            rbi: rbi
        )
    }

    func testIdenticalScoringIsPerfect() {
        var driver = GameDriver()
        driver.single()
        driver.strikeout()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        let theirs = [
            official(index: 0, inning: 1, half: .top, eventType: "single"),
            official(index: 1, inning: 1, half: .top, eventType: "strikeout")
        ]

        let report = ScoringComparator.compare(mine: mine, official: theirs, document: driver.document)

        XCTAssertEqual(report.comparedPlays, 2)
        XCTAssertEqual(report.agreements, 2)
        XCTAssertTrue(report.differences.isEmpty)
        XCTAssertEqual(report.accuracyPercent, "100%")
        XCTAssertTrue(report.isAligned)
    }

    /// The case this feature exists for: you called it a hit, the official
    /// scorer called it an error.
    func testHitScoredAsAnErrorIsFlagged() {
        var driver = GameDriver()
        driver.single()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        let theirs = [official(index: 0, inning: 1, half: .top, eventType: "field_error")]

        let report = ScoringComparator.compare(mine: mine, official: theirs, document: driver.document)

        XCTAssertEqual(report.agreements, 0)
        XCTAssertEqual(report.differences.count, 1)

        guard case .differentCall(let mineCall, let officialCall) = report.differences[0].kind else {
            return XCTFail("expected a differing call")
        }
        XCTAssertEqual(mineCall, .single)
        XCTAssertEqual(officialCall, .error)
    }

    func testRBIDisagreementIsFlaggedSeparately() {
        var driver = GameDriver()
        driver.walk()
        driver.single()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        let theirs = [
            official(index: 0, inning: 1, half: .top, eventType: "walk"),
            official(index: 1, inning: 1, half: .top, eventType: "single", rbi: 1)
        ]

        let report = ScoringComparator.compare(mine: mine, official: theirs, document: driver.document)

        XCTAssertEqual(report.differences.count, 1)
        guard case .differentRBI(let mineRBI, let officialRBI) = report.differences[0].kind else {
            return XCTFail("expected an RBI difference")
        }
        XCTAssertEqual(mineRBI, 0, "a single with a man on first drives in nobody")
        XCTAssertEqual(officialRBI, 1)
    }

    func testAPlayTheScorerMissedIsReported() {
        var driver = GameDriver()
        driver.single()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        let theirs = [
            official(index: 0, inning: 1, half: .top, eventType: "single"),
            official(index: 1, inning: 1, half: .top, eventType: "double")
        ]

        let report = ScoringComparator.compare(mine: mine, official: theirs, document: driver.document)

        XCTAssertEqual(report.comparedPlays, 1)
        XCTAssertEqual(report.agreements, 1)
        XCTAssertEqual(report.differences.count, 1)
        XCTAssertFalse(report.isAligned)

        guard case .missed(let category) = report.differences[0].kind else {
            return XCTFail("expected a missed play")
        }
        XCTAssertEqual(category, .double)
    }

    func testAPlayTheScorerInventedIsReported() {
        var driver = GameDriver()
        driver.single()
        driver.homeRun()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        let theirs = [official(index: 0, inning: 1, half: .top, eventType: "single")]

        let report = ScoringComparator.compare(mine: mine, official: theirs, document: driver.document)

        XCTAssertEqual(report.differences.count, 1)
        guard case .extra(let category) = report.differences[0].kind else {
            return XCTFail("expected an extra play")
        }
        XCTAssertEqual(category, .homeRun)
    }

    /// Plays line up within a half-inning, so a mistake in the first doesn't
    /// cascade into every inning after it.
    func testMisalignmentIsContainedToItsHalfInning() {
        var driver = GameDriver()
        driver.single()       // top 1
        driver.retireSide()   // three strikeouts finish the top
        driver.retireSide()   // and the bottom
        driver.homeRun()      // top 2

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        var theirs: [OfficialPlay] = [
            official(index: 0, inning: 1, half: .top, eventType: "single"),
            official(index: 1, inning: 1, half: .top, eventType: "strikeout"),
            official(index: 2, inning: 1, half: .top, eventType: "strikeout"),
            official(index: 3, inning: 1, half: .top, eventType: "strikeout"),
            // Their bottom-first is a play short of ours.
            official(index: 4, inning: 1, half: .bottom, eventType: "strikeout"),
            official(index: 5, inning: 1, half: .bottom, eventType: "strikeout")
        ]
        // A solo homer drives in a run, so it must carry the RBI the scorer's
        // own home run does — otherwise the match fails on the RBI, not the
        // alignment this test is about.
        theirs.append(official(index: 6, inning: 2, half: .top, eventType: "home_run", rbi: 1))

        let report = ScoringComparator.compare(mine: mine, official: theirs, document: driver.document)

        // The top of the second still matches despite the hole in the first.
        let secondInningDifferences = report.differences.filter { $0.inning == 2 }
        XCTAssertTrue(secondInningDifferences.isEmpty, "a gap in the first must not cascade")

        let firstInningDifferences = report.differences.filter { $0.inning == 1 }
        XCTAssertEqual(firstInningDifferences.count, 1)
    }

    func testEmptyOfficialScoringReportsNothingCompared() {
        var driver = GameDriver()
        driver.single()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        let report = ScoringComparator.compare(mine: mine, official: [], document: driver.document)

        XCTAssertEqual(report.comparedPlays, 0)
        XCTAssertEqual(report.accuracyPercent, "—")
        XCTAssertEqual(report.differences.count, 1, "the one play we have is surplus")
    }

    func testPlateAppearancesComeBackInOrder() {
        var driver = GameDriver()
        driver.single()
        driver.strikeout()
        driver.homeRun()

        let mine = ScoringEngine.plateAppearances(document: driver.document)
        XCTAssertEqual(mine.count, 3)
        XCTAssertEqual(ScoringCategory(mine[0].outcome), .single)
        XCTAssertEqual(ScoringCategory(mine[1].outcome), .strikeout)
        XCTAssertEqual(ScoringCategory(mine[2].outcome), .homeRun)
    }
}
