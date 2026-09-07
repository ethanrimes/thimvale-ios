import Foundation

final class InferenceService: @unchecked Sendable {
    private let engine = PMInference()
    private let queue = DispatchQueue(label: "com.ethanrimes.pocketmind.inference", qos: .userInitiated)
    private var loadedPath: String?
    func cancel() { engine.cancel() }
    func prepare() { engine.resetCancellation() }
    func unload() { queue.async { self.engine.unload(); self.loadedPath = nil } }
    func generate(model: URL, messages: [ChatMessage], maxTokens: Int = 768, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        if self.loadedPath != model.path {
                            try self.engine.loadModel(atPath: model.path, contextSize: 4096)
                            self.loadedPath = model.path
                        }
                        let payload = messages.map { ["role": $0.role, "content": $0.content] }
                        let output = try self.engine.generateMessages(payload, maxTokens: Int32(maxTokens), temperature: 0.6, onToken: onToken)
                        continuation.resume(returning: output)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.engine.cancel() }
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
