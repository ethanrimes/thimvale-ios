import Foundation

/// Reviewed recommendations, not a live leaderboard or an inference-speed promise.
/// The same snapshot ships as an Android asset; no network is required to see it.
struct ModelRecommendations: Decodable {
    struct Pick: Decodable, Identifiable {
        let id: String
        let modelID: String
        let title: String
        let reason: String
        let score: Double
        let reasoning: Bool
        let tokensPerSecond: Double
        let endToEndSeconds: Double
        let peakMemoryBytes: UInt64
        let benchmarkSlug: String
        let modelSourceURL: URL
    }
    let reviewedOn: String
    let sourceURL: URL
    let methodologyURL: URL
    let device: String
    let contextTokens: Int
    let prefillTokens: Int
    let outputTokens: Int
    let quantization: String
    let caveat: String
    let picks: [Pick]

    static let current: ModelRecommendations? = {
        guard let url = Bundle.main.url(forResource: "model-recommendations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()

    func defaultPick(memoryBytes: UInt64, models: [ModelEntry]) -> Pick? {
        // iOS reports slightly less than the marketed RAM class. Round upward
        // to GiB, never treat available/free memory as installed device memory.
        let memoryGB = Int(ceil(Double(memoryBytes) / 1_073_741_824))
        let preferred = memoryGB >= 6 ? "balanced" : "quick"
        return picks.first { $0.id == preferred }
            .flatMap { pick in models.contains(where: { $0.id == pick.modelID && $0.minimumMemoryGB <= memoryGB }) ? pick : nil }
            ?? picks.first { pick in models.contains { $0.id == pick.modelID && $0.minimumMemoryGB <= memoryGB } }
    }
}
