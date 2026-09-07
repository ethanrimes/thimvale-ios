import XCTest
import SwiftSoup
@testable import Thimvale

final class WikipediaReaderTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/smoke-wikipedia.zim")
    }

    func testPagedArticleIndexAndFullTextSearchReadRealArchive() throws {
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Fetch the real Wikipedia fixture first.") }
        let archive = try PMArchive(path: fixture.path)
        let first = try archive.browse("", offset: 0, limit: 40)
        let next = try archive.browse("", offset: 40, limit: 40)
        XCTAssertEqual(first.count, 40); XCTAssertEqual(next.count, 40)
        XCTAssertTrue(Set(first.compactMap { $0["path"] }).isDisjoint(with: next.compactMap { $0["path"] }))
        XCTAssertTrue(first.allSatisfy { $0["html"] == nil }, "Browsing must not decompress all articles")
        XCTAssertTrue(try archive.browse("", offset: Int32(archive.articleCount), limit: 40).isEmpty)
        let results = try archive.browse("bowline", offset: 0, limit: 40)
        let row = try XCTUnwrap(results.first { $0["title"] == "Bowline" })
        let article = try archive.article(atPath: XCTUnwrap(row["path"]))
        XCTAssertEqual(article["title"], "Bowline")
        let html = try XCTUnwrap(article["html"])
        XCTAssertTrue(html.contains("History"))
        XCTAssertTrue(html.contains("href="))
        XCTAssertGreaterThan(html.count, 6_000, "Reader returns an article, not the Q&A excerpt")
        XCTAssertThrowsError(try archive.article(atPath: "not-in-this-pack-347821")) { error in
            XCTAssertTrue(error.localizedDescription.contains("isn't included"))
        }
        XCTAssertTrue(try archive.browse("notinthispack347821", offset: 0, limit: 40).isEmpty)
    }

    func testReaderServiceAndMissingPackDoNotNeedAModel() async throws {
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Fetch the real Wikipedia fixture first.") }
        try AppPaths.prepare()
        let filename = "reader-test-\(UUID().uuidString).zim"
        let copied = AppPaths.archives.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: fixture, to: copied)
        defer { try? FileManager.default.removeItem(at: copied) }
        let knowledge = try KnowledgeService()
        let page = try await knowledge.wikipediaPage(in: filename, query: "", offset: 0)
        XCTAssertEqual(page.entries.count, 40); XCTAssertTrue(page.hasMore)
        let result = try await knowledge.wikipediaPage(in: filename, query: "bowline", offset: 0)
        let entry = try XCTUnwrap(result.entries.first { $0.title == "Bowline" })
        let article = try await knowledge.wikipediaArticle(in: filename, path: entry.path)
        XCTAssertTrue(article.html.contains("History"))
        XCTAssertFalse(article.html.contains("<script"))
        await knowledge.closeArchive(filename)
        do { _ = try await knowledge.wikipediaPage(in: "../outside.zim", query: "", offset: 0); XCTFail("Traversal accepted") } catch {}
        do { _ = try await knowledge.wikipediaPage(in: filename, query: "", offset: -1); XCTFail("Negative offset accepted") } catch {}
        do { _ = try await knowledge.wikipediaPage(in: "missing-\(UUID().uuidString).zim", query: "", offset: 0); XCTFail("Missing pack accepted") } catch {}
    }

    func testReaderSanitizesArchiveHTMLAndPreservesTextStructure() throws {
        let raw = """
        <html><head><base href="https://evil.example"><meta http-equiv="refresh" content="0;url=https://evil.example"></head>
        <body onload="steal()"><script>steal()</script><iframe src="https://evil.example"></iframe>
        <style>body{background:url(https://evil.example)}</style><img src="https://evil.example/pixel">
        <h1>Article</h1><h2 id="history">History</h2><p style="color:red" onclick="steal()">Original paragraph.</p>
        <table><tr><td colspan="2">Original table</td></tr></table>
        <a href="javascript:steal()">Bad link</a><a href="file:///private/data">File link</a>
        <a href="../Bowline#History" ping="https://evil.example">Bowline</a><a href="#history">Jump</a>
        <form action="https://evil.example"><input name="secret"></form></body></html>
        """
        let rendered = try WikipediaHTML.render(raw, title: "Article", path: "A/Sheet_bend")
        let doc = try SwiftSoup.parse(rendered)
        XCTAssertTrue(try doc.select("script,iframe,img,form,input,base,[onclick],[onload],[ping]").isEmpty())
        XCTAssertFalse(rendered.contains("evil.example"))
        XCTAssertFalse(rendered.contains("javascript:")); XCTAssertFalse(rendered.contains("file:///"))
        XCTAssertEqual(try doc.select("h2#history").text(), "History")
        XCTAssertEqual(try doc.select("td").text(), "Original table")
        XCTAssertTrue(rendered.contains("default-src 'none'"))
        XCTAssertEqual(try doc.select("a").array().first { try $0.text() == "Jump" }?.attr("href"), "#history")
        XCTAssertTrue(rendered.contains("https://offline.thimvale.invalid/Bowline#History"))
    }

    func testOfflineLinkResolutionAndExternalBoundaries() throws {
        let linked = try XCTUnwrap(WikipediaHTML.link("../Bowline#History", from: "A/Sheet_bend"))
        XCTAssertEqual(WikipediaHTML.localPath(try XCTUnwrap(URL(string: linked))), "Bowline")
        XCTAssertEqual(WikipediaHTML.link("//en.wikipedia.org/wiki/Sheet_bend#Uses", from: "Bowline"), "https://offline.thimvale.invalid/Sheet_bend#Uses")
        XCTAssertEqual(WikipediaHTML.link("https://example.com/page", from: "Bowline"), "https://example.com/page")
        XCTAssertNil(WikipediaHTML.localPath(URL(string: "https://offline.thimvale.invalid.evil.example/Bowline")!))
        XCTAssertNil(WikipediaHTML.link("data:text/html,evil", from: "Bowline"))
        XCTAssertNil(WikipediaHTML.link("javascript:alert(1)", from: "Bowline"))
        XCTAssertNil(WikipediaHTML.link("file:///etc/passwd", from: "Bowline"))
        let special = "A/Knot (é)%/a?b#c"
        XCTAssertEqual(WikipediaHTML.localPath(WikipediaHTML.localURL(path: special)), special)
    }

    @MainActor func testInlineAnswerPresentationKeepsToolJSONAndReasoningInDetails() {
        func message(_ text: String) -> ChatMessage { var m = ChatMessage(role: "assistant", content: ""); m.events = [AgentEvent(kind: .generation, title: "Model output", text: text)]; return m }
        XCTAssertEqual(AppState.streamingAnswer(message("Hello world"), mode: .chat), "Hello world")
        XCTAssertEqual(AppState.streamingAnswer(message("A bowline is a loop"), mode: .work), "A bowline is a loop")
        XCTAssertEqual(AppState.streamingAnswer(message("{\"tool\":"), mode: .work), "")
        XCTAssertEqual(AppState.streamingAnswer(message("```j"), mode: .work), "")
        XCTAssertEqual(AppState.streamingAnswer(message("<tool_ca"), mode: .work), "")
        XCTAssertEqual(AppState.streamingAnswer(message("<think>unfinished"), mode: .chat), "")
        XCTAssertEqual(AppState.streamingAnswer(message("<thi"), mode: .chat), "")
        XCTAssertEqual(AppState.streamingAnswer(message("<think>private draft</think>Answer"), mode: .chat), "Answer")
        XCTAssertEqual(AppState.streamingAnswer(message("{\"value\":1}"), mode: .chat), "{\"value\":1}")
        var complete = message("Hello"); complete.content = "Hello"
        XCTAssertEqual(AppState.streamingAnswer(complete, mode: .chat), "", "Never show duplicate final text")
    }

    func testScreenshotModelAdditionsAreDistinctAndIncludeFourBClass() throws {
        let models = ModelCatalog.models
        let mini = try XCTUnwrap(models.first { $0.id == "minicpm5-2" })
        XCTAssertEqual(mini.repository, "openbmb/MiniCPM5-2B-GGUF")
        XCTAssertEqual(mini.minimumMemoryGB, 6)
        let nano = try XCTUnwrap(models.first { $0.id == "nemotron3-nano-4" })
        XCTAssertEqual(nano.family, "Nemotron"); XCTAssertTrue(nano.isFourBillionClass)
        XCTAssertTrue(nano.summary.contains("License"))
        let nanbeige = try XCTUnwrap(models.first { $0.id == "nanbeige41-3" })
        XCTAssertTrue(nanbeige.isFourBillionClass)
        XCTAssertNotEqual(nanbeige.repository, models.first { $0.id == "nanbeige42-3" }?.repository)
        XCTAssertEqual(Set(models.map(\.repository)).count, models.count)
    }

    func testInlineCitationsLinkOnlyReturnedSourcesAndResolveWithinMessage() throws {
        let sources = [Citation(id: "1", title: "Bowline", location: "Local pack", excerpt: "A fixed loop.")]
        let rendered = InlineCitations.text("Évidence **supports** this [1]. Unknown [9]. Code `[1]`. Incomplete [1", sources: sources)
        let links = rendered.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "thimvale-citation://source/1")!])
        XCTAssertEqual(InlineCitations.source(for: links[0], in: sources), sources[0])
        XCTAssertNil(InlineCitations.source(for: URL(string: "thimvale-citation://source/9")!, in: sources))
        XCTAssertNil(InlineCitations.source(for: URL(string: "https://source/1")!, in: sources))
        XCTAssertNil(InlineCitations.source(for: links[0], in: []))
        XCTAssertTrue(InlineCitations.text("Text [1]", sources: []).runs.compactMap(\.link).isEmpty)
        let existingLink = InlineCitations.text("Source [[1]](https://example.com)", sources: sources)
        XCTAssertTrue(existingLink.runs.compactMap(\.link).contains(links[0]))
    }
}
