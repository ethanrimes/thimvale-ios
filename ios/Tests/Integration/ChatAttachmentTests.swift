import XCTest
import UIKit
import PDFKit
@testable import Thimvale

final class ChatAttachmentTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func coloredImage(_ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).jpegData(withCompressionQuality: 0.9) { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
    }
    func testRealVisionReadsDifferentPixelsWithIdenticalPrompt() throws {
        let model = root.appendingPathComponent("Vendor/vision-model.gguf")
        let projector = root.appendingPathComponent("Vendor/vision-projector.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("Run scripts/fetch-vision-test-assets.sh") }
        let engine = PMInference(); defer { engine.unload() }
        try engine.loadModel(atPath: model.path, contextSize: 4096)
        try engine.loadVision(atPath: projector.path)
        let messages = [["role": "user", "content": "What color is this image? Answer with the color only."]]
        for (color, word) in [(UIColor.red, "red"), (UIColor.blue, "blue")] {
            var streamed = ""
            let output = try engine.generateMessages(messages, images: [coloredImage(color)], maxTokens: 24, temperature: 0) { streamed += $0 }
            XCTAssertEqual(streamed, output)
            XCTAssertTrue(output.lowercased().contains(word), "Actual vision output: \(output)")
            XCTAssertEqual(engine.generationStatistics["images"]?.intValue, 1)
            XCTAssertEqual(engine.generationStatistics["reusedTokens"]?.intValue, 0)
        }
        XCTAssertThrowsError(try engine.generateMessages(messages, images: [coloredImage(.red)], maxTokens: 24, temperature: 0) { _ in engine.cancel() })
        engine.resetCancellation()
        // Image embeddings must never masquerade as a cached text prefix.
        let text = try engine.generateMessages([["role": "user", "content": "Say hello."]], maxTokens: 12, temperature: 0) { _ in }
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(engine.generationStatistics["reusedTokens"]?.intValue, 0)
        XCTAssertThrowsError(try engine.generateMessages(messages, images: [Data([1, 2, 3])], maxTokens: 12, temperature: 0) { _ in })
        XCTAssertThrowsError(try engine.loadVision(atPath: model.path), "The text weights are not a matching vision file")
        XCTAssertFalse(try engine.generateMessages([["role": "user", "content": "Say hello."]], maxTokens: 12, temperature: 0) { _ in }.isEmpty)
        try engine.loadVision(atPath: projector.path)
        XCTAssertThrowsError(try engine.generateMessages([["role": "user", "content": String(repeating: "very long prompt ", count: 4_000)]], images: [coloredImage(.red)], maxTokens: 12, temperature: 0) { _ in })
        XCTAssertThrowsError(try engine.generateMessages(messages, images: [Data(repeating: 0, count: 1_500_001)], maxTokens: 12, temperature: 0) { _ in })
        engine.unload()
        XCTAssertThrowsError(try engine.loadVision(atPath: projector.path))
    }

    func testQwen35VisionMROPEAndHybridState() throws {
        let model = root.appendingPathComponent("Vendor/vision-qwen.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("Optional: fetch-vision-test-assets.sh --qwen") }
        let engine = PMInference(); defer { engine.unload() }
        try engine.loadModel(atPath: model.path, contextSize: 4096)
        try engine.loadVision(atPath: root.appendingPathComponent("Vendor/vision-qwen-projector.gguf").path)
        for (color, word) in [(UIColor.red, "red"), (UIColor.blue, "blue")] {
            let output = try engine.generateMessages([["role": "user", "content": "What color fills this picture? Answer with the color only."]], images: [coloredImage(color)], maxTokens: 48, temperature: 0) { _ in }
            XCTAssertTrue(output.lowercased().contains(word), "Qwen image output: \(output)")
            XCTAssertEqual(engine.generationStatistics["reusedTokens"]?.intValue, 0)
        }
        XCTAssertThrowsError(try engine.generateMessages([["role": "user", "content": "Describe the picture in detail."]], images: [coloredImage(.red)], maxTokens: 48, temperature: 0) { _ in engine.cancel() })
        engine.resetCancellation()
        let output = try engine.generateMessages([["role": "user", "content": "What is 2 + 2? Answer with the number only."]], maxTokens: 24, temperature: 0) { _ in }
        XCTAssertTrue(output.contains("4"), output)
        XCTAssertEqual(engine.generationStatistics["reusedTokens"]?.intValue, 0)
    }

    @MainActor func testRealChatImageUsesImportedProjectorAndReleasesTogether() async throws {
        let model = root.appendingPathComponent("Vendor/vision-model.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("Run scripts/fetch-vision-test-assets.sh") }
        let inference = InferenceService()
        let state = try AppState(inference: inference); state.activate(); state.newConversation()
        await state.importModel(model)
        let entry = try XCTUnwrap(state.selectedModel)
        defer { state.suspend(); state.removeModel(state.selectedModel ?? entry) }
        state.error = nil
        await state.importProjector(root.appendingPathComponent("Vendor/vision-projector.gguf"), model: entry)
        XCTAssertNil(state.error)
        XCTAssertNotNil(state.projectorURL(for: try XCTUnwrap(state.selectedModel)))
        XCTAssertEqual(state.selectedModel?.visionLabel, "Vision unverified")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try coloredImage(.blue).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        await state.addChatAttachments([file])
        XCTAssertTrue(state.send("What color is this image? Answer with the color only."))
        for _ in 0..<1_500 { if !state.isGenerating { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(state.isGenerating); XCTAssertNil(state.error)
        XCTAssertTrue(state.current.messages.last?.content.lowercased().contains("blue") == true, state.current.messages.last?.content ?? "no response")
        XCTAssertEqual(state.selectedModel?.visionLabel, "Vision")
        XCTAssertTrue(state.current.messages.last?.events?.contains { $0.title == "Reading images" && !$0.text.isEmpty } == true)
        let resident = await inference.residency(); XCTAssertNotNil(resident.path)
        state.suspend()
        let released = await inference.residency(); XCTAssertNil(released.path)
        state.activate()
        XCTAssertTrue(state.send("What color did I attach?"))
        for _ in 0..<1_500 { if !state.isGenerating { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(state.isGenerating); XCTAssertNil(state.error)
        let reloaded = await inference.residency(); XCTAssertEqual(reloaded.loads, resident.loads + 1)
        XCTAssertTrue(state.current.messages.last?.content.lowercased().contains("blue") == true)
    }

    @MainActor func testRealTextModelAnswersFromChatFile() async throws {
        let model = root.appendingPathComponent("Vendor/smoke-model.gguf")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("Run scripts/fetch-test-assets.sh") }
        let state = try AppState(); state.activate(); state.newConversation()
        await state.importModel(model)
        let entry = try XCTUnwrap(state.selectedModel)
        defer { state.suspend(); state.removeModel(entry) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Arrival information: The gate code is 4829.".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        await state.addChatAttachments([file])
        for tool in ToolName.allCases { state.policy[tool] = .deny }
        XCTAssertTrue(state.send("What is the gate code in my attached file?"))
        for _ in 0..<1_500 { if !state.isGenerating { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(state.isGenerating); XCTAssertNil(state.error)
        let answer = try XCTUnwrap(state.current.messages.last)
        XCTAssertTrue(answer.content.contains("4829"), answer.content)
        XCTAssertTrue(answer.citations.first?.excerpt.contains("4829") == true)
        XCTAssertFalse(answer.events?.contains { $0.kind == .tool } == true)
    }

    func testSameNamedFilesKeepDistinctEvidenceAndEveryFileGetsContext() async throws {
        let files = (1...6).map { index in
            ChatAttachment(name: "Notes.txt", originalBytes: 100, fingerprint: "\(index)", sections: [
                .init(text: String(repeating: "Device \(index) runs at \(index * 100) rpm. ", count: 120))
            ])
        }
        let candidates = try ChatAttachment.candidates(from: files, question: "How fast do the devices run?")
        XCTAssertEqual(Set(candidates.map { $0.id.components(separatedBy: ":")[0] }).count, 6)
        let service = try KnowledgeService()
        let selected = try await service.attachmentEvidence(files, question: "How fast do the devices run?")
        XCTAssertEqual(selected.count, 6)
        XCTAssertEqual(Set(selected.map { $0.id.components(separatedBy: ":")[0] }).count, 6)
    }

    func testReaderTextHTMLPDFImagesAndRejections() throws {
        let text = try ChatAttachmentReader.decode(Data("The observatory opens at 21:30.".utf8), name: "Schedule.txt")
        XCTAssertEqual(text.text, "The observatory opens at 21:30.")
        XCTAssertFalse(text.isImage)
        let html = try ChatAttachmentReader.decode(Data("<html><body><p>Harbor gate: 42</p><script>secret()</script></body></html>".utf8), name: "Gate.html")
        XCTAssertTrue(html.text.contains("Harbor gate: 42"))
        XCTAssertFalse(html.text.contains("secret()"))
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300)).pdfData { context in
            context.beginPage(); ("Backup key is TULIP" as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            context.beginPage(); ("Meeting room is Cedar" as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        let document = try ChatAttachmentReader.decode(pdf, name: "Notes.pdf")
        XCTAssertEqual(document.sections.map(\.page), [1, 2])
        XCTAssertTrue(document.text.contains("TULIP"))
        let photo = try ChatAttachmentReader.decode(coloredImage(.red), name: "Picture.jpg")
        XCTAssertTrue(photo.isImage); XCTAssertTrue(photo.sections.isEmpty)
        XCTAssertLessThan(try XCTUnwrap(photo.imageData).count, 1_500_000)
        for (data, name) in [(Data(), "Empty.txt"), (Data([0, 1, 255]), "Binary.txt"), (Data("hello".utf8), "Archive.zip"), (Data(repeating: 65, count: 100_001), "Long.txt")] {
            XCTAssertThrowsError(try ChatAttachmentReader.decode(data, name: name), name)
        }
        let scanned = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
        XCTAssertThrowsError(try ChatAttachmentReader.decode(scanned, name: "Scan.pdf"))
    }

    func testAttachmentSnapshotsRoundTripAndSelectVerbatimPages() throws {
        let file = ChatAttachment(name: "Manual.txt", originalBytes: 100, fingerprint: "sample", sections: [
            .init(text: "The pressure valve closes at 72 kPa.", page: 2),
            .init(text: "The water pump runs at 900 rpm.", page: 3)
        ])
        let messages = [ChatMessage(role: "user", content: "What pressure?", attachments: [file])]
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: JSONEncoder().encode(messages))
        XCTAssertEqual(decoded.first?.attachments, [file])
        XCTAssertEqual(ChatAttachment.files(in: decoded + decoded).count, 1)
        let candidates = try ChatAttachment.candidates(from: [file], question: "At what pressure does the valve close?")
        XCTAssertEqual(candidates.first?.excerpt, file.sections[0].text)
        XCTAssertTrue(candidates.first?.location.contains("page 2") == true)
        XCTAssertFalse(messages[0].content.contains("72"))
        let old = try JSONDecoder().decode(ChatMessage.self, from: Data("{\"id\":\"4870F2AA-A990-421A-A38F-14625F64BEFE\",\"role\":\"user\",\"content\":\"hello\",\"citations\":[],\"activity\":[],\"date\":0}".utf8))
        XCTAssertNil(old.attachments)
    }

    @MainActor private func state(_ inference: ScriptedInference) throws -> AppState {
        let state = try AppState(inference: inference); state.activate(); state.newConversation()
        state.models = [.init(id: "attachment-test", name: "Attachment test", family: "Test", repository: "", summary: "Scripted test only", parameters: "Test", minimumMemoryGB: 0, localFilename: "attachment-test.gguf")]
        state.selectModel(state.models[0])
        for tool in ToolName.allCases { state.policy[tool] = .deny }
        return state
    }
    @MainActor private func finish(_ state: AppState) async throws {
        for _ in 0..<500 {
            if !state.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Generation did not finish")
    }
    @MainActor func testFilesAreChatContextWithoutKnowledgeImportOrToolGrants() async throws {
        let inference = ScriptedInference([["The gate code is 4829 [1]."]], tokenDelay: .milliseconds(1))
        let state = try state(inference); defer { state.suspend() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Arrival.txt")
        try Data("The gate code is 4829. Check-in is after 15:00.".utf8).write(to: url)
        let originalDocuments = try await state.knowledge.documents().count
        let originalFolders = state.folders.count
        await state.addChatAttachments([url, url])
        XCTAssertEqual(state.pendingChatAttachments.count, 1)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(state.send("What is the gate code?"))
        try await finish(state)
        XCTAssertTrue(state.pendingChatAttachments.isEmpty)
        XCTAssertEqual(state.conversationAttachments.count, 1)
        XCTAssertTrue(inference.receivedPrompts.last?.last?.content.contains("4829") == true)
        XCTAssertEqual(state.current.messages.last?.citations.first?.title, "Arrival.txt")
        XCTAssertFalse(state.current.messages.last?.events?.contains { $0.kind == .tool } == true)
        let documents = try await state.knowledge.documents().count
        XCTAssertEqual(documents, originalDocuments); XCTAssertEqual(state.folders.count, originalFolders)
        for tool in ToolName.allCases { XCTAssertEqual(state.policy[tool], .deny) }
        XCTAssertTrue(state.send("What time is check-in?")); try await finish(state)
        XCTAssertTrue(inference.receivedPrompts.last?.last?.content.contains("15:00") == true)
        let saved = try XCTUnwrap(AppPaths.load([Conversation].self, name: "conversations.json")?.first { $0.id == state.conversationID })
        XCTAssertEqual(ChatAttachment.files(in: saved.messages).count, 1)
        XCTAssertFalse(saved.messages[0].content.contains("4829"))
        state.newConversation()
        XCTAssertTrue(state.conversationAttachments.isEmpty)
        XCTAssertTrue(state.send("Hello")); try await finish(state)
        XCTAssertFalse(inference.receivedPrompts.last?.contains { $0.content.contains("4829") } == true)
    }

    @MainActor func testPendingFilesRemoveCapsErrorsAndMissingVisionKeepDraft() async throws {
        let inference = ScriptedInference([["An image."]], tokenDelay: .milliseconds(1))
        let state = try state(inference); defer { state.suspend() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("Photo.jpg")
        try coloredImage(.red).write(to: photo)
        await state.addChatAttachments([photo, folder.appendingPathComponent("Missing.txt")])
        XCTAssertEqual(state.pendingChatAttachments.count, 1); XCTAssertNotNil(state.error)
        state.error = nil
        XCTAssertFalse(state.send("What is shown?"))
        XCTAssertTrue(state.error?.contains("vision") == true)
        XCTAssertEqual(state.pendingChatAttachments.count, 1)
        XCTAssertTrue(state.current.messages.isEmpty)
        let firstConversation = state.conversationID
        state.newConversation(); XCTAssertTrue(state.pendingChatAttachments.isEmpty)
        state.conversationID = firstConversation
        state.removeChatAttachment(try XCTUnwrap(state.pendingChatAttachments.first?.id))
        XCTAssertTrue(state.pendingChatAttachments.isEmpty)
        let urls = try (1...7).map { index -> URL in
            let url = folder.appendingPathComponent("Note\(index).txt")
            try Data("Note \(index)".utf8).write(to: url); return url
        }
        await state.addChatAttachments(urls)
        XCTAssertTrue(state.pendingChatAttachments.isEmpty)
        await state.addChatAttachments(Array(urls.prefix(6)))
        XCTAssertEqual(state.remainingChatAttachments, 0)
        XCTAssertTrue(state.send("")); try await finish(state)
        XCTAssertEqual(state.current.messages.first?.content, "Describe the attached files.")
        XCTAssertEqual(state.conversationAttachments.count, 6)
    }

    func testVisionCatalogIsSpecificToVariantAndProjectorsStayOutOfWeightList() async throws {
        let models = ModelCatalog.models
        XCTAssertEqual(models.filter { $0.vision == true }.count, 9)
        for id in ["gemma3-1", "phi4-mini", "minicpm5-1", "qwen3-4"] {
            XCTAssertEqual(models.first { $0.id == id }?.visionLabel, "Text only")
        }
        XCTAssertEqual(models.first { $0.id == "smolvlm-256" }?.visionLabel, "Vision")
        guard ProcessInfo.processInfo.environment["THIMVALE_NETWORK_TESTS"] == "1" else { return }
        let assets = try await ModelHub().assets(in: "ggml-org/SmolVLM-256M-Instruct-GGUF", revision: "b9e4379657e1450d04d02eec8e345667265b0a00")
        XCTAssertFalse(assets.projectors.isEmpty)
        XCTAssertTrue(assets.projectors.allSatisfy { $0.path.contains("mmproj") && $0.bytes > 0 && $0.sha256 != nil })
        XCTAssertTrue(assets.weights.allSatisfy { !$0.path.contains("mmproj") })
        XCTAssertEqual(Set((assets.weights + assets.projectors).map(\.revision)).count, 1)
    }
}
