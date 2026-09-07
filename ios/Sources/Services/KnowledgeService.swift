import Foundation
import PDFKit
import SwiftSoup

struct WikiPack: Identifiable, Codable, Sendable {
    var id: String
    var name: String
    var summary: String
    var edition: String
    var date: String
    var bytes: Int64
    var url: URL
    var filename: String { url.lastPathComponent }
    var isMini: Bool { edition == "mini" }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

enum WikipediaCatalog {
    static func fetch(includePictures: Bool = false) async throws -> [WikiPack] {
        let url = URL(string: "https://library.kiwix.org/catalog/v2/entries?lang=eng&q=wikipedia&count=100")!
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PocketError.message("The Wikipedia catalog is unavailable. Try again later.") }
        let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), "", Parser.xmlParser())
        var result: [WikiPack] = []
        let allowed = ["wikipedia_en_all", "wikipedia_en_top", "wikipedia_en_top1m", "wikipedia_en_geography", "wikipedia_en_medicine", "wikipedia_en_mathematics", "wikipedia_en_physics", "wikipedia_en_chemistry", "wikipedia_en_knots"]
        for entry in try doc.select("entry") {
            let name = try entry.select("name").first()?.text() ?? ""
            let flavour = try entry.select("flavour").text()
            guard allowed.contains(name), (includePictures ? ["mini", "nopic", "maxi"] : ["mini", "nopic"]).contains(flavour), try entry.select("tags").text().contains("_ftindex:yes"), let link = try entry.select("link[type=application/x-zim]").first() else { continue }
            let remote = try link.attr("href")
            guard let filename = URL(string: remote)?.lastPathComponent.replacingOccurrences(of: ".meta4", with: ""), filename.hasSuffix(".zim") else { continue }
            let title = name == "wikipedia_en_all" ? "English Wikipedia" : try entry.select("title").text()
            result.append(.init(id: StableID.hash(filename), name: title, summary: try entry.select("summary").text(), edition: flavour, date: String(try entry.select("updated").text().prefix(10)), bytes: Int64(try link.attr("length")) ?? 0, url: URL(string: "https://download.kiwix.org/zim/wikipedia/")!.appendingPathComponent(filename)))
        }
        guard !result.isEmpty else { throw PocketError.message("No compatible English Wikipedia packs were returned.") }
        return result.sorted { $0.bytes < $1.bytes }
    }
    static func downloadJob(for pack: WikiPack) async throws -> DownloadJob {
        let (data, response) = try await URLSession.shared.data(from: URL(string: pack.url.absoluteString + ".meta4")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PocketError.message("Could not verify this pack's download metadata.") }
        let metadata = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), "", Parser.xmlParser())
        let digest = try metadata.select("hash[type=sha-256]").first()?.text()
        let bytes = Int64(try metadata.select("file > size").text()) ?? 0
        guard let digest, digest.count == 64, bytes > 0 else { throw PocketError.message("This archive has no valid checksum or size metadata.") }
        return .init(id: pack.id, title: pack.name + (pack.isMini ? " · Mini" : " · Full text"), url: pack.url, kind: .wikipedia, filename: pack.filename, expectedBytes: bytes, sha256: digest)
    }
}

actor KnowledgeService {
    private let store: KnowledgeStore
    private var archives: [String: PMArchive] = [:]
    init() throws { store = try KnowledgeStore(url: AppPaths.root.appendingPathComponent("knowledge.sqlite")) }
    func documents() throws -> [KnowledgeDocument] { try store.documents() }
    func hasSemanticSearch() -> Bool { store.hasSemanticSearch }
    func remove(_ id: String) throws { try store.remove(id: id) }
    func closeArchive(_ filename: String) { archives[filename] = nil }

    private func archive(_ filename: String) throws -> PMArchive {
        guard !filename.isEmpty, filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".zim") else {
            throw PocketError.message("Choose a downloaded Wikipedia pack.")
        }
        if let cached = archives[filename] { return cached }
        let opened = try PMArchive(path: AppPaths.archives.appendingPathComponent(filename).path)
        archives[filename] = opened
        return opened
    }

    func wikipediaPage(in filename: String, query: String, offset: Int) throws -> WikipediaPage {
        try Task.checkCancellation()
        guard offset >= 0, offset <= Int(Int32.max) - 100 else { throw PocketError.message("This page number is out of range.") }
        let opened = try archive(filename)
        let rows = try opened.browse(String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)), offset: Int32(offset), limit: 41)
        let entries = try rows.prefix(40).map { row in
            WikipediaEntry(path: row["path"] ?? "", title: row["title"] ?? "Untitled", snippet: try SwiftSoup.parse(row["snippet"] ?? "").text())
        }
        try Task.checkCancellation()
        return WikipediaPage(entries: entries, hasMore: rows.count > 40, articleCount: Int(opened.articleCount))
    }

    func wikipediaArticle(in filename: String, path: String) throws -> WikipediaArticle {
        try Task.checkCancellation()
        let row = try archive(filename).article(atPath: path)
        let title = row["title"] ?? "Wikipedia"
        let canonicalPath = row["path"] ?? path
        let html = try WikipediaHTML.render(row["html"] ?? "", title: title, path: canonicalPath)
        try Task.checkCancellation()
        return WikipediaArticle(title: title, path: canonicalPath, html: html)
    }

    func importURL(_ url: URL, progress: @Sendable (String) -> Void) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let directory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let urls: [URL]
        if directory {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw PocketError.message("Cannot read this folder.") }
            var files: [URL] = []
            for case let file as URL in enumerator {
                try Task.checkCancellation()
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true, ["txt", "md", "markdown", "pdf", "csv", "json", "html", "htm", "rst"].contains(file.pathExtension.lowercased()) { files.append(file) }
                if files.count > 1_000 { throw PocketError.message("Select a folder with at most 1,000 supported files per import.") }
            }
            urls = files
        } else { urls = [url] }
        var imported = 0
        var failures: [String] = []
        for (i, file) in urls.enumerated() {
            try Task.checkCancellation()
            progress("Indexing \(i + 1) of \(urls.count): \(file.lastPathComponent)")
            do {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 25_000_000 else { throw PocketError.message("File exceeds 25 MB or is a symbolic link.") }
                let location = file.path
                if file.pathExtension.lowercased() == "pdf" {
                    guard let pdf = PDFDocument(url: file), !pdf.isLocked, pdf.pageCount <= 500 else { throw PocketError.message("This PDF is locked, invalid, or longer than 500 pages.") }
                    var pages = 0
                    for pageIndex in 0..<pdf.pageCount {
                        try Task.checkCancellation()
                        if let text = pdf.page(at: pageIndex)?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try store.importText(title: "\(file.lastPathComponent) · page \(pageIndex + 1)", location: "\(location)#page=\(pageIndex + 1)", text: text)
                            pages += 1
                        }
                    }
                    guard pages > 0 else { throw PocketError.message("This PDF has no selectable text; OCR is not yet supported.") }
                } else {
                    var text = try String(contentsOf: file, encoding: .utf8)
                    if ["html", "htm"].contains(file.pathExtension.lowercased()) { text = try Self.plainText(text) }
                    try store.importText(title: file.lastPathComponent, location: location, text: text)
                }
                imported += 1
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        guard !urls.isEmpty else { throw PocketError.message("No supported text files or PDFs were found in this folder.") }
        return "Indexed \(imported) file\(imported == 1 ? "" : "s")." + (failures.isEmpty ? "" : "\nSkipped \(failures.count):\n" + failures.prefix(5).joined(separator: "\n"))
    }
    static func plainText(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        try doc.select("script, style, nav, footer, header, .navbox, .mw-editsection, .reflist").remove()
        let blocks = try doc.select("h1, h2, h3, p, li").array().map { try $0.text() }.filter { !$0.isEmpty }
        return blocks.isEmpty ? try doc.text() : blocks.joined(separator: "\n\n")
    }
    func search(_ query: String, archiveFiles: [String]) throws -> [Citation] {
        var results = try store.search(query, limit: 5)
        let terms = KnowledgeStore.searchTerms(query)
        let keywords = Set(terms)
        for filename in WikipediaEdition.preferredFiles(archiveFiles) {
            try Task.checkCancellation()
            let archive = try archive(filename)
            var articles = try archive.search(query, limit: 6)
            if articles.isEmpty {
                // Use plain search terms for libzim, not SQLite's quoted-OR expression.
                if !terms.isEmpty { articles = try archive.search(terms.joined(separator: " "), limit: 6) }
                if articles.isEmpty {
                    for term in terms.prefix(3) { articles += try archive.search(term, limit: 2) }
                }
            }
            var seen = Set<String>()
            articles = articles.filter { seen.insert($0["path"] ?? $0["title"] ?? "").inserted }
            // A definition of a named article should not be diluted by similarly named variants.
            if let exact = articles.first(where: { ($0["title"] ?? "").lowercased() == terms.joined(separator: " ") }),
               query.lowercased().hasPrefix("what is") || terms.count == 1 {
                articles = [exact]
            }
            for article in articles {
                let title = article["title"] ?? "Wikipedia"
                let text = try Self.plainText(article["html"] ?? "")
                let passages = TextChunker.chunks(text)
                let ranked = passages.map { passage -> (TextChunker.Chunk, Double) in
                    let words = Set(passage.text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
                    return (passage, Double(keywords.intersection(words).count))
                }.sorted { $0.1 > $1.1 }.prefix(12)
                let definition = query.lowercased().hasPrefix("what is") || terms.joined(separator: " ") == title.lowercased()
                let scored: [(chunk: TextChunker.Chunk, score: Double)] = ranked.map { chunk, lexical in
                    let semantic = store.semanticScore(query: query, passage: chunk.text) * 2
                    let introductionBonus: Double = definition && chunk.offset == 0 ? 1 : 0
                    return (chunk, lexical + semantic + introductionBonus)
                }
                let best = scored.max { left, right in
                    left.score == right.score ? left.chunk.offset > right.chunk.offset : left.score < right.score
                }?.chunk
                guard let best else { continue }
                let link = URL(string: "https://en.wikipedia.org/wiki/")!.appendingPathComponent(title.replacingOccurrences(of: " ", with: "_"))
                results.append(Citation(id: "W" + String(StableID.hash("\(filename):\(title):\(best.offset)").prefix(8)), title: title, location: "Wikipedia · \(filename) · character \(best.offset)", excerpt: best.text, sourceURL: link.absoluteString))
            }
        }
        // The selected excerpt is always an exact chunk from the stored source, never an LLM summary.
        return Array(results.prefix(10))
    }
}
