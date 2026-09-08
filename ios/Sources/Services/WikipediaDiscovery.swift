import Foundation
import SwiftSoup

/// Metadata-only candidate expansion before decompression. Bounded, offline, and title-aware.
enum WikipediaDiscovery {
    private struct RankedArticle {
        let row: [String: String]
        let score: Double
        let rank: Int
    }
    static func articles(in archive: PMArchive, query: String, limit: Int = 6) throws -> [[String: String]] {
        let terms = KnowledgeStore.searchTerms(String(query.prefix(500)))
        let ordered = KnowledgeStore.queryTokens(String(query.prefix(500)))
        guard !terms.isEmpty else { return [] }
        var queries = [terms.joined(separator: " ")]
        if ordered.count > 1 {
            for index in 0..<min(ordered.count - 1, 8) {
                queries.append("\"" + ordered[index...index + 1].joined(separator: " ") + "\"")
            }
        }
        // Single-keyword fallback remains useful for niche names with no phrase matches.
        queries += terms.prefix(3)
        var seen = Set<String>()
        var candidates: [[String: String]] = []
        for variant in NSOrderedSet(array: queries).array.compactMap({ $0 as? String }) {
            try Task.checkCancellation()
            for row in try archive.browse(variant, offset: 0, limit: 12) {
                guard let path = row["path"], seen.insert(path).inserted else { continue }
                candidates.append(row)
            }
        }
        let queryWords = Set(terms)
        let normalized = " " + query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        let snippetWords = try candidates.map { row in
            Set(KnowledgeStore.searchTerms(try SwiftSoup.parse(row["snippet"] ?? "").text()))
        }
        // A descriptive query may name no article at all. Reward distinctive
        // words in search snippets instead of allowing generic one-word titles
        // to crowd out relevant body matches. No full articles are read here.
        let weights = Dictionary(uniqueKeysWithValues: terms.map { term in
            (term, log(1 + Double(candidates.count + 1) / Double(1 + snippetWords.filter { $0.contains(term) }.count)))
        })
        let totalWeight = max(weights.values.reduce(0, +), 1)
        var ranked: [RankedArticle] = []
        for (index, row) in candidates.enumerated() {
            let title = row["title"] ?? ""
            let titleTerms = KnowledgeStore.searchTerms(title)
            let overlap = Double(queryWords.intersection(titleTerms).count)
            let exact = title.lowercased() == terms.joined(separator: " ")
            let phrase = normalized.contains(" " + titleTerms.joined(separator: " ") + " ")
            let titleBonus: Double = exact ? 5.0 : phrase && titleTerms.count > 1 ? 1.0 : 0.0
            var score = 1.2 * overlap / Double(max(queryWords.count, 1))
            let snippetScore = queryWords.intersection(snippetWords[index]).reduce(0.0) { $0 + (weights[$1] ?? 0) } / totalWeight
            score += snippetScore * 2
            score += titleBonus
            score += 0.2 / Double(index + 1)
            ranked.append(.init(row: row, score: score, rank: index))
        }
        ranked.sort { $0.score == $1.score ? $0.rank < $1.rank : $0.score > $1.score }
        let resultLimit = min(max(limit, 1), 12)
        // Preserve leading full-text hits as well. Descriptive questions can match
        // an article's body without sharing any words with its title.
        let lexicalLeaders = candidates.prefix(2).map { RankedArticle(row: $0, score: 0, rank: 0) }
        let prioritized = Array(ranked.prefix(max(2, resultLimit - 2))) + lexicalLeaders + ranked
        var articles: [[String: String]] = []
        var firstError: Error?
        var attempted = Set<String>()
        for candidate in prioritized {
            try Task.checkCancellation()
            guard let path = candidate.row["path"], attempted.insert(path).inserted else { continue }
            do { articles.append(try archive.article(atPath: candidate.row["path"]!)) }
            catch { if firstError == nil { firstError = error } }
            if articles.count >= resultLimit || attempted.count >= 12 { break }
        }
        if articles.isEmpty, let firstError { throw firstError }
        return articles
    }
}
