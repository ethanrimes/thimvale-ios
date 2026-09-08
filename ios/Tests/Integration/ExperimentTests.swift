import XCTest
@testable import Thimvale

/// Opt-in measurements, separate from release gates. Run the ThimvaleExperiments scheme.
/// All documents are synthetic, and model execution is real inside the iOS simulator.
final class ExperimentTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func enabled() throws {
        guard ProcessInfo.processInfo.environment["THIMVALE_EXPERIMENTS"] == "1" else {
            throw XCTSkip("Opt-in experiment: use the ThimvaleExperiments scheme.")
        }
    }
    private func record(_ row: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print("THIMVALE_EXPERIMENT " + String(decoding: data, as: UTF8.self))
    }
    func testInferenceMatrix() throws {
        try enabled()
        let models = [("lfm25-230m-q4", "smoke-model.gguf"), ("qwen3-06-q8", "experiments/qwen3-06-q8.gguf"), ("gemma3-1b-q4", "experiments/gemma3-1b-q4.gguf")]
        let context = (1...32).map { "Record \($0): the North Pier project uses a copper marker and a numbered notebook." }.joined(separator: "\n")
        let messages = [["role": "system", "content": "Follow the user's request. Be precise."],
                        ["role": "user", "content": context + "\nList twenty practical steps for organizing these project records. Use a numbered list."]]
        for (name, file) in models {
            let path = root.appendingPathComponent("Vendor/" + file).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Run scripts/fetch-experiment-assets.sh")
            for threads in [2, 4, 6] {
                let engine = PMInference()
                engine.threadCount = Int32(threads)
                engine.reusePromptCache = false // Isolate raw prefill/decode throughput from prompt reuse.
                try engine.loadModel(atPath: path, contextSize: 4096)
                defer { engine.unload() }
                for repetition in 0..<3 {
                    var streamed = ""
                    let output = try engine.generateMessages(messages, maxTokens: 96, temperature: 0.6) { streamed += $0 }
                    XCTAssertEqual(output, streamed)
                    XCTAssertFalse(output.isEmpty)
                    var row: [String: Any] = engine.generationStatistics
                    row.merge(["kind": "inference", "model": name, "threads": threads, "repetition": repetition,
                               "thermal": ProcessInfo.processInfo.thermalState.rawValue, "simulator": true]) { _, new in new }
                    try record(row)
                }
            }
        }
    }

    struct Probe {
        let id: String
        let question: String
        let answer: String
        let title: String
        let body: String
    }
    // Fixed reporting partitions. This hand-built stress set is inspected during tuning,
    // not an independent blind test of general model intelligence.
    static let probes: [Probe] = [
        .init(id: "01", question: "What is the Cedar observatory access code?", answer: "CEDAR-7419", title: "Cedar observatory", body: "The Cedar observatory access code is CEDAR-7419. The previous code no longer works."),
        .init(id: "02", question: "How many spare lanterns are stored at Alder station?", answer: "seventeen", title: "Alder station inventory", body: "Alder station stores seventeen spare lanterns in the east cabinet."),
        .init(id: "03", question: "Which platform does the Juniper shuttle leave from?", answer: "platform nine", title: "Juniper shuttle", body: "The Juniper shuttle leaves from platform nine. The Willow shuttle uses platform two."),
        .init(id: "04", question: "Who is responsible for the Marigold archive keys?", answer: "Nora Finch", title: "Marigold archive", body: "Nora Finch is the custodian responsible for the Marigold archive keys."),
        .init(id: "05", question: "At what temperature should the Saffron calibration sample be stored?", answer: "14 degrees", title: "Saffron calibration notes", body: "Store the Saffron calibration sample at 14 degrees Celsius. This is a fictional engineering sample, not food or medicine."),
        .init(id: "06", question: "What color marks the approved Kestrel cable?", answer: "violet", title: "Kestrel cable marking", body: "The approved Kestrel cable is marked violet. Orange markings identify rejected cables."),
        .init(id: "07", question: "What is the maximum height for a crate in the Rowan lift?", answer: "142 centimetres", title: "Rowan lift", body: "Crates in the Rowan lift must be no taller than 142 centimetres."),
        .init(id: "08", question: "On which weekday is the Bracken workshop closed?", answer: "Tuesday", title: "Bracken workshop", body: "The Bracken workshop is closed every Tuesday and open on the other six weekdays."),
        .init(id: "09", question: "What is the file extension for a saved Larkspur drawing?", answer: ".lspx", title: "Larkspur drawing format", body: "Saved Larkspur drawings use the .lspx file extension. A .bak file is only a backup."),
        .init(id: "10", question: "Where is the backup key for the Tern boathouse?", answer: "blue tin", title: "Tern boathouse key", body: "The Tern boathouse backup key is kept in the blue tin below the workbench.")
    ]
    static func populatedStore(at url: URL) throws -> KnowledgeStore {
        let store = try KnowledgeStore(url: url)
        for probe in probes {
            // Answer-bearing text appears late in a long document, amid similar project vocabulary.
            let preface = String(repeating: "This handbook describes \(probe.title) and its records. The introduction covers labels, record keeping, and routine inspections. ", count: 18)
            try store.importText(title: probe.title, location: "fixture/\(probe.id).txt", text: preface + "\n\nVerified detail\n" + probe.body)
            try store.importText(title: probe.title + " historical discussion", location: "fixture/\(probe.id)-distractor.txt", text: String(repeating: probe.question + " The planning discussion did not establish this detail. ", count: 7))
        }
        return store
    }
    func testRetrievalMatrix() throws {
        try enabled()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Self.populatedStore(at: folder.appendingPathComponent("experiments.sqlite"))
        for probe in Self.probes {
          for refined in [false, true] {
            let start = Date()
            let results = try store.search(probe.question, limit: 6, refine: refined)
            let rank = results.firstIndex { $0.excerpt.contains(probe.answer) }.map { $0 + 1 } ?? 0
            // Measure the text actually sent to the model, including the current per-source cap.
            let evidenceHit = results.prefix(6).contains { (refined ? EvidenceSelection.window($0.excerpt, query: probe.question).text : String($0.excerpt.prefix(1100))).contains(probe.answer) }
            let answerSources = results.enumerated().filter { $0.element.excerpt.contains(probe.answer) }.map { String($0.offset + 1) }
            try record(["kind": "retrieval", "variant": refined ? "refined" : "legacy", "id": probe.id, "split": Int(probe.id)! % 2 == 0 ? "even" : "odd",
                        "rank": rank, "evidenceHit": evidenceHit, "semantic": store.hasSemanticSearch,
                        "elapsedMS": Date().timeIntervalSince(start) * 1000,
                        "answerSourceIDs": answerSources, "titles": results.map(\.title)])
          }
        }
        let archive = try PMArchive(path: root.appendingPathComponent("Vendor/smoke-wikipedia.zim").path)
        for query in ["bowline", "How does a sheet bend join ropes of different thicknesses?", "What distinguishes a reef knot from a granny knot?"] {
            let terms = KnowledgeStore.searchTerms(query)
            let start = Date()
            let rows = try archive.search(terms.joined(separator: " "), limit: 6)
            try record(["kind": "wikipedia-discovery", "query": query, "titles": rows.compactMap { $0["title"] }, "elapsedMS": Date().timeIntervalSince(start) * 1000])
            let improvedStart = Date()
            let improved = try WikipediaDiscovery.articles(in: archive, query: query)
            try record(["kind": "wikipedia-title-aware", "query": query, "titles": improved.compactMap { $0["title"] }, "elapsedMS": Date().timeIntervalSince(improvedStart) * 1000])
        }
    }

    func testPromptCacheMatrix() throws {
        try enabled()
        let context = (1...32).map { "Record \($0): the North Pier project uses a copper marker and a numbered notebook." }.joined(separator: "\n")
        let first = [["role": "system", "content": "Answer briefly."], ["role": "user", "content": context + "\nWhat marker does the project use?"]]
        for (name, file) in [("lfm25-230m-q4", "smoke-model.gguf"), ("qwen3-06-q8", "experiments/qwen3-06-q8.gguf"), ("gemma3-1b-q4", "experiments/gemma3-1b-q4.gguf")] {
            let engine = PMInference()
            try engine.loadModel(atPath: root.appendingPathComponent("Vendor/" + file).path, contextSize: 4096)
            defer { engine.unload() }
            engine.reusePromptCache = false
            let answer = try engine.generateMessages(first, maxTokens: 24, temperature: 0) { _ in }
            let followup = first + [["role": "assistant", "content": answer], ["role": "user", "content": "What is written about the notebook? Answer in one sentence."]]
            for repetition in 0..<3 {
                // Alternate order to reduce first/second-run bias.
                var outputs: [String] = []
                for cached in (repetition % 2 == 0 ? [true, false] : [false, true]) {
                    if cached {
                        engine.reusePromptCache = false
                        _ = try engine.generateMessages(first, maxTokens: 24, temperature: 0) { _ in }
                    }
                    engine.reusePromptCache = cached
                    let output = try engine.generateMessages(followup, maxTokens: 32, temperature: 0) { _ in }
                    outputs.append(output)
                    var row: [String: Any] = engine.generationStatistics
                    row.merge(["kind": "prompt-cache", "model": name, "cached": cached, "repetition": repetition, "thermal": ProcessInfo.processInfo.thermalState.rawValue]) { _, new in new }
                    try record(row)
                }
                XCTAssertEqual(outputs[0], outputs[1], "Cached and fresh greedy continuations must agree: \(name)")
            }
        }
    }

    func testPrefillBatchMatrix() throws {
        try enabled()
        let context = (1...32).map { "Record \($0): the North Pier project uses a copper marker and a numbered notebook." }.joined(separator: "\n")
        let messages = [["role": "system", "content": "Follow the user's request. Be precise."],
                        ["role": "user", "content": context + "\nList twenty practical steps for organizing these project records. Use a numbered list."]]
        for (name, file) in [("lfm25-230m-q4", "smoke-model.gguf"), ("qwen3-06-q8", "experiments/qwen3-06-q8.gguf"), ("gemma3-1b-q4", "experiments/gemma3-1b-q4.gguf")] {
            for (batch, micro) in [(256, 128), (512, 256)] {
                let engine = PMInference()
                engine.reusePromptCache = false
                engine.threadCount = 6
                engine.batchSize = Int32(batch); engine.microBatchSize = Int32(micro)
                try engine.loadModel(atPath: root.appendingPathComponent("Vendor/" + file).path, contextSize: 4096)
                defer { engine.unload() }
                for repetition in 0..<3 {
                    _ = try engine.generateMessages(messages, maxTokens: 96, temperature: 0.6) { _ in }
                    var row: [String: Any] = engine.generationStatistics
                    row.merge(["kind": "prefill-batch", "model": name, "batch": batch, "micro": micro, "repetition": repetition, "thermal": ProcessInfo.processInfo.thermalState.rawValue]) { _, new in new }
                    try record(row)
                }
            }
        }
    }

    func testGroundedAnswerMatrix() throws {
        try enabled()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Self.populatedStore(at: folder.appendingPathComponent("answers.sqlite"))
        for (name, file) in [("lfm25-230m-q4", "smoke-model.gguf"), ("qwen3-06-q8", "experiments/qwen3-06-q8.gguf"), ("gemma3-1b-q4", "experiments/gemma3-1b-q4.gguf")] {
            let engine = PMInference()
            try engine.loadModel(atPath: root.appendingPathComponent("Vendor/" + file).path, contextSize: 4096)
            defer { engine.unload() }
            for probe in Self.probes {
                var registry = CitationRegistry()
                let citations = registry.register(try store.search(probe.question, limit: 6))
                let prompt = EvidencePrompt.messages(question: probe.question, citations: citations).map { ["role": $0.role, "content": $0.content] }
                let output = try engine.generateMessages(prompt, maxTokens: 96, temperature: 0.6) { _ in }
                let cited = CitationValidator.cited(in: output, from: citations)
                try record(["kind": "answer", "model": name, "id": probe.id,
                            "correct": output.localizedCaseInsensitiveContains(probe.answer),
                            "supportedCitation": cited.contains { $0.excerpt.contains(probe.answer) },
                            "output": output, "metrics": engine.generationStatistics])
            }
            let missing = EvidencePrompt.messages(question: "What is the unlock code for the Pelican depot?", citations: []).map { ["role": $0.role, "content": $0.content] }
            let output = try engine.generateMessages(missing, maxTokens: 96, temperature: 0.6) { _ in }
            try record(["kind": "unanswerable", "model": name, "output": output, "metrics": engine.generationStatistics])
            for question in ["What is the unlock code for the Pelican depot?", "What is the purchase price of the Alder station lanterns?"] {
                var registry = CitationRegistry()
                let citations = registry.register(try store.search(question, limit: 6))
                let prompt = EvidencePrompt.messages(question: question, citations: citations).map { ["role": $0.role, "content": $0.content] }
                let answer = try engine.generateMessages(prompt, maxTokens: 96, temperature: 0.6) { _ in }
                try record(["kind": "unanswerable-with-distractors", "model": name, "question": question, "output": answer, "metrics": engine.generationStatistics])
            }
        }
    }

    func testImportedFileAnswerMatrix() async throws {
        try enabled()
        let folder = try LocalFileFixture.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appendingPathComponent("knowledge.sqlite")
        let importer = try KnowledgeService(storeURL: database)
        let report = try await importer.importURL(folder.appendingPathComponent("Library")) { _ in }
        XCTAssertEqual(report, "Indexed 7 files.")
        let service = try KnowledgeService(storeURL: database)
        var questions = LocalFileFixture.probes.map { ($0.question, [$0.answer]) }
        questions.append(("What are the Aster cabinet access code and the Gorse annex gate code?", ["ASTER-6382", "GORSE-2846"]))
        questions.append(("What is the purchase price of the Cobalt survey notebook?", []))
        for (name, file) in [("lfm25-230m-q4", "smoke-model.gguf"), ("qwen3-06-q8", "experiments/qwen3-06-q8.gguf"), ("gemma3-1b-q4", "experiments/gemma3-1b-q4.gguf")] {
            let engine = PMInference()
            try engine.loadModel(atPath: root.appendingPathComponent("Vendor/" + file).path, contextSize: 4096)
            defer { engine.unload() }
            for (question, expected) in questions {
                var registry = CitationRegistry()
                let citations = registry.register(try await service.search(question, archiveFiles: []))
                let evidence = EvidencePrompt.render(citations, question: question)
                XCTAssertTrue(expected.allSatisfy { evidence.contains($0) }, "Imported evidence missing for \(question)")
                let prompt = EvidencePrompt.messages(question: question, citations: citations).map { ["role": $0.role, "content": $0.content] }
                var streamed = ""
                let output = try engine.generateMessages(prompt, maxTokens: 96, temperature: 0.6) { streamed += $0 }
                XCTAssertEqual(streamed, output)
                let cited = CitationValidator.cited(in: output, from: citations)
                // Synthetic-only logs. Locations are relative fixture paths, never customer paths.
                try record(["kind": "imported-file-answer", "model": name, "question": question,
                            "expected": expected, "expectedPhrasesPresent": expected.filter { output.localizedCaseInsensitiveContains($0) }.count,
                            "supportingSourcesCited": expected.filter { fact in cited.contains { $0.excerpt.contains(fact) } }.count,
                            "sources": citations.map { ["id": $0.id, "file": $0.location.replacingOccurrences(of: folder.path + "/", with: "")] },
                            "output": output, "metrics": engine.generationStatistics])
            }
        }
    }

    func testEditedPromptCacheEquivalenceAcrossModels() throws {
        try enabled()
        for (name, file) in [("lfm25-230m-q4", "smoke-model.gguf"), ("qwen3-06-q8", "experiments/qwen3-06-q8.gguf"), ("gemma3-1b-q4", "experiments/gemma3-1b-q4.gguf")] {
            let cached = PMInference(), fresh = PMInference()
            fresh.reusePromptCache = false
            let path = root.appendingPathComponent("Vendor/" + file).path
            try cached.loadModel(atPath: path, contextSize: 1024)
            try fresh.loadModel(atPath: path, contextSize: 1024)
            defer { cached.unload(); fresh.unload() }
            for color in ["amber", "violet", "violet", "blue"] {
                let messages = [["role": "system", "content": "Answer briefly."], ["role": "user", "content": "The Finch label is \(color). What color is the label?"]]
                let warm = try cached.generateMessages(messages, maxTokens: 24, temperature: 0) { _ in }
                let cold = try fresh.generateMessages(messages, maxTokens: 24, temperature: 0) { _ in }
                XCTAssertEqual(warm, cold, "Edited/repeated greedy prompts must agree: \(name), \(color)")
            }
        }
    }
}
