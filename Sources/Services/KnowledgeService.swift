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
    static func fetch() async throws -> [WikiPack] {
        let url = URL(string: "https://library.kiwix.org/catalog/v2/entries?lang=eng&q=wikipedia&count=100")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PocketError.message("The Wikipedia catalog is unavailable. Try again later.") }
        let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), "", Parser.xmlParser())
        var result: [WikiPack] = []
        let allowed = ["wikipedia_en_all", "wikipedia_en_top", "wikipedia_en_top1m", "wikipedia_en_geography", "wikipedia_en_medicine", "wikipedia_en_mathematics", "wikipedia_en_physics", "wikipedia_en_chemistry", "wikipedia_en_knots"]
        for entry in try doc.select("entry") {
            let name = try entry.select("name").first()?.text() ?? ""
            let flavour = try entry.select("flavour").text()
            guard allowed.contains(name), ["mini", "nopic"].contains(flavour), try entry.select("tags").text().contains("_ftindex:yes"), let link = try entry.select("link[type=application/x-zim]").first() else { continue }
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
        let keywords = Set(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        for filename in archiveFiles {
            try Task.checkCancellation()
            if archives[filename] == nil { archives[filename] = try PMArchive(path: AppPaths.archives.appendingPathComponent(filename).path) }
            guard let archive = archives[filename] else { continue }
            let articles = try archive.search(query, limit: 6)
            for article in articles {
                let title = article["title"] ?? "Wikipedia"
                let text = try Self.plainText(article["html"] ?? "")
                let passages = TextChunker.chunks(text)
                let ranked = passages.map { passage -> (TextChunker.Chunk, Double) in
                    let words = Set(passage.text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
                    return (passage, Double(keywords.intersection(words).count))
                }.sorted { $0.1 > $1.1 }.prefix(12)
                let best = ranked.map { ($0.0, $0.1 + store.semanticScore(query: query, passage: $0.0.text) * 2) }.max { $0.1 < $1.1 }?.0
                guard let best else { continue }
                let link = URL(string: "https://en.wikipedia.org/wiki/")!.appendingPathComponent(title.replacingOccurrences(of: " ", with: "_"))
                results.append(Citation(id: "W" + String(StableID.hash("\(filename):\(title):\(best.offset)").prefix(8)), title: title, location: "Wikipedia · \(filename) · character \(best.offset)", excerpt: best.text, sourceURL: link.absoluteString))
            }
        }
        // The selected excerpt is always an exact chunk from the stored source, never an LLM summary.
        return Array(results.prefix(10))
    }
}
