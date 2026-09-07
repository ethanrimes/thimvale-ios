import Foundation
import CryptoKit

enum PocketError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum ConversationMode: String, Codable, CaseIterable { case chat = "Chat", work = "Work" }

struct Citation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var location: String
    var excerpt: String
    var sourceURL: String?
}

struct ChatMessage: Codable, Identifiable, Sendable {
    var id = UUID()
    var role: String
    var content: String
    var citations: [Citation] = []
    var activity: [String] = []
    var date = Date()
}

struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title = "New conversation"
    var mode: ConversationMode = .chat
    var messages: [ChatMessage] = []
    var updatedAt = Date()
}

struct ModelEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var family: String
    var repository: String
    var summary: String
    var parameters: String
    var minimumMemoryGB: Int
    var preferredQuant = "Q4_K_M"
    var localFilename: String?
    var license: String?
    var isDownloaded: Bool { localFilename != nil }
    var isFourBillionClass: Bool {
        let label = parameters.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.hasSuffix("B"), let billions = Double(label.dropLast()) else { return false }
        return (3.5..<4.5).contains(billions)
    }
    func matchesLibrarySearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || "\(name) \(family) \(parameters) \(summary)".localizedCaseInsensitiveContains(query)
    }
}

struct HubFile: Identifiable, Sendable {
    var id: String { path }
    var repository: String
    var revision: String
    var path: String
    var bytes: Int64
    var sha256: String?
    var downloadURL: URL {
        URL(string: "https://huggingface.co")!
            .appendingPathComponent(repository)
            .appendingPathComponent("resolve")
            .appendingPathComponent(revision)
            .appendingPathComponent(path)
    }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

enum StableID {
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum CitationValidator {
    /// Only expose evidence IDs actually present in the generated answer and supplied by tools.
    static func cited(in text: String, from available: [Citation]) -> [Citation] {
        var seen = Set<String>()
        return available.filter { text.contains("[\($0.id)]") && seen.insert($0.id).inserted }
    }
}

/// Short, turn-local labels are easier for small models to reproduce than hashes.
/// Stable retrieval IDs remain the deduplication keys; numbering cannot redirect a source.
struct CitationRegistry {
    private var labels: [String: String] = [:]
    private(set) var citations: [Citation] = []
    mutating func register(_ sources: [Citation]) -> [Citation] {
        sources.map { source in
            var numbered = source
            if let label = labels[source.id] { numbered.id = label }
            else {
                numbered.id = String(citations.count + 1)
                labels[source.id] = numbered.id
                citations.append(numbered)
            }
            return numbered
        }
    }
}

enum FileValidation {
    static func check(_ url: URL, magic: [UInt8], expectedBytes: Int64? = nil) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: magic.count) == Data(magic) else {
            throw PocketError.message("The downloaded file has an invalid format. It may be an error page or an unsupported file.")
        }
        if let expectedBytes, expectedBytes > 0 {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(bytes) == expectedBytes else { throw PocketError.message("The download is incomplete. Please resume or try again.") }
        }
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
