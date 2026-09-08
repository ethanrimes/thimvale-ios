import XCTest
@testable import Thimvale

/// Deliberately scripted test double for deterministic streaming/permission timing.
/// Production and the real-model suite always use PMInference.
final class ScriptedInference: InferenceServing, @unchecked Sendable {
    private let lock = NSLock()
    private var resident: URL?
    private var loadCount = 0
    private var generationCount = 0
    private var cancellation = 0
    private var prompts: [[ChatMessage]] = []
    private var imagesReceived: [Int] = []
    let scripts: [[String]]
    let loadDelay: Duration
    let tokenDelay: Duration
    init(_ scripts: [[String]] = [["Hello", " there."]], loadDelay: Duration = .milliseconds(10), tokenDelay: Duration = .milliseconds(80)) {
        self.scripts = scripts; self.loadDelay = loadDelay; self.tokenDelay = tokenDelay
    }
    var snapshot: (model: URL?, loads: Int, generations: Int) { lock.withLock { (resident, loadCount, generationCount) } }
    var receivedPrompts: [[ChatMessage]] { lock.withLock { prompts } }
    var receivedImageCounts: [Int] { lock.withLock { imagesReceived } }
    func generate(model: URL, messages: [ChatMessage], images: [Data], projector: URL?, maxTokens: Int, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        lock.withLock { imagesReceived.append(images.count) }
        return try await generate(model: model, messages: messages, maxTokens: maxTokens, onToken: onToken)
    }
    func load(model: URL) async throws {
        try await Task.sleep(for: loadDelay)
        try Task.checkCancellation()
        if model.lastPathComponent == "broken.gguf" { throw PocketError.message("Test model is incompatible.") }
        lock.withLock { if resident != model { resident = model; loadCount += 1 } }
    }
    func generate(model: URL, messages: [ChatMessage], maxTokens: Int, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        let (script, ticket) = lock.withLock {
            prompts.append(messages)
            let script = scripts[min(generationCount, scripts.count - 1)]
            generationCount += 1
            return (script, cancellation)
        }
        var output = ""
        for token in script {
            try await Task.sleep(for: tokenDelay)
            guard lock.withLock({ cancellation == ticket }) else { throw CancellationError() }
            output += token; onToken(token)
        }
        return output
    }
    func cancel() { lock.withLock { cancellation += 1 } }
    func unload() { lock.withLock { cancellation += 1; resident = nil } }
}

@MainActor final class SessionAndStreamingTests: XCTestCase {
    private let modelURL = URL(fileURLWithPath: "/test/selected.gguf")
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for state transition")
        throw PocketError.message("Test timed out")
    }
    private func makeState(_ inference: ScriptedInference) throws -> AppState {
        let state = try AppState(inference: inference)
        state.activate()
        let conversation = Conversation()
        state.conversations = [conversation]; state.conversationID = conversation.id
        state.models = [.init(id: "scripted-test", name: "Scripted test model", family: "Test", repository: "", summary: "Test only", parameters: "Test", minimumMemoryGB: 0, localFilename: "scripted-test.gguf")]
        state.selectModel(state.models[0])
        state.documents = []; state.archiveFiles = []; state.policy[.searchKnowledge] = .deny
        return state
    }
    func testPreloadReuseIdleReleaseAndAutomaticReload() async throws {
        let inference = ScriptedInference()
        let session = ModelSession(inference: inference, idleTimeout: .milliseconds(120))
        session.select(modelURL)
        XCTAssertEqual(session.state, .loading)
        try await session.ensureReady()
        XCTAssertEqual(inference.snapshot.loads, 1)
        session.select(modelURL)
        try await session.ensureReady()
        XCTAssertEqual(inference.snapshot.loads, 1)
        session.beginUse()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(session.state, .ready, "Never unload during a turn, including tool approval")
        session.endUse()
        try await waitUntil { session.state == .unloaded }
        XCTAssertNil(inference.snapshot.model)
        session.beginUse()
        try await session.ensureReady()
        XCTAssertEqual(inference.snapshot.loads, 2)
        session.endUse(); session.release()
    }
    func testBackgroundReleaseDoesNotReloadOnForegroundUntilNeeded() async throws {
        let inference = ScriptedInference()
        let session = ModelSession(inference: inference)
        session.select(modelURL); try await session.ensureReady()
        session.suspend()
        XCTAssertEqual(session.state, .unloaded)
        XCTAssertNil(inference.snapshot.model)
        do { try await session.ensureReady(); XCTFail("Must not load in background") } catch {}
        session.activate()
        XCTAssertEqual(inference.snapshot.loads, 1)
        try await session.ensureReady()
        XCTAssertEqual(inference.snapshot.loads, 2)
        session.release()
    }
    func testDeletingAnotherDownloadDoesNotUnloadSelectedWeights() async throws {
        let inference = ScriptedInference()
        let state = try makeState(inference)
        defer { state.suspend() }
        try await state.modelSession.ensureReady()
        let filename = "unselected-test-" + UUID().uuidString + ".gguf"
        let file = AppPaths.models.appendingPathComponent(filename)
        try Data("GGUF".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let other = ModelEntry(id: filename, name: "Other test download", family: "Test", repository: "", summary: "Test only", parameters: "Test", minimumMemoryGB: 0, localFilename: filename)
        state.models.append(other)
        state.removeModel(other)
        XCTAssertEqual(state.modelSession.state, .ready)
        XCTAssertEqual(inference.snapshot.loads, 1)
        XCTAssertNotNil(inference.snapshot.model)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        state.releaseForMemoryPressure()
        XCTAssertNil(inference.snapshot.model)
        XCTAssertTrue(state.modelSession.isForeground)
        XCTAssertTrue(state.send("After a memory warning"))
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(inference.snapshot.loads, 2)
    }
    func testRapidSelectionCancellationAndFailedLoadCanRecover() async throws {
        let inference = ScriptedInference(loadDelay: .milliseconds(100))
        let session = ModelSession(inference: inference)
        session.select(modelURL)
        let replacement = URL(fileURLWithPath: "/test/replacement.gguf")
        session.select(replacement)
        try await session.ensureReady()
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(inference.snapshot.model, replacement)
        XCTAssertEqual(inference.snapshot.loads, 1)
        session.select(URL(fileURLWithPath: "/test/broken.gguf"))
        do { try await session.ensureReady(); XCTFail("Broken model loaded") } catch {}
        guard case .failed = session.state else { return XCTFail("Load error was not visible") }
        XCTAssertNil(inference.snapshot.model)
        session.select(modelURL); try await session.ensureReady()
        session.release()
        session.select(replacement); session.suspend()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(session.state, .unloaded)
        XCTAssertNil(inference.snapshot.model, "Late preload must not resurrect released weights")
    }
    func testChatStreamsBeforeCompletionAndKeepsWeightsForNewConversation() async throws {
        let inference = ScriptedInference([["First ", "visible ", "answer."]])
        let state = try makeState(inference)
        defer { state.suspend() }
        XCTAssertTrue(state.send("Hello"))
        try await waitUntil { state.current.messages.last?.events?.last?.text == "First " }
        XCTAssertTrue(state.isGenerating)
        XCTAssertEqual(state.current.messages.last?.events?.last?.state, .running)
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(state.current.messages.last?.content, "First visible answer.")
        XCTAssertEqual(state.current.messages.last?.events?.last?.text, "First visible answer.")
        XCTAssertEqual(inference.snapshot.loads, 1)
        state.newConversation()
        XCTAssertTrue(state.send("Hello again"))
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(inference.snapshot.loads, 1)
        state.suspend(); state.activate()
        XCTAssertTrue(state.send("After reopening"))
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(inference.snapshot.loads, 2)
    }
    func testWorkStreamsToolJSONApprovalResultAndFinalAnswerInOrder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try SecureWorkspace.create(root: folder, path: "note.txt", content: "A bowline forms a fixed loop.")
        let inference = ScriptedInference([
            ["{\"tool\":\"read_file\",", "\"folder\":\"test\",", "\"path\":\"note.txt\"}"],
            ["A bowline ", "forms a fixed loop ", "[1]."]
        ])
        let state = try makeState(inference)
        defer { state.suspend() }
        state.folders = [.init(id: "test", name: "Test", bookmark: try folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil))]
        state.policy[.readFile] = .ask
        state.setMode(.work)
        XCTAssertTrue(state.send("Read note.txt"))
        try await waitUntil { state.current.messages.last?.events?.first?.text == "{\"tool\":\"read_file\"," }
        XCTAssertTrue(state.isGenerating)
        XCTAssertNil(state.approval, "Partial JSON must never execute")
        XCTAssertEqual(state.current.messages.last?.events?.count, 1)
        try await waitUntil { state.approval != nil }
        XCTAssertEqual(state.current.messages.last?.events?.last?.state, .awaitingApproval)
        XCTAssertEqual(state.current.messages.last?.events?.last?.call?.path, "note.txt")
        state.approve(true)
        try await waitUntil { state.current.messages.last?.events?.last?.text == "A bowline " }
        let events = try XCTUnwrap(state.current.messages.last?.events)
        XCTAssertEqual(events.map(\.kind), [.generation, .tool, .generation])
        XCTAssertEqual(events[1].state, .completed)
        XCTAssertTrue(events[1].text.contains("fixed loop"))
        XCTAssertTrue(state.isGenerating)
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(state.current.messages.last?.content, "A bowline forms a fixed loop [1].")
        XCTAssertEqual(state.current.messages.last?.citations.count, 1)
        XCTAssertEqual(inference.snapshot.loads, 1)
    }
    func testCancellationKeepsPartialOutputAndNoLateTokensReachNextTurn() async throws {
        let inference = ScriptedInference([["Partial ", "old ", "output."], ["New ", "answer."]])
        let state = try makeState(inference)
        defer { state.suspend() }
        XCTAssertTrue(state.send("First request"))
        try await waitUntil { state.current.messages.last?.events?.last?.text == "Partial " }
        state.stop()
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(state.current.messages.last?.content, "Partial")
        XCTAssertEqual(state.current.messages.last?.events?.last?.state, .cancelled)
        XCTAssertTrue(state.send("Second request"))
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(state.current.messages.last?.content, "New answer.")
        XCTAssertEqual(state.current.messages.last?.events?.last?.text, "New answer.")
    }

    func testFailedToolIsVisibleAndChatJSONCannotExecuteTools() async throws {
        let call = "{\"tool\":\"web_search\",\"query\":\"bowline\"}"
        let inference = ScriptedInference([[call], ["Web search is turned off."]])
        let state = try makeState(inference)
        defer { state.suspend() }
        state.policy[.webSearch] = .deny
        state.setMode(.work)
        XCTAssertTrue(state.send("Search for bowline"))
        try await waitUntil { !state.isGenerating }
        let tool = try XCTUnwrap(state.current.messages.last?.events?.first { $0.kind == .tool })
        XCTAssertEqual(tool.state, .failed)
        XCTAssertTrue(tool.text.contains("turned off"))
        XCTAssertNil(state.approval)

        let chat = try makeState(ScriptedInference([[call]]))
        defer { chat.suspend() }
        XCTAssertTrue(chat.send("Search for bowline"))
        try await waitUntil { !chat.isGenerating }
        XCTAssertFalse(chat.current.messages.last?.events?.contains { $0.kind == .tool } == true)
    }

    func testAnswerOnlyCitationRetryAlsoStreams() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try SecureWorkspace.create(root: folder, path: "note.txt", content: "A bowline forms a fixed loop.")
        let inference = ScriptedInference([
            ["{\"tool\":\"read_file\",\"folder\":\"test\",\"path\":\"note.txt\"}"],
            ["An uncited draft."], ["Cited ", "answer ", "[1]."]
        ])
        let state = try makeState(inference)
        defer { state.suspend() }
        state.folders = [.init(id: "test", name: "Test", bookmark: try folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil))]
        state.policy[.readFile] = .allow; state.setMode(.work)
        XCTAssertTrue(state.send("Read the note"))
        try await waitUntil { state.current.messages.last?.events?.last?.text == "Cited " }
        XCTAssertTrue(state.isGenerating)
        XCTAssertEqual(state.current.messages.last?.events?.last?.title, "Answering from sources")
        try await waitUntil { !state.isGenerating }
        XCTAssertEqual(state.current.messages.last?.content, "Cited answer [1].")
        XCTAssertEqual(state.current.messages.last?.events?.filter { $0.kind == .tool }.count, 1)
    }

    func testStopDuringApprovalNeverCreatesTheFile() async throws {
        let name = "stopped-" + UUID().uuidString + ".txt"
        let call = "{\"tool\":\"write_file\",\"folder\":\"exports\",\"path\":\"\(name)\",\"content\":\"Must not be written\"}"
        let state = try makeState(ScriptedInference([[call]]))
        defer { state.suspend() }
        state.folders = [.init(id: "exports", name: "Exports", isExports: true)]
        state.policy[.writeFile] = .ask; state.setMode(.work)
        XCTAssertTrue(state.send("Create a note"))
        try await waitUntil { state.approval != nil }
        XCTAssertEqual(state.current.messages.last?.events?.last?.state, .awaitingApproval)
        state.stop()
        try await waitUntil { !state.isGenerating }
        XCTAssertNil(state.approval)
        XCTAssertEqual(state.current.messages.last?.events?.last?.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: AppPaths.exports.appendingPathComponent(name).path))
    }

    func testCompletedWriteStaysVisibleWhenTheFollowingResponseIsStopped() async throws {
        let name = "completed-" + UUID().uuidString + ".txt"
        let file = AppPaths.exports.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: file) }
        let call = "{\"tool\":\"write_file\",\"folder\":\"exports\",\"path\":\"\(name)\",\"content\":\"Saved with permission\"}"
        let state = try makeState(ScriptedInference([[call], ["The file ", "was ", "saved."]]))
        defer { state.suspend() }
        state.folders = [.init(id: "exports", name: "Exports", isExports: true)]
        state.policy[.writeFile] = .allow; state.setMode(.work)
        XCTAssertTrue(state.send("Create a note"))
        try await waitUntil { state.current.messages.last?.events?.last?.text == "The file " }
        state.stop()
        try await waitUntil { !state.isGenerating }
        let tool = try XCTUnwrap(state.current.messages.last?.events?.first { $0.kind == .tool })
        XCTAssertEqual(tool.state, .completed)
        XCTAssertTrue(tool.text.contains("Created \(name)"))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Saved with permission")
    }
}
