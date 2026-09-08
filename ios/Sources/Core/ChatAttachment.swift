import Foundation

/// A conversation-local snapshot. Never a persistent grant to the source folder.
struct ChatAttachment: Codable, Identifiable, Sendable, Equatable {
    struct Section: Codable, Sendable, Equatable {
        var text: String
        var page: Int?
    }
    static let maximumFiles = 6
    static let maximumImages = 3
    static let maximumTextBytes = 100_000
    var id = UUID()
    var name: String
    var originalBytes: Int64
    var fingerprint: String
    var sections: [Section] = []
    // Downsampled JPEG, stripped of source metadata. No original photo is saved.
    var imageData: Data?
    var isImage: Bool { imageData != nil }
    var text: String { sections.map(\.text).joined(separator: "\n\n") }
    var preview: Citation {
        let body = text
        return Citation(id: "File", title: name,
                        location: body.count > 12_000 ? "Attached to this chat · preview of the first 12,000 characters" : "Attached to this chat",
                        excerpt: String(body.prefix(12_000)))
    }
    static func files(in messages: [ChatMessage]) -> [ChatAttachment] {
        var seen = Set<UUID>()
        return messages.flatMap { $0.attachments ?? [] }.filter { seen.insert($0.id).inserted }
    }
    /// Bounded lexical shortlist; the caller reranks it using its sentence embedding.
    static func candidates(from files: [ChatAttachment], question: String) throws -> [Citation] {
        var ranked: [(citation: Citation, score: Double, order: Int)] = []
        let terms = Set(KnowledgeStore.searchTerms(question))
        for file in files where !file.isImage {
            for section in file.sections {
                for chunk in TextChunker.chunks(section.text) {
                    try Task.checkCancellation()
                    let page = section.page.map { " · page \($0)" } ?? ""
                    let location = "Attachment · \(file.name)\(page) · character \(chunk.offset)"
                    let id = "A\(file.id.uuidString):\(section.page ?? 0):\(chunk.offset)"
                    let citation = Citation(id: id, title: file.name + page, location: location, excerpt: chunk.text)
                    let titleOverlap = Double(terms.intersection(KnowledgeStore.searchTerms(file.name)).count) / Double(max(terms.count, 1))
                    let score = EvidenceSelection.window(chunk.text, query: question).relevance + titleOverlap * 0.3
                    ranked.append((citation, score, ranked.count))
                }
            }
        }
        let ordered = ranked.sorted { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }.map(\.citation)
        // One large attachment must not push every other file out of the shortlist.
        return diverse(ordered, limit: 30)
    }
    static func diverse(_ sources: [Citation], limit: Int) -> [Citation] {
        var seen = Set<String>()
        let firstPerFile = sources.filter { seen.insert($0.id.components(separatedBy: ":")[0]).inserted }
        let used = Set(firstPerFile.map(\.id))
        return Array((firstPerFile + sources.filter { !used.contains($0.id) }).prefix(limit))
    }
}
