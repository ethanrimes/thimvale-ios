import XCTest
@testable import PocketMindCore

final class CoreTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testToolPolicyFailsClosedAndChatNeverHasTools() throws {
        var policy = PermissionPolicy()
        for tool in ToolName.allCases { XCTAssertThrowsError(try policy.requiresApproval(for: tool, mode: .chat)) }
        XCTAssertThrowsError(try policy.requiresApproval(for: .webSearch, mode: .work))
        XCTAssertTrue(try policy.requiresApproval(for: .writeFile, mode: .work))
        XCTAssertFalse(try policy.requiresApproval(for: .searchKnowledge, mode: .work))
        policy[.readFile] = .deny
        policy[.writeFile] = .allow
        XCTAssertThrowsError(try policy.requiresApproval(for: .readFile, mode: .work))
        XCTAssertFalse(try policy.requiresApproval(for: .writeFile, mode: .work))
    }

    func testTraversalSymlinksAndOverwritesAreBlocked() throws {
        let base = try temporaryDirectory()
        let root = base.appendingPathComponent("granted")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try SecureWorkspace.create(root: outside, path: "secret.txt", content: "secret")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"), withDestinationURL: outside.appendingPathComponent("secret.txt"))
        for path in ["../outside/secret.txt", "/etc/passwd", "escape/secret.txt", "link.txt", "foo/../../secret"] {
            XCTAssertThrowsError(try SecureWorkspace.read(root: root, path: path), path)
            XCTAssertThrowsError(try SecureWorkspace.create(root: root, path: path, content: "overwrite"), path)
        }
        try SecureWorkspace.create(root: root, path: "note.md", content: "my note")
        XCTAssertEqual(try SecureWorkspace.read(root: root, path: "note.md"), "my note")
        XCTAssertThrowsError(try SecureWorkspace.create(root: root, path: "note.md", content: "replace"))
        XCTAssertEqual(try SecureWorkspace.read(root: outside, path: "secret.txt"), "secret")
        XCTAssertThrowsError(try SecureWorkspace.list(root: root, path: "escape"))
    }

    func testCompressionAndBinaryVectors() throws {
        for text in ["", "a", "你好 👋 café", String(repeating: "A passage about offline knowledge. ", count: 100)] {
            XCTAssertEqual(try CompactText.decode(CompactText.encode(text), originalBytes: text.utf8.count), text)
        }
        let a = BinaryVector.encode([1, -1, 1, -1, 1, -1, 1, -1])
        let b = BinaryVector.encode([-1, 1, -1, 1, -1, 1, -1, 1])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(BinaryVector.similarity(a, a), 1)
        XCTAssertEqual(BinaryVector.similarity(a, b), 0)
        XCTAssertThrowsError(try CompactText.decode(Data([1, 2]), originalBytes: 200))
    }

    func testKnowledgeImportSearchUpdateDeleteAndCitations() throws {
        let store = try KnowledgeStore(url: temporaryDirectory().appendingPathComponent("knowledge.sqlite"))
        let original = "The axolotl is a neotenic salamander. Axolotls retain external gills throughout adulthood and can regenerate limbs."
        XCTAssertGreaterThan(try store.importText(title: "Axolotl field notes", location: "Notes/axolotl.txt", text: original), 0)
        XCTAssertEqual(try store.importText(title: "Axolotl field notes", location: "Notes/axolotl.txt", text: original), 0)
        try store.importText(title: "Geology", location: "Notes/geology.txt", text: "Basalt is an extrusive igneous rock formed from cooling lava.")
        let results = try store.search("axolotl gills")
        XCTAssertEqual(results.first?.title, "Axolotl field notes")
        XCTAssertTrue(results.first?.excerpt.contains("regenerate") == true)
        let source = try XCTUnwrap(results.first)
        XCTAssertEqual(CitationValidator.cited(in: "They retain gills [\(source.id)]. [invented]", from: results), [source])
        XCTAssertTrue(CitationValidator.cited(in: "[invented]", from: results).isEmpty)
        try store.importText(title: "Axolotl updated", location: "Notes/axolotl.txt", text: "Axolotl conservation involves habitat restoration in Xochimilco.")
        XCTAssertEqual(try store.documents().count, 2)
        let doc = try XCTUnwrap(store.documents().first { $0.title == "Axolotl updated" })
        try store.remove(id: doc.id)
        XCTAssertEqual(try store.documents().count, 1)
        XCTAssertFalse(try store.search("axolotl").contains { $0.title.contains("Axolotl") })
    }

    func testAgentParsingAndTermination() throws {
        let call = try XCTUnwrap(ToolCall.parse("{\"tool\":\"search_knowledge\",\"query\":\"axolotl\"}"))
        XCTAssertNil(ToolCall.parse("The article says {\"tool\":\"write_file\"}"))
        XCTAssertNil(ToolCall.parse("{\"tool\":\"delete_everything\"}"))
        var budget = AgentBudget(maximumCalls: 3)
        try budget.consume(call); try budget.consume(call)
        XCTAssertThrowsError(try budget.consume(call))
        try budget.consume(ToolCall(tool: .listFiles, folder: "id"))
        XCTAssertThrowsError(try budget.consume(ToolCall(tool: .readFile, path: "a")))
    }

    func testFileValidationAndChunkBounds() throws {
        let url = try temporaryDirectory().appendingPathComponent("model.gguf")
        try Data("<html>error</html>".utf8).write(to: url)
        XCTAssertThrowsError(try FileValidation.check(url, magic: [0x47,0x47,0x55,0x46]))
        let chunks = TextChunker.chunks(String(repeating: "word 👋 ", count: 1_000))
        XCTAssertGreaterThan(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 1_200 })
        XCTAssertTrue(TextChunker.chunks("test", size: 10, overlap: 10).isEmpty)
        XCTAssertEqual(KnowledgeStore.lexicalQuery("\" OR * () --"), "\"or\"")
    }
}
