import XCTest
@testable import PocketMind

final class NativeIntegrationTests: XCTestCase {
    private var projectRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    func testRealGGUFInferenceAndCancellation() async throws {
        let url = projectRoot.appendingPathComponent("Vendor/smoke-model.gguf")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Run scripts/fetch-test-assets.sh to enable real inference tests.") }
        let inference = InferenceService()
        inference.prepare()
        let output = try await inference.generate(model: url, messages: [.init(role: "system", content: "Answer briefly."), .init(role: "user", content: "What is two plus two? Answer with the number.")], maxTokens: 48) { _ in }
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("4") || output.lowercased().contains("four"), "Real model output: \(output)")
        inference.prepare()
        inference.cancel()
        do {
            _ = try await inference.generate(model: url, messages: [.init(role: "user", content: "Write a long story.")], maxTokens: 300) { _ in }
            XCTFail("Cancelled generation should fail")
        } catch { XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("stop")) }
        inference.unload()
    }

    func testOfflineWikipediaSearchReturnsRealArticleText() throws {
        let url = projectRoot.appendingPathComponent("Vendor/smoke-wikipedia.zim")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Run scripts/fetch-test-assets.sh to enable archive tests.") }
        let archive = try PMArchive(path: url.path)
        XCTAssertGreaterThan(archive.articleCount, 100)
        let results = try archive.search("bowline", limit: 3)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { ($0["title"] ?? "").localizedCaseInsensitiveContains("bowline") })
        let body = try KnowledgeService.plainText(try XCTUnwrap(results.first?["html"]))
        XCTAssertTrue(body.lowercased().contains("knot"))
        XCTAssertFalse(body.contains("<script"))
    }

    func testModelMetadataAndWikipediaCatalog() async throws {
        guard ProcessInfo.processInfo.environment["POCKETMIND_NETWORK_TESTS"] == "1" else { throw XCTSkip("Set POCKETMIND_NETWORK_TESTS=1 to test upstream services.") }
        let hub = ModelHub()
        let (files, _) = try await hub.files(in: "LiquidAI/LFM2.5-230M-GGUF")
        XCTAssertTrue(files.contains { $0.path == "LFM2.5-230M-Q4_K_M.gguf" && $0.bytes > 100_000_000 && $0.sha256?.count == 64 })
        let packs = try await WikipediaCatalog.fetch()
        XCTAssertTrue(packs.contains { $0.name == "English Wikipedia" && !$0.isMini })
        let pack = try XCTUnwrap(packs.first)
        let job = try await WikipediaCatalog.downloadJob(for: pack)
        XCTAssertEqual(job.sha256?.count, 64)
        XCTAssertGreaterThan(job.expectedBytes, 0)
    }
}
