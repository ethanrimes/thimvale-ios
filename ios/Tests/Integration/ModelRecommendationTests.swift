import XCTest
@testable import Thimvale

final class ModelRecommendationTests: XCTestCase {
    func testBundledSnapshotReferencesAvailableModels() throws {
        let snapshot = try XCTUnwrap(ModelRecommendations.current)
        XCTAssertEqual(snapshot.reviewedOn, "2026-09-27")
        XCTAssertEqual(Set(snapshot.picks.map(\.id)).count, snapshot.picks.count)
        XCTAssertEqual(snapshot.picks.count, 6)
        for pick in snapshot.picks {
            XCTAssertTrue(ModelCatalog.models.contains { $0.id == pick.modelID }, pick.modelID)
            XCTAssertTrue((0...100).contains(pick.score))
            XCTAssertGreaterThan(pick.tokensPerSecond, 0)
            XCTAssertEqual(pick.modelSourceURL.scheme, "https")
        }
    }
    func testDefaultFitsInstalledMemoryAndDoesNotRequireCatalogOrder() throws {
        let snapshot = try XCTUnwrap(ModelRecommendations.current)
        let models = Array(ModelCatalog.models.reversed())
        XCTAssertEqual(snapshot.defaultPick(memoryBytes: 8 * 1_073_741_824, models: models)?.id, "balanced")
        XCTAssertEqual(snapshot.defaultPick(memoryBytes: 4 * 1_073_741_824, models: models)?.id, "quick")
        XCTAssertNil(snapshot.defaultPick(memoryBytes: 2 * 1_073_741_824, models: models))
        XCTAssertNil(snapshot.defaultPick(memoryBytes: 8 * 1_073_741_824, models: []))
        let withoutDefault = models.filter { $0.id != "liquid25-26" }
        XCTAssertEqual(snapshot.defaultPick(memoryBytes: 8 * 1_073_741_824, models: withoutDefault)?.id, "quick")
    }
}
