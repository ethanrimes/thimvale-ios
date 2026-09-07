#if DEBUG && targetEnvironment(simulator)
import Foundation

extension AppState {
    /// Real local artifacts, imported through production services into an isolated test session.
    /// This entry point is absent from device and Release builds.
    func prepareUITestFixtures() async throws {
        guard AppPaths.testSession != nil else { return }
        // A presentation-only fixture, separate from the real inference tests.
        if ProcessInfo.processInfo.environment["THIMVALE_UI_ACTIVITY_FIXTURE"] == "1" {
            let event = AgentEvent(kind: .tool, title: "Search knowledge", state: .completed,
                                   text: "Presentation fixture: a bowline forms a fixed loop.",
                                   call: ToolCall(tool: .searchKnowledge, query: "bowline"), finishedAt: Date())
            var messages = [ChatMessage(role: "user", content: "Show the source for a bowline."),
                            ChatMessage(role: "assistant", content: "A bowline forms a fixed loop.", events: [event])]
            for index in 1...16 {
                messages.append(ChatMessage(role: "assistant", content: "Layout fixture \(index). " + String(repeating: "This is a saved conversation paragraph. ", count: 5)))
            }
            let conversation = Conversation(title: "Activity layout test", mode: .work, messages: messages)
            conversations = [conversation]; conversationID = conversation.id
            return
        }
        guard let path = ProcessInfo.processInfo.environment["THIMVALE_UI_FIXTURES"] else { return }
        let marker = AppPaths.root.appendingPathComponent("fixtures-ready")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let source = URL(fileURLWithPath: path, isDirectory: true)
        if ProcessInfo.processInfo.environment["THIMVALE_UI_WIKI_ONLY"] != "1" {
            await importModel(source.appendingPathComponent("Vendor/smoke-model.gguf"))
            if let error { throw PocketError.message(error) }
        }
        await importArchive(source.appendingPathComponent("Vendor/smoke-wikipedia.zim"))
        if let error { throw PocketError.message(error) }
        _ = try await knowledge.importURL(source.appendingPathComponent("Tests/Fixtures/Field notes.md")) { _ in }
        await refreshKnowledge()
        try Data().write(to: marker, options: .atomic)
    }
}
#endif
