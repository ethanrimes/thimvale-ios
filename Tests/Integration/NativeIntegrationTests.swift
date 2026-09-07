import XCTest
import UIKit
@testable import Thimvale

final class NativeIntegrationTests: XCTestCase {
    func testExpandedCatalogUsesDistinctModelsAndHonestMemoryLabels() throws {
        let models = ModelCatalog.models
        XCTAssertEqual(models.count, 39)
        XCTAssertEqual(Set(models.map(\.repository)).count, models.count)
        XCTAssertEqual(Set(ModelCatalog.families), Set(models.map(\.family)))
        XCTAssertEqual(ModelCatalog.families.count, Set(ModelCatalog.families).count)
        for id in ["liquid25-350", "liquid25-12-instruct", "liquid2-26-exp", "granite4-350", "minicpm5-1", "g9v3-3"] {
            let model = try XCTUnwrap(models.first { $0.id == id })
            XCTAssertFalse(model.needsHigherMemory)
            XCTAssertEqual(model.preferredQuant, "Q4_K_M")
        }
        let larger = models.filter(\.needsHigherMemory)
        XCTAssertEqual(Set(larger.map(\.id)), ["qwen35-9", "gemma4-e4", "liquid25-8-a1", "granite41-8", "ling3-tiny", "falcon-h1r-7", "ornith1-9"])
        XCTAssertTrue(larger.allSatisfy { !$0.isFourBillionClass })
        let nanbeige = try XCTUnwrap(models.first { $0.id == "nanbeige42-3" })
        XCTAssertEqual(nanbeige.parameters, "4.2B")
        XCTAssertTrue(nanbeige.isFourBillionClass)
        XCTAssertTrue(nanbeige.summary.contains("non-embedding"))
        XCTAssertTrue(models.first { $0.id == "ling3-tiny" }?.parameters.contains("7.9B") == true)
        XCTAssertTrue(models.first { $0.id == "liquid25-8-a1" }?.parameters.hasPrefix("8B") == true)
    }

    func testFourBillionCatalogEntriesHaveDistinctIDsAndMemoryGuidance() {
        let models = ModelCatalog.models
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        let fourB = models.filter { $0.parameters == "4B" }
        XCTAssertEqual(Set(fourB.map(\.id)), ["qwen35-4", "qwen3-4", "qwen3-4-instruct2507", "gemma3-4", "nemotron3-nano-4"])
        XCTAssertTrue(fourB.allSatisfy { $0.minimumMemoryGB >= 8 && $0.preferredQuant == "Q4_K_M" })
        XCTAssertTrue(models.first { $0.id == "phi4-mini" }?.isFourBillionClass == true)
    }

    func testInstalledAppNameAndUpdateIdentity() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, AppIdentity.displayName)
        XCTAssertEqual(Bundle.main.bundleIdentifier, AppIdentity.bundleIdentifier)
    }

    func testCompiledAppIconIsNotABlankSquare() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        let name = try XCTUnwrap((primary["CFBundleIconFiles"] as? [String])?.last)
        let image = try XCTUnwrap(UIImage(named: name)?.cgImage)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let brightness = stride(from: 0, to: pixels.count, by: 4).map { (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3 }
        XCTAssertGreaterThan(Set(brightness).count, 30)
        XCTAssertGreaterThan(brightness.filter { $0 > 150 }.count, 100, "The compiled icon must contain a visible foreground mark")
    }

    func testBuiltAppDeclaresOnlyExemptEncryption() throws {
        let value = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? NSNumber)
        XCTAssertEqual(CFGetTypeID(value), CFBooleanGetTypeID())
        XCTAssertFalse(value.boolValue)
    }

    func testBuiltAppSupportsAllIPadOrientations() throws {
        // Bundle's lookup resolves device-specific variants for this iPhone;
        // inspect the actual built plist to check the iPad declaration too.
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let orientations = try XCTUnwrap(info["UISupportedInterfaceOrientations~ipad"] as? [String])
        XCTAssertEqual(Set(orientations), Set([
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
        ]))
    }

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
        try await inference.load(model: url)
        let loaded = await inference.residency()
        XCTAssertEqual(loaded.path, url.path)
        XCTAssertEqual(loaded.loads, 1)
        let output = try await inference.generate(model: url, messages: [.init(role: "system", content: "Answer briefly."), .init(role: "user", content: "What is two plus two? Answer with the number.")], maxTokens: 48) { _ in }
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("4") || output.lowercased().contains("four"), "Real model output: \(output)")
        let reused = await inference.residency()
        XCTAssertEqual(reused.loads, 1, "Selection preload must be reused by generation")
        let cancelled = Task {
            _ = try await inference.generate(model: url, messages: [.init(role: "user", content: "Write a long story.")], maxTokens: 300) { _ in inference.cancel() }
        }
        do {
            try await cancelled.value
            XCTFail("Cancelled generation should fail")
        } catch { XCTAssertTrue(error is CancellationError || error.localizedDescription.localizedCaseInsensitiveContains("stop")) }
        let stillResident = await inference.residency()
        XCTAssertEqual(stillResident.loads, 1)
        XCTAssertEqual(stillResident.path, url.path)
        inference.unload()
        let released = await inference.residency()
        XCTAssertNil(released.path)
        try await inference.load(model: url)
        let reloaded = await inference.residency()
        XCTAssertEqual(reloaded.loads, 2)
        // A failed switch must not leave a stale cache entry for the old weights.
        do { try await inference.load(model: url.appendingPathExtension("missing")); XCTFail("Missing model loaded") } catch {}
        let failed = await inference.residency()
        XCTAssertNil(failed.path)
        try await inference.load(model: url)
        let recovered = await inference.residency()
        XCTAssertEqual(recovered.loads, 3)
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
        guard ProcessInfo.processInfo.environment["THIMVALE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Set THIMVALE_NETWORK_TESTS=1 to test upstream services.") }
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
        guard ProcessInfo.processInfo.environment["THIMVALE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Network tests are disabled.") }
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
