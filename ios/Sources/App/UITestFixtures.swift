#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit

extension AppState {
    /// Real local artifacts, imported through production services into an isolated test session.
    /// This entry point is absent from device and Release builds.
    func prepareUITestFixtures() async throws {
        guard AppPaths.testSession != nil else { return }
        if let path = ProcessInfo.processInfo.environment["THIMVALE_UI_VISION_FIXTURES"] {
            let source = URL(fileURLWithPath: path)
            await importModel(source.appendingPathComponent("Vendor/vision-model.gguf"))
            if let error { throw PocketError.message(error) }
            guard let model = selectedModel else { throw PocketError.message("Vision test model is missing.") }
            await importProjector(source.appendingPathComponent("Vendor/vision-projector.gguf"), model: model)
            if let error { throw PocketError.message(error) }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).jpegData(withCompressionQuality: 0.9) { context in
                UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            }
            let url = AppPaths.exports.appendingPathComponent("Picture.jpg")
            try photo.write(to: url, options: .atomic)
            await addChatAttachments([url])
            if let error { throw PocketError.message(error) }
            return
        }
        if ProcessInfo.processInfo.environment["THIMVALE_UI_ATTACHMENT_FILES"] == "1" {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fixtureFolder = documents.appendingPathComponent("Chat attachment samples", isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureFolder, withIntermediateDirectories: true)
            try Data("The observatory opens at 21:30. The entry code is 4829.".utf8).write(to: fixtureFolder.appendingPathComponent("Arrival.txt"), options: .atomic)
            try Data("Bring a red flashlight. Meet at the east gate.".utf8).write(to: fixtureFolder.appendingPathComponent("Packing.txt"), options: .atomic)
        }
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
        let localFile = AppPaths.exports.appendingPathComponent("Field notes.md")
        if !FileManager.default.fileExists(atPath: localFile.path) {
            try FileManager.default.copyItem(at: source.appendingPathComponent("Tests/Fixtures/Field notes.md"), to: localFile)
        }
        _ = try await knowledge.importURL(localFile) { _ in }
        await refreshKnowledge()
        try Data().write(to: marker, options: .atomic)
    }
}
#endif
