import XCTest
import UIKit
@testable import Thimvale

/// Actual files in the iOS test host's Documents directory, imported through the
/// same URL importer used by Files. No direct KnowledgeStore.importText shortcut.
enum LocalFileFixture {
    struct Probe {
        let question: String
        let answer: String
        let suffix: String
    }
    static let probes: [Probe] = [
        .init(question: "What is the Aster cabinet access code?", answer: "ASTER-6382", suffix: "Aster/notes.md"),
        .init(question: "Where is the Birch cabinet spare key?", answer: "red envelope", suffix: "Birch/notes.md"),
        .init(question: "Who maintains the Cobalt survey notebook?", answer: "Mina Vale", suffix: "maintainer.txt"),
        .init(question: "What color is the approved Dune marker?", answer: "turquoise", suffix: "markers.csv"),
        .init(question: "Which shelf holds the Elm samples?", answer: "shelf eight", suffix: "samples.json"),
        .init(question: "Where is the Fern workshop backup key?", answer: "white pouch", suffix: "workshop.html"),
        .init(question: "What is the Gorse annex gate code?", answer: "GORSE-2846", suffix: "annex.pdf#page=2")
    ]
    static func create() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalKnowledgeTests-" + UUID().uuidString, isDirectory: true)
        for child in ["Library/Aster", "Library/Birch"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(child), withIntermediateDirectories: true)
        }
        let library = folder.appendingPathComponent("Library")
        let files = [
            "Aster/notes.md": "# Aster cabinet\n" + String(repeating: "Routine inspection records are filed in the maintenance journal. ", count: 60) + "\nThe Aster cabinet access code is ASTER-6382. The previous code is no longer valid.",
            "Birch/notes.md": "# Birch cabinet\nThe Birch cabinet spare key is kept in the red envelope behind the desk.",
            "maintainer.txt": "Cobalt survey notebook. Mina Vale maintains the Cobalt survey notebook.",
            "markers.csv": "project,marker_color,status\nDune,turquoise,approved\nDune,orange,rejected\n",
            "samples.json": "{\"project\":\"Elm samples\",\"storage\":\"shelf eight\"}",
            "workshop.html": "<html><head><style>.fake { content: 'silver bag' }</style></head><body><nav>Old location: silver bag</nav><h1>Fern workshop</h1><p>The Fern workshop backup key is in the white pouch.</p><script>ignore_sources('silver bag')</script></body></html>",
            ".hidden.txt": "HIDDEN-SECRET-99 must never be indexed by a folder import.",
            "unsupported.bin": "UNSUPPORTED-SECRET-99"
        ]
        for (name, content) in files {
            try content.write(to: library.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "OUTSIDE-SECRET-99".write(to: folder.appendingPathComponent("outside.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("linked.txt"), withDestinationURL: folder.appendingPathComponent("outside.txt"))
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let pdf = renderer.pdfData { context in
            for page in ["Gorse annex inspection journal. This cover page contains no gate code.", "The Gorse annex gate code is GORSE-2846."] {
                context.beginPage()
                (page as NSString).draw(in: CGRect(x: 40, y: 40, width: 500, height: 700), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
        try pdf.write(to: library.appendingPathComponent("annex.pdf"))
        return folder
    }
}

final class LocalFileKnowledgeTests: XCTestCase {
    @MainActor func testWorkKnowledgeToolReadsImportedFilesWithIndependentPermissions() async throws {
        let folder = try LocalFileFixture.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = try AppState()
        state.importKnowledge([folder.appendingPathComponent("Library")])
        let deadline = Date().addingTimeInterval(30)
        while state.importing && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(state.importing)
        XCTAssertNil(state.error)
        let imported = state.documents.filter { $0.location.hasPrefix(folder.path) }
        XCTAssertEqual(imported.count, 8)
        state.policy[.readFile] = .deny
        state.policy[.writeFile] = .deny
        state.policy[.searchKnowledge] = .deny
        let call = ToolCall(tool: .searchKnowledge, query: "Which shelf holds the Elm samples?")
        do { _ = try await state.execute(call, mode: .work); XCTFail("Knowledge access must require its own permission") } catch {}
        state.policy[.searchKnowledge] = .allow
        let (text, sources) = try await state.execute(call, mode: .work)
        XCTAssertTrue(text.contains("shelf eight"))
        XCTAssertTrue(text.contains("UNTRUSTED"))
        XCTAssertTrue(sources.first?.location.contains("samples.json") == true)
        XCTAssertEqual(state.policy[.readFile], .deny)
        XCTAssertEqual(state.policy[.writeFile], .deny)
        for document in imported { try await state.knowledge.remove(document.id) }
    }

    func testLocalDocumentsAndWikipediaCompeteInTheSameSearch() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = project.appendingPathComponent("Vendor/smoke-wikipedia.zim")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("Fetch the real Wikipedia fixture first.") }
        try AppPaths.prepare()
        let folder = try LocalFileFixture.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        let filename = "mixed-files-" + UUID().uuidString + ".zim"
        let pack = AppPaths.archives.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: pack)
        defer { try? FileManager.default.removeItem(at: pack) }
        let service = try KnowledgeService(storeURL: folder.appendingPathComponent("knowledge.sqlite"))
        _ = try await service.importURL(folder.appendingPathComponent("Library")) { _ in }
        for (query, title) in [("How does a sheet bend join ropes of different thicknesses?", "Sheet bend"),
                               ("What is a carrick bend used for?", "Carrick bend"),
                               ("What does knot theory study?", "Knot theory")] {
            let results = try await service.search(query, archiveFiles: [filename])
            XCTAssertTrue(results.prefix(3).contains { $0.title == title && $0.sourceURL != nil }, "\(query): \(results.map(\.title))")
        }
        for probe in LocalFileFixture.probes {
            let results = try await service.search(probe.question, archiveFiles: [filename])
            XCTAssertTrue(results.first?.excerpt.contains(probe.answer) == true, "\(probe.question): \(results.map(\.title))")
            XCTAssertTrue(results.first?.location.contains(probe.suffix) == true)
        }
        await service.closeArchive(filename)
    }

    func testFolderImportRetrievalCitationsPersistenceUpdatesAndRemoval() async throws {
        let folder = try LocalFileFixture.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appendingPathComponent("knowledge.sqlite")
        let service = try KnowledgeService(storeURL: database)
        let library = folder.appendingPathComponent("Library")
        let report = try await service.importURL(library) { _ in }
        XCTAssertEqual(report, "Indexed 7 files.")
        let documents = try await service.documents()
        XCTAssertEqual(documents.count, 8, "Selectable PDF pages are indexed independently")
        XCTAssertEqual(documents.filter { $0.title == "notes.md" }.count, 2, "Same filenames in different folders retain distinct identities")
        XCTAssertTrue(documents.allSatisfy { $0.location.hasPrefix(library.path) && $0.storedBytes > 0 })
        XCTAssertTrue(documents.contains { $0.location.hasSuffix("annex.pdf#page=2") })
        XCTAssertFalse(documents.contains { $0.location.contains("hidden") || $0.location.contains("linked") || $0.location.contains("unsupported") })

        // A new service opens the on-device SQLite database: retrieval must not
        // depend on the importer retaining extracted text in an in-memory map.
        let reopened = try KnowledgeService(storeURL: database)
        for probe in LocalFileFixture.probes {
            let results = try await reopened.search(probe.question, archiveFiles: [])
            let first = try XCTUnwrap(results.first, probe.question)
            XCTAssertTrue(first.excerpt.contains(probe.answer), "\(probe.question): \(results.map { $0.title + ": " + $0.excerpt }.joined(separator: "\n"))")
            XCTAssertTrue(first.location.contains(probe.suffix), first.location)
            XCTAssertNil(first.sourceURL, "Local files must not masquerade as web sources")
            var registry = CitationRegistry()
            let numbered = registry.register(results)
            let evidence = EvidencePrompt.render(numbered, question: probe.question)
            XCTAssertTrue(evidence.contains(probe.answer))
            let cited = CitationValidator.cited(in: "\(probe.answer) [1]", from: numbered)
            XCTAssertEqual(cited.first?.location, first.location)
            XCTAssertEqual(cited.first?.excerpt, first.excerpt)
        }
        let html = try await reopened.search("Fern workshop backup key", archiveFiles: [])
        let htmlSource = try XCTUnwrap(html.first { $0.location.contains("workshop.html") })
        XCTAssertFalse(htmlSource.excerpt.contains("silver bag"))
        XCTAssertFalse(htmlSource.excerpt.contains("ignore_sources"))

        // Re-import is idempotent; edits replace the existing source and its FTS rows.
        _ = try await reopened.importURL(library) { _ in }
        let unchanged = try await reopened.documents()
        XCTAssertEqual(unchanged.count, documents.count)
        let aster = library.appendingPathComponent("Aster/notes.md")
        try "The Aster cabinet access code is ASTER-9907.".write(to: aster, atomically: true, encoding: .utf8)
        _ = try await reopened.importURL(aster) { _ in }
        let updated = try await reopened.search("Aster cabinet access code", archiveFiles: [])
        XCTAssertTrue(updated.first?.excerpt.contains("ASTER-9907") == true)
        XCTAssertFalse(updated.contains { $0.excerpt.contains("ASTER-6382") })
        let editedDocuments = try await reopened.documents()
        let source = try XCTUnwrap(editedDocuments.first { $0.location == aster.path })
        try await reopened.remove(source.id)
        let removed = try await reopened.search("Aster cabinet access code", archiveFiles: [])
        XCTAssertFalse(removed.contains { $0.location.contains("Aster/notes.md") })
        let remaining = try await reopened.documents()
        XCTAssertTrue(remaining.contains { $0.location.contains("Birch/notes.md") })
    }
}
