import Foundation

protocol InferenceServing: AnyObject, Sendable {
    func load(model: URL) async throws
    func generate(model: URL, messages: [ChatMessage], maxTokens: Int, onToken: @escaping @Sendable (String) -> Void) async throws -> String
    func cancel()
    func unload()
}

final class InferenceService: InferenceServing, @unchecked Sendable {
    private let engine = PMInference()
    private let queue = DispatchQueue(label: "com.ethanrimes.pocketmind.inference", qos: .userInitiated)
    private let lock = NSLock()
    // The queue owns model/context state. The lock owns cancellation only.
    private var loadedPath: String?
    private var loads = 0
    private var epoch = 0
    private var activeOperation: UUID?

    private final class Operation: @unchecked Sendable {
        let id = UUID()
        var cancelled = false // Protected by the service lock.
    }

    func cancel() {
        lock.withLock { epoch += 1; engine.cancel() }
    }
    func unload() {
        lock.withLock {
            epoch += 1; engine.cancel()
            queue.async { self.engine.unload(); self.loadedPath = nil }
        }
    }
    private func ensureLoaded(_ model: URL) throws {
        guard loadedPath != model.path else { return }
        // Native loading releases the previous model even if the replacement fails.
        loadedPath = nil
        do {
            try engine.loadModel(atPath: model.path, contextSize: 4096)
            loadedPath = model.path
            loads += 1
        } catch { engine.unload(); throw error }
    }
    func load(model: URL) async throws {
        try await perform { try self.ensureLoaded(model) }
    }
    func generate(model: URL, messages: [ChatMessage], maxTokens: Int = 768, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        try await perform {
            try self.ensureLoaded(model)
            let payload = messages.map { ["role": $0.role, "content": $0.content] }
            return try self.engine.generateMessages(payload, maxTokens: Int32(maxTokens), temperature: 0.6, onToken: onToken)
        }
    }
    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        let operation = Operation()
        let ticket = lock.withLock { epoch }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let canStart = self.lock.withLock {
                        guard !operation.cancelled, ticket == self.epoch else { return false }
                        self.activeOperation = operation.id
                        self.engine.resetCancellation()
                        return true
                    }
                    guard canStart else { continuation.resume(throwing: CancellationError()); return }
                    defer { self.lock.withLock { self.activeOperation = nil } }
                    do {
                        let output = try work()
                        guard self.lock.withLock({ !operation.cancelled && ticket == self.epoch }) else { throw CancellationError() }
                        continuation.resume(returning: output)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            self.lock.withLock {
                operation.cancelled = true
                // A late cancellation from an old request must not stop its successor.
                if self.activeOperation == operation.id { self.engine.cancel() }
            }
        }
    }
    /// Queue-consistent diagnostics; never includes prompts or generated text.
    func residency() async -> (path: String?, loads: Int) {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: (self.loadedPath, self.loads)) }
        }
    }
}

enum WebSearchService {
    struct Response: Decodable {
        struct Web: Decodable {
            struct Result: Decodable { var title: String; var url: String; var description: String; var extra_snippets: [String]? }
            var results: [Result]
        }
        var web: Web?
    }
    static func search(_ query: String) async throws -> [Citation] {
        let key = Keychain.read("brave")
        guard !key.isEmpty else { throw PocketError.message("Add your Brave Search API key in Settings to enable web search.") }
        guard !query.isEmpty, query.count <= 400 else { throw PocketError.message("Web queries must be between 1 and 400 characters.") }
        var url = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        url.queryItems = [.init(name: "q", value: query), .init(name: "count", value: "5"), .init(name: "extra_snippets", value: "true")]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 25
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PocketError.message("Web search failed. Check your internet connection, API key, and Brave quota.") }
        let result = try JSONDecoder().decode(Response.self, from: data)
        return try (result.web?.results ?? []).map { item in
            let excerpt = try KnowledgeService.plainText(([item.description] + (item.extra_snippets ?? [])).joined(separator: "\n"))
            return Citation(id: "S" + String(StableID.hash(item.url).prefix(8)), title: item.title, location: "Web search excerpt · \(item.url)", excerpt: String(excerpt.prefix(1_200)), sourceURL: item.url)
        }
    }
}
