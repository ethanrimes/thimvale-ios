import XCTest
@testable import PocketMind

final class NativeIntegrationTests: XCTestCase {
    private var projectRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    @MainActor func testRejectedMessagesAreNotAcceptedOrAddedToHistory() throws {
        let state = try AppState()
        state.selectedModelID = nil
        let count = state.current.messages.count
        XCTAssertFalse(state.send(" \n "))
        XCTAssertFalse(state.send(String(repeating: "x", count: 8_001)))
        XCTAssertTrue(state.error?.contains("8,000") == true)
        state.error = nil
        XCTAssertFalse(state.send("Keep this draft until a model is selected."))
        XCTAssertEqual(state.selectedTab, 1)
        XCTAssertNotNil(state.notice)
        XCTAssertFalse(state.isGenerating)
        XCTAssertEqual(state.current.messages.count, count)
    }

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

    func testNaturalLanguageWikipediaQueryRetrievesTheNamedArticle() async throws {
        let source = projectRoot.appendingPathComponent("Vendor/smoke-wikipedia.zim")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("Fetch the test assets first.") }
        try AppPaths.prepare()
        let filename = "query-test-" + UUID().uuidString + ".zim"
        let destination = AppPaths.archives.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let knowledge = try KnowledgeService()
        let results = try await knowledge.search("What is a bowline? Answer briefly using the sources.", archiveFiles: [filename])
        let article = try XCTUnwrap(results.first { $0.title == "Bowline" })
        XCTAssertTrue(article.excerpt.lowercased().contains("loop"))
        XCTAssertTrue(article.sourceURL?.contains("/wiki/Bowline") == true)
        await knowledge.closeArchive(filename)
    }

    func testCitedAnswerFromOfflineWikipedia() async throws {
        let model = projectRoot.appendingPathComponent("Vendor/smoke-model.gguf")
        let zim = projectRoot.appendingPathComponent("Vendor/smoke-wikipedia.zim")
        guard FileManager.default.fileExists(atPath: model.path), FileManager.default.fileExists(atPath: zim.path) else { throw XCTSkip("Fetch the test assets first.") }
        let archive = try PMArchive(path: zim.path)
        let article = try XCTUnwrap(archive.search("bowline", limit: 3).first { ($0["title"] ?? "").lowercased() == "bowline" })
        let excerpt = String(try KnowledgeService.plainText(article["html"] ?? "").prefix(1600))
        let inference = InferenceService()
        inference.prepare()
        let answer = try await inference.generate(model: model, messages: [
            .init(role: "system", content: "Answer using only the provided source. Include its citation number in brackets after your answer, such as [1]."),
            .init(role: "user", content: "Source [1]:\n\(excerpt)\n\nWhat is a bowline knot? Answer briefly and cite the source with [1].")
        ], maxTokens: 120) { _ in }
        XCTAssertTrue(answer.lowercased().contains("loop"), "Answer: \(answer)")
        XCTAssertTrue(answer.contains("[1]"), "Answer: \(answer)")
        inference.unload()
    }

    @MainActor func testToolExecutorApprovalDenialAndRevocation() async throws {
        let state = try AppState()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bookmark = try folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        state.folders = [.init(id: "test", name: "Test folder", bookmark: bookmark)]
        state.policy[.writeFile] = .ask
        state.policy[.readFile] = .deny
        let call = ToolCall(tool: .writeFile, folder: "test", path: "approved.txt", content: "Only after approval")
        let writing = Task { try await state.execute(call, mode: .work) }
        try await waitForApproval(state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("approved.txt").path))
        XCTAssertEqual(state.approval?.call.content, "Only after approval")
        state.approve(true)
        _ = try await writing.value
        XCTAssertEqual(try SecureWorkspace.read(root: folder, path: "approved.txt"), "Only after approval")
        do { _ = try await state.execute(.init(tool: .readFile, folder: "test", path: "approved.txt"), mode: .work); XCTFail("Read permission is independent of write permission") } catch {}
        do { _ = try await state.execute(call, mode: .chat); XCTFail("Chat must never execute tools") } catch {}

        let deniedCall = ToolCall(tool: .writeFile, folder: "test", path: "denied.txt", content: "Must not be saved")
        let denied = Task { try await state.execute(deniedCall, mode: .work) }
        try await waitForApproval(state)
        state.approve(false)
        do { _ = try await denied.value; XCTFail("A declined action must fail") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("denied.txt").path))

        let revoked = Task { try await state.execute(deniedCall, mode: .work) }
        try await waitForApproval(state)
        state.policy[.writeFile] = .deny
        state.approve(true)
        do { _ = try await revoked.value; XCTFail("Permissions must be rechecked after approval") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("denied.txt").path))
    }

    @MainActor func testUnknownFolderDoesNotRequestApproval() async throws {
        let state = try AppState()
        state.policy[.readFile] = .ask
        do {
            _ = try await state.execute(.init(tool: .readFile, folder: "folder ID", path: "relative/file.txt"), mode: .work)
            XCTFail("An unconnected folder must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("not connected")) }
        XCTAssertNil(state.approval)
    }

    @MainActor private func waitForApproval(_ state: AppState) async throws {
        for _ in 0..<500 {
            if state.approval != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Approval was not presented")
        throw PocketError.message("Approval timed out")
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

    @MainActor func testModelDownloadAndValidationRecovery() async throws {
        guard ProcessInfo.processInfo.environment["POCKETMIND_NETWORK_TESTS"] == "1" else { throw XCTSkip("Network tests are disabled.") }
        try AppPaths.prepare()
        let id = "integration-" + UUID().uuidString
        let ledger = id + ".json"
        let center = DownloadCenter(identifier: "com.ethanrimes.pocketmind." + id, ledger: ledger)
        let ready = expectation(description: "Real model download verified")
        var received: DownloadJob?
        center.onReady = { job in received = job; ready.fulfill() }
        let job = DownloadJob(id: id, title: "Integration model", url: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/cdf97bd8205908758f44aec508d68ac1aef98f5c/LFM2.5-230M-Q4_K_M.gguf")!, kind: .model, filename: id + ".gguf", expectedBytes: 153406304, sha256: "7bbd90384d3deffe4c646ec9643b212802d32d4ce417c90a1ec9282100650062")
        defer {
            center.forget(id)
            try? FileManager.default.removeItem(at: job.destination)
            try? FileManager.default.removeItem(at: AppPaths.root.appendingPathComponent(ledger))
        }
        try center.start(job)
        await fulfillment(of: [ready], timeout: 120)
        XCTAssertEqual(received?.state, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.destination.path))

        // Simulate suspension after download but before validation was committed.
        let recoveryID = "recovery-" + UUID().uuidString
        let recoveryLedger = recoveryID + ".json"
        var recovery = job
        recovery.id = recoveryID; recovery.filename = recoveryID + ".gguf"; recovery.state = .validating
        recovery.url = URL(string: "https://example.invalid/must-not-download")!
        let staged = AppPaths.staging.appendingPathComponent(recoveryID + ".download")
        try FileManager.default.copyItem(at: job.destination, to: staged)
        try AppPaths.save([recovery], as: recoveryLedger)
        let recovered = expectation(description: "Completed file reused without network")
        let recoveryCenter = DownloadCenter(identifier: "com.ethanrimes.pocketmind." + recoveryID, ledger: recoveryLedger)
        recoveryCenter.onReady = { _ in recovered.fulfill() }
        await fulfillment(of: [recovered], timeout: 30)
        XCTAssertEqual(recoveryCenter.jobs.first?.state, .ready)
        recoveryCenter.forget(recoveryID)
        try? FileManager.default.removeItem(at: recovery.destination)
        try? FileManager.default.removeItem(at: AppPaths.root.appendingPathComponent(recoveryLedger))
    }
}
