import XCTest
@testable import Thimvale

final class PromptCacheTests: XCTestCase {
    private var model: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/smoke-model.gguf").path
    }
    func testCacheMatchesFreshAfterContinuationEditsCancellationAndReload() throws {
        guard FileManager.default.fileExists(atPath: model) else { throw XCTSkip("Fetch the real inference fixture first.") }
        let cached = PMInference(), fresh = PMInference()
        fresh.reusePromptCache = false
        try cached.loadModel(atPath: model, contextSize: 1024)
        try fresh.loadModel(atPath: model, contextSize: 1024)
        defer { cached.unload(); fresh.unload() }
        let first = [["role": "system", "content": "Answer in one short sentence."],
                     ["role": "user", "content": "The Finch label is amber. What color is the label?"]]
        func generate(_ engine: PMInference, _ messages: [[String: String]]) throws -> String {
            engine.resetCancellation()
            return try engine.generateMessages(messages, maxTokens: 12, temperature: 0) { _ in }
        }
        let answer = try generate(cached, first)
        let followup = first + [["role": "assistant", "content": answer], ["role": "user", "content": "What was the label color?"]]
        let warm = try generate(cached, followup)
        XCTAssertGreaterThan(cached.generationStatistics["reusedTokens"]?.intValue ?? 0, 0)
        XCTAssertEqual(warm, try generate(fresh, followup))
        // Repeated/shortened prompts require rollback; hybrid models may safely fall back to a full prefill.
        XCTAssertEqual(try generate(cached, first), try generate(fresh, first))
        let edited = [["role": "system", "content": "Answer in one short sentence."],
                      ["role": "user", "content": "The Finch label is violet. What color is the label?"]]
        XCTAssertEqual(try generate(cached, edited), try generate(fresh, edited))
        let oversized = [["role": "user", "content": String(repeating: "A long record. ", count: 1500)]]
        XCTAssertThrowsError(try generate(cached, oversized))
        XCTAssertTrue(cached.generationStatistics.isEmpty)
        XCTAssertEqual(try generate(cached, edited), try generate(fresh, edited))
        cached.resetCancellation()
        XCTAssertThrowsError(try cached.generateMessages(first, maxTokens: 40, temperature: 0) { _ in cached.cancel() })
        XCTAssertTrue(cached.generationStatistics.isEmpty)
        XCTAssertEqual(try generate(cached, edited), try generate(fresh, edited))
        cached.unload()
        XCTAssertTrue(cached.generationStatistics.isEmpty)
        try cached.loadModel(atPath: model, contextSize: 1024)
        XCTAssertEqual(try generate(cached, edited), try generate(fresh, edited))
        XCTAssertEqual(cached.generationStatistics["reusedTokens"]?.intValue, 0)
    }
}
