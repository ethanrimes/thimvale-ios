import Foundation
import SQLite3
import Compression
import NaturalLanguage

enum CompactText {
    static func encode(_ text: String) -> Data {
        let source = Array(text.utf8)
        guard !source.isEmpty else { return Data([0]) }
        var destination = [UInt8](repeating: 0, count: source.count + 256)
        let size = compression_encode_buffer(&destination, destination.count, source, source.count, nil, COMPRESSION_LZFSE)
        if size > 0, size < source.count { return Data([1]) + Data(destination.prefix(size)) }
        return Data([0]) + Data(source)
    }
    static func decode(_ data: Data, originalBytes: Int) throws -> String {
        guard let codec = data.first, originalBytes >= 0, originalBytes <= 1_000_000 else { throw PocketError.message("Invalid passage data.") }
        if codec == 0 {
            guard data.count - 1 == originalBytes else { throw PocketError.message("Invalid passage size.") }
            return String(decoding: data.dropFirst(), as: UTF8.self)
        }
        guard codec == 1 else { throw PocketError.message("Unsupported passage compression.") }
        let source = Array(data.dropFirst())
        var destination = [UInt8](repeating: 0, count: max(1, originalBytes))
        let size = compression_decode_buffer(&destination, originalBytes, source, source.count, nil, COMPRESSION_LZFSE)
        guard size == originalBytes else { throw PocketError.message("This knowledge passage is damaged.") }
        return String(decoding: destination.prefix(size), as: UTF8.self)
    }
}

enum BinaryVector {
    static func encode(_ vector: [Double]) -> Data {
        var bits = [UInt8](repeating: 0, count: (vector.count + 7) / 8)
        for (index, value) in vector.enumerated() where value > 0 { bits[index / 8] |= 1 << (index % 8) }
        return Data(bits)
    }
    static func similarity(_ a: Data, _ b: Data) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        let distance = zip(a, b).reduce(0) { $0 + ($1.0 ^ $1.1).nonzeroBitCount }
        return 1 - Double(distance) / Double(a.count * 8)
    }
}

enum TextChunker {
    struct Chunk { var text: String; var offset: Int }
    static func chunks(_ text: String, size: Int = 1_200, overlap: Int = 160) -> [Chunk] {
        guard size > 0, overlap >= 0, overlap < size else { return [] }
        let chars = Array(text)
        var result: [Chunk] = []
        var start = 0
        while start < chars.count {
            var end = min(start + size, chars.count)
            if end < chars.count, let boundary = (max(start + size / 2, start)..<end).reversed().first(where: { chars[$0].isWhitespace }) { end = boundary }
            let passage = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !passage.isEmpty { result.append(Chunk(text: passage, offset: start)) }
            if end == chars.count { break }
            start = max(start + 1, end - overlap)
        }
        return result
    }
}

struct KnowledgeDocument: Identifiable, Sendable {
    var id: String
    var title: String
    var location: String
    var passages: Int
    var storedBytes: Int64
}

/// Serialized by the owning actor. SQLite is also opened FULLMUTEX for defensive use.
final class KnowledgeStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var embeddingID: String { "apple-en-sentence-\(embedding?.revision ?? 0)-binary-v1" }
    var hasSemanticSearch: Bool { embedding != nil }
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db); db = nil }
            throw PocketError.message("Could not open the knowledge library.")
        }
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA secure_delete=ON;")
            try execute("""
                CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY, title TEXT NOT NULL, location TEXT NOT NULL, digest TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY AUTOINCREMENT, document TEXT NOT NULL REFERENCES documents(id), offset INTEGER NOT NULL, body BLOB NOT NULL, bytes INTEGER NOT NULL, vector BLOB, embedding TEXT);
                CREATE INDEX IF NOT EXISTS chunk_document ON chunks(document);
                CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(title, body, content='', detail=none, tokenize='unicode61');
                PRAGMA user_version=1;
                """)
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func error() -> PocketError { .message("Knowledge database: \(String(cString: sqlite3_errmsg(db)))") }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return statement
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) { sqlite3_bind_text(statement, index, value, -1, transient) }
    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), transient) }
    }
    private func text(_ statement: OpaquePointer, _ index: Int32) -> String { String(cString: sqlite3_column_text(statement, index)) }
    private func data(_ statement: OpaquePointer, _ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    @discardableResult
    func importText(title: String, location: String, text content: String) throws -> Int {
        guard content.utf8.count <= 20_000_000 else { throw PocketError.message("A document can contain up to 20 MB of extracted text.") }
        let id = StableID.hash(location)
        let digest = StableID.hash(content)
        let existing = try prepare("SELECT digest FROM documents WHERE id=?")
        bind(id, to: existing, at: 1)
        let unchanged = sqlite3_step(existing) == SQLITE_ROW && text(existing, 0) == digest
        sqlite3_finalize(existing)
        if unchanged { return 0 }
        let chunks = TextChunker.chunks(content)
        guard !chunks.isEmpty else { throw PocketError.message("No readable text was found in this document.") }
        try execute("BEGIN IMMEDIATE")
        do {
            try deleteRows(id)
            let doc = try prepare("INSERT INTO documents VALUES(?,?,?,?)")
            defer { sqlite3_finalize(doc) }
            for (i, value) in [id, title, location, digest].enumerated() { bind(value, to: doc, at: Int32(i + 1)) }
            guard sqlite3_step(doc) == SQLITE_DONE else { throw error() }
            let chunk = try prepare("INSERT INTO chunks(document,offset,body,bytes,vector,embedding) VALUES(?,?,?,?,?,?)")
            let fts = try prepare("INSERT INTO search(rowid,title,body) VALUES(?,?,?)")
            defer { sqlite3_finalize(chunk); sqlite3_finalize(fts) }
            for passage in chunks {
                try Task.checkCancellation()
                sqlite3_reset(chunk); sqlite3_clear_bindings(chunk)
                bind(id, to: chunk, at: 1)
                sqlite3_bind_int64(chunk, 2, Int64(passage.offset))
                bind(CompactText.encode(passage.text), to: chunk, at: 3)
                sqlite3_bind_int64(chunk, 4, Int64(passage.text.utf8.count))
                if let vector = embedding?.vector(for: passage.text) {
                    bind(BinaryVector.encode(vector), to: chunk, at: 5)
                    bind(embeddingID, to: chunk, at: 6)
                }
                guard sqlite3_step(chunk) == SQLITE_DONE else { throw error() }
                let row = sqlite3_last_insert_rowid(db)
                sqlite3_reset(fts); sqlite3_clear_bindings(fts)
                sqlite3_bind_int64(fts, 1, row)
                bind(title, to: fts, at: 2); bind(passage.text, to: fts, at: 3)
                guard sqlite3_step(fts) == SQLITE_DONE else { throw error() }
            }
            try execute("COMMIT")
            return chunks.count
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func deleteRows(_ id: String) throws {
        let select = try prepare("SELECT c.id,d.title,c.body,c.bytes FROM chunks c JOIN documents d ON d.id=c.document WHERE d.id=?")
        defer { sqlite3_finalize(select) }
        bind(id, to: select, at: 1)
        let removeFTS = try prepare("INSERT INTO search(search,rowid,title,body) VALUES('delete',?,?,?)")
        defer { sqlite3_finalize(removeFTS) }
        while sqlite3_step(select) == SQLITE_ROW {
            sqlite3_reset(removeFTS); sqlite3_clear_bindings(removeFTS)
            sqlite3_bind_int64(removeFTS, 1, sqlite3_column_int64(select, 0))
            bind(text(select, 1), to: removeFTS, at: 2)
            bind(try CompactText.decode(data(select, 2), originalBytes: Int(sqlite3_column_int64(select, 3))), to: removeFTS, at: 3)
            guard sqlite3_step(removeFTS) == SQLITE_DONE else { throw error() }
        }
        for sql in ["DELETE FROM chunks WHERE document=?", "DELETE FROM documents WHERE id=?"] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bind(id, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
        }
    }

    func remove(id: String) throws {
        try execute("BEGIN IMMEDIATE")
        do { try deleteRows(id); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
        try execute("INSERT INTO search(search) VALUES('optimize'); PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }

    func documents() throws -> [KnowledgeDocument] {
        let statement = try prepare("SELECT d.id,d.title,d.location,count(c.id),coalesce(sum(length(c.body)+length(coalesce(c.vector,''))),0) FROM documents d LEFT JOIN chunks c ON c.document=d.id GROUP BY d.id ORDER BY d.title")
        defer { sqlite3_finalize(statement) }
        var result: [KnowledgeDocument] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(.init(id: text(statement, 0), title: text(statement, 1), location: text(statement, 2), passages: Int(sqlite3_column_int(statement, 3)), storedBytes: sqlite3_column_int64(statement, 4)))
        }
        return result
    }

    static func searchTerms(_ query: String) -> [String] {
        let stop = Set(["the", "a", "an", "is", "are", "was", "what", "why", "how", "does", "do", "of", "to", "and", "in", "for", "it", "me", "about", "answer", "briefly", "using", "sources", "source", "please", "tell", "explain", "could", "would", "should", "can", "you", "my", "from", "with", "this", "that", "these", "those"])
        let words = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) }
        return NSOrderedSet(array: Array(words.prefix(20))).array.compactMap { $0 as? String }
    }
    static func lexicalQuery(_ query: String) -> String {
        searchTerms(query).map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    func search(_ query: String, limit: Int = 6) throws -> [Citation] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var scores: [Int64: Double] = [:]
        let lexical = Self.lexicalQuery(query)
        if !lexical.isEmpty {
            let statement = try prepare("SELECT rowid FROM search WHERE search MATCH ? ORDER BY bm25(search,3.0,1.0) LIMIT 120")
            defer { sqlite3_finalize(statement) }
            bind(lexical, to: statement, at: 1)
            var rank = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                scores[sqlite3_column_int64(statement, 0)] = 1.0 / (1 + Double(rank) * 0.12)
                rank += 1
            }
        }
        if let vector = embedding?.vector(for: query) {
            let binary = BinaryVector.encode(vector)
            // Bound memory and runtime; larger libraries use lexical candidates for vector reranking.
            let countStmt = try prepare("SELECT count(*) FROM chunks")
            _ = sqlite3_step(countStmt)
            let count = sqlite3_column_int64(countStmt, 0)
            sqlite3_finalize(countStmt)
            let filter = count <= 20_000 ? "" : " AND id IN (\(scores.keys.map(String.init).joined(separator: ",")))"
            let statement = try prepare("SELECT id,vector FROM chunks WHERE embedding=?\(filter)")
            defer { sqlite3_finalize(statement) }
            bind(embeddingID, to: statement, at: 1)
            while sqlite3_step(statement) == SQLITE_ROW {
                try Task.checkCancellation()
                let similarity = BinaryVector.similarity(binary, data(statement, 1))
                if similarity > 0.57 {
                    scores[sqlite3_column_int64(statement, 0), default: 0] += (similarity - 0.5) * 2.0
                }
            }
        }
        var results: [Citation] = []
        let statement = try prepare("SELECT d.title,d.location,c.offset,c.body,c.bytes,c.document FROM chunks c JOIN documents d ON d.id=c.document WHERE c.id=?")
        defer { sqlite3_finalize(statement) }
        var perDoc: [String: Int] = [:]
        for (row, _) in scores.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }) {
            sqlite3_reset(statement); sqlite3_bind_int64(statement, 1, row)
            guard sqlite3_step(statement) == SQLITE_ROW else { continue }
            let document = text(statement, 5)
            guard perDoc[document, default: 0] < 3 else { continue }
            perDoc[document, default: 0] += 1
            let location = text(statement, 1)
            let offset = sqlite3_column_int64(statement, 2)
            let excerpt = try CompactText.decode(data(statement, 3), originalBytes: Int(sqlite3_column_int64(statement, 4)))
            results.append(Citation(id: "K" + String(StableID.hash("\(document):\(row)").prefix(8)), title: text(statement, 0), location: "\(location) · character \(offset)", excerpt: excerpt, sourceURL: location.hasPrefix("https://") ? location : nil))
            if results.count >= min(max(limit, 1), 20) { break }
        }
        return results
    }

    func semanticScore(query: String, passage: String) -> Double {
        guard let a = embedding?.vector(for: query), let b = embedding?.vector(for: passage) else { return 0 }
        return BinaryVector.similarity(BinaryVector.encode(a), BinaryVector.encode(b))
    }
}
