import XCTest
@testable import Thimvale

private actor UpdateCatalogFixture {
    var calls = 0
    var fails = false
    let packs: [WikiPack]
    init(_ packs: [WikiPack]) { self.packs = packs }
    func setFailure() { fails = true }
    func fetch() throws -> [WikiPack] {
        calls += 1
        if fails { throw URLError(.notConnectedToInternet) }
        return packs
    }
}

@MainActor final class WikipediaUpdateTests: XCTestCase {
    private func pack(_ filename: String) -> WikiPack {
        .init(id: StableID.hash(filename), name: "English Wikipedia", summary: "Fixture metadata", edition: "nopic", date: "2026-08-01", bytes: 100,
              url: URL(string: "https://download.kiwix.org/zim/wikipedia/")!.appendingPathComponent(filename))
    }
    func testUpdateMatchingPreservesTopicEditionAndNewestInstalledVersion() async {
        let old = "wikipedia_en_all_nopic_2026-07.zim"
        let next = "wikipedia_en_all_nopic_2026-08.zim"
        let packs = [pack(next), pack("wikipedia_en_all_mini_2026-09.zim"), pack("wikipedia_en_medicine_nopic_2026-09.zim"), pack("wikipedia_en_all_nopic_2026-06.zim")]
        let center = WikipediaUpdates(persistCache: false, fetch: { packs })
        center.setInstalled([old, "personal.zim"])
        await center.checkNow()
        XCTAssertEqual(center.available.map { $0.pack.filename }, [next])
        center.setInstalled([old, next])
        XCTAssertTrue(center.available.isEmpty)
        XCTAssertEqual(WikipediaEdition.preferredFiles([old, next, "personal.zim"]), ["personal.zim", next])
        XCTAssertNil(WikipediaEdition.parse("../" + old))
        XCTAssertNil(WikipediaEdition.parse("wikipedia_en_all_nopic_2026-13.zim"))
        XCTAssertNil(WikipediaEdition.parse("renamed-wikipedia.zim"))
        XCTAssertNotNil(WikipediaEdition.parse("wikipedia_en_knots_maxi_2026-07.zim"))
    }
    func testReconnectChecksMetadataOnceAndManualRetryStillWorks() async throws {
        let remote = UpdateCatalogFixture([pack("wikipedia_en_all_nopic_2026-08.zim")])
        let center = WikipediaUpdates(persistCache: false, fetch: { try await remote.fetch() })
        center.setInstalled(["wikipedia_en_all_nopic_2026-07.zim"])
        center.setForeground(true, monitorNetwork: false)
        center.networkChanged(online: false)
        XCTAssertNil(center.lastChecked)
        center.networkChanged(online: true)
        let deadline = Date().addingTimeInterval(2)
        while center.lastChecked == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(center.lastChecked)
        XCTAssertEqual(center.available.count, 1)
        center.networkChanged(online: false); center.networkChanged(online: true)
        await Task.yield()
        let automaticCalls = await remote.calls
        XCTAssertEqual(automaticCalls, 1, "Brief network flaps must not spam the catalog")
        await center.checkNow()
        let manualCalls = await remote.calls
        XCTAssertEqual(manualCalls, 2)
    }
    func testNoBackgroundCheckAndNetworkFailurePreservesCachedUpdates() async throws {
        let remote = UpdateCatalogFixture([pack("wikipedia_en_all_nopic_2026-08.zim")])
        let center = WikipediaUpdates(persistCache: false, fetch: { try await remote.fetch() })
        center.setInstalled(["wikipedia_en_all_nopic_2026-07.zim"])
        center.networkChanged(online: true)
        await Task.yield()
        let backgroundCalls = await remote.calls
        XCTAssertEqual(backgroundCalls, 0)
        await center.checkNow()
        let checked = center.lastChecked
        await remote.setFailure()
        await center.checkNow()
        XCTAssertNotNil(center.error)
        XCTAssertEqual(center.available.count, 1)
        XCTAssertEqual(center.lastChecked, checked)
    }
    func testUnknownImportedFilenameDoesNotRequestCatalog() async {
        let remote = UpdateCatalogFixture([])
        let center = WikipediaUpdates(persistCache: false, fetch: { try await remote.fetch() })
        center.setInstalled(["my-archive.zim"])
        await center.checkNow()
        let calls = await remote.calls
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(ReviewPrompter.isStoreBuild, "Development/test installations must not solicit public reviews")
    }
}
