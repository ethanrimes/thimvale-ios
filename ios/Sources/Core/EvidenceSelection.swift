import Foundation
import NaturalLanguage

/// Query-focused, verbatim windows. No generated summaries or source instructions are executed.
enum EvidenceSelection {
    struct Window { let text: String; let offset: Int; let relevance: Double }
    private struct RankedPassage {
        let citation: Citation
        let window: String
        let score: Double
        let rank: Int
    }

    static func window(_ text: String, query: String, maximum: Int = 700) -> Window {
        guard maximum > 0, !text.isEmpty else { return .init(text: "", offset: 0, relevance: 0) }
        let terms = Set(KnowledgeStore.searchTerms(query))
        guard !terms.isEmpty else { return .init(text: String(text.prefix(maximum)), offset: 0, relevance: 0) }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        guard !sentences.isEmpty else { return .init(text: String(text.prefix(maximum)), offset: 0, relevance: 0) }
        func score(_ range: Range<String.Index>) -> Double {
            let sentence = String(text[range])
            let words = Set(KnowledgeStore.searchTerms(sentence))
            let coverage = Double(terms.intersection(words).count) / Double(terms.count)
            // A repeated question is less useful evidence than a declarative sentence.
            // Adjacent context is retained below, so FAQ question/answer pairs stay readable.
            let questionWeight = sentence.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") ? 0.0 : 1.0
            return (coverage + coverage / sqrt(Double(max(words.count, 1)))) * questionWeight
        }
        let best = sentences.indices.max { left, right in
            let a = score(sentences[left]), b = score(sentences[right])
            return a == b ? left > right : a < b
        } ?? 0
        // Already-small passages need no further trimming. Their answer may use a
        // paraphrase ("taller" vs "height") that lexical sentence scoring cannot see.
        if text.count <= maximum {
            return .init(text: text, offset: 0, relevance: score(sentences[best]))
        }
        var lower = sentences[best].lowerBound
        var upper = sentences[best].upperBound
        // Bound the selected sentence too. Long unpunctuated text remains an exact slice.
        if text.distance(from: lower, to: upper) > maximum {
            let slice = String(text[lower..<upper])
            let chunks = TextChunker.chunks(slice, size: maximum, overlap: min(100, maximum / 4))
            let chosen = chunks.max { left, right in
                Set(KnowledgeStore.searchTerms(left.text)).intersection(terms).count < Set(KnowledgeStore.searchTerms(right.text)).intersection(terms).count
            }
            if let chosen {
                // TextChunker trims whitespace; resolve the actual substring to retain a precise offset.
                if let exact = text.range(of: chosen.text, range: lower..<upper) {
                    return .init(text: chosen.text, offset: text.distance(from: text.startIndex, to: exact.lowerBound), relevance: score(sentences[best]))
                }
            }
        }
        // Prefer the following sentence (often the answer to a heading/question), then the preceding one.
        if best + 1 < sentences.count, text.distance(from: lower, to: sentences[best + 1].upperBound) <= maximum {
            upper = sentences[best + 1].upperBound
        }
        if best > 0, text.distance(from: sentences[best - 1].lowerBound, to: upper) <= maximum {
            lower = sentences[best - 1].lowerBound
        }
        return .init(text: String(text[lower..<upper]), offset: text.distance(from: text.startIndex, to: lower), relevance: score(sentences[best]))
    }

    static func rerank(_ candidates: [Citation], query: String, limit: Int, semantic: (String) -> Double) -> [Citation] {
        let terms = Set(KnowledgeStore.searchTerms(query))
        var scored: [RankedPassage] = []
        for (index, citation) in candidates.enumerated() {
            let focused = window(citation.excerpt, query: query)
            let titleTerms = Set(KnowledgeStore.searchTerms(citation.title))
            let titleScore = Double(terms.intersection(titleTerms).count) / Double(max(terms.count, 1))
            var score = focused.relevance
            score += semantic(focused.text) * 0.65
            score += titleScore * 0.25
            score += 0.08 / Double(index + 1)
            scored.append(.init(citation: citation, window: focused.text, score: score, rank: index))
        }
        scored.sort { $0.score == $1.score ? $0.rank < $1.rank : $0.score > $1.score }
        var selected: [Citation] = []
        var seen = Set<String>()
        var perSource: [String: Int] = [:]
        for row in scored {
            let key = row.citation.sourceURL ?? (row.citation.id.hasPrefix("A") && row.citation.location.hasPrefix("Attachment · ")
                ? row.citation.id.components(separatedBy: ":")[0]
                : row.citation.location.components(separatedBy: " · character ")[0])
            let fingerprint = row.window.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            guard perSource[key, default: 0] < 2, seen.insert(key + ":" + fingerprint).inserted else { continue }
            selected.append(row.citation)
            perSource[key, default: 0] += 1
            if selected.count >= max(1, limit) { break }
        }
        return selected
    }
}
