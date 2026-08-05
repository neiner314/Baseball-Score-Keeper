import XCTest
@testable import BaseballScoreKeeper

/// There used to be three layouts and now there are two. A game saved by the
/// old build carries a raw value that no longer exists, and an enum decode of
/// an unknown raw value throws — which would take the whole saved game down
/// with it, not just the one setting.
final class LayoutMigrationTests: XCTestCase {

    private func decodeSettings(_ json: String) throws -> TrackingSettings {
        try JSONDecoder().decode(TrackingSettings.self, from: Data(json.utf8))
    }

    func testRetiredPitchFirstBecomesOneHanded() throws {
        let settings = try decodeSettings(#"{"preferredLayout":"pitchFirst"}"#)
        XCTAssertEqual(settings.preferredLayout, .oneHanded)
    }

    func testRetiredThumbClusterBecomesOneHanded() throws {
        let settings = try decodeSettings(#"{"preferredLayout":"thumbCluster"}"#)
        XCTAssertEqual(settings.preferredLayout, .oneHanded)
    }

    func testRetiredSingleSheetBecomesFullSheet() throws {
        let settings = try decodeSettings(#"{"preferredLayout":"singleSheet"}"#)
        XCTAssertEqual(settings.preferredLayout, .fullSheet)
    }

    func testCurrentValuesRoundTrip() throws {
        for layout in ScoringLayout.allCases {
            var settings = TrackingSettings()
            settings.preferredLayout = layout
            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(TrackingSettings.self, from: data)
            XCTAssertEqual(decoded.preferredLayout, layout)
        }
    }

    /// The point of the exercise: an unreadable layout must not cost the game.
    func testUnknownLayoutDoesNotFailTheWholeDecode() throws {
        let settings = try decodeSettings(
            #"{"preferredLayout":"someLayoutFromTheFuture","trackPitchVelocity":false,"handedness":"left"}"#
        )
        XCTAssertEqual(settings.preferredLayout, .oneHanded)
        XCTAssertFalse(settings.trackPitchVelocity, "the rest of the settings still decode")
        XCTAssertEqual(settings.handedness, .left)
    }

    func testMissingLayoutFallsBackToTheDefault() throws {
        let settings = try decodeSettings(#"{"trackPitchType":false}"#)
        XCTAssertEqual(settings.preferredLayout, .oneHanded)
        XCTAssertFalse(settings.trackPitchType)
    }

    func testThereAreExactlyTwoLayouts() {
        XCTAssertEqual(ScoringLayout.allCases.count, 2)
    }
}
