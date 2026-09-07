import Foundation

enum ModelCatalog {
    static let models: [ModelEntry] = [
        .init(id: "qwen35-08", name: "Qwen 3.5", family: "Qwen", repository: "unsloth/Qwen3.5-0.8B-GGUF", summary: "Qwen 3.5 at 0.8B parameters. Text mode.", parameters: "0.8B", minimumMemoryGB: 4),
        .init(id: "qwen35-2", name: "Qwen 3.5", family: "Qwen", repository: "unsloth/Qwen3.5-2B-GGUF", summary: "Qwen 3.5 at 2B parameters. Text mode.", parameters: "2B", minimumMemoryGB: 6),
        .init(id: "qwen3-06", name: "Qwen 3", family: "Qwen", repository: "Qwen/Qwen3-0.6B-GGUF", summary: "Lightweight multilingual chat.", parameters: "0.6B", minimumMemoryGB: 4),
        .init(id: "qwen3-17", name: "Qwen 3", family: "Qwen", repository: "Qwen/Qwen3-1.7B-GGUF", summary: "Multilingual text generation at 1.7B parameters.", parameters: "1.7B", minimumMemoryGB: 6),
        .init(id: "gemma3-1", name: "Gemma 3", family: "Gemma", repository: "ggml-org/gemma-3-1b-it-GGUF", summary: "Google's 1B instruction model.", parameters: "1B", minimumMemoryGB: 4),
        .init(id: "gemma4-e2", name: "Gemma 4", family: "Gemma", repository: "google/gemma-4-E2B-it-qat-q4_0-gguf", summary: "The E2B edition. Text mode; needs a higher-memory iPhone.", parameters: "E2B", minimumMemoryGB: 8, preferredQuant: "Q4_0"),
        .init(id: "liquid25-230", name: "Liquid LFM 2.5", family: "Liquid", repository: "LiquidAI/LFM2.5-230M-GGUF", summary: "230M-parameter text model from Liquid AI.", parameters: "230M", minimumMemoryGB: 4),
        .init(id: "liquid2-12", name: "Liquid LFM 2", family: "Liquid", repository: "LiquidAI/LFM2-1.2B-GGUF", summary: "Designed for efficient inference on edge devices.", parameters: "1.2B", minimumMemoryGB: 4),
        .init(id: "liquid25-26", name: "Liquid LFM 2.5", family: "Liquid", repository: "LiquidAI/LFM2.5-2.6B-GGUF", summary: "2.6B-parameter text model from Liquid AI.", parameters: "2.6B", minimumMemoryGB: 6),
        .init(id: "liquid-rag", name: "Liquid LFM 2 RAG", family: "Liquid", repository: "LiquidAI/LFM2-1.2B-RAG-GGUF", summary: "Specialized for answering from retrieved documents.", parameters: "1.2B", minimumMemoryGB: 4),
        .init(id: "granite4-micro", name: "Granite 4 Micro", family: "Granite", repository: "ibm-granite/granite-4.0-micro-GGUF", summary: "IBM's Granite 4.0 Micro instruction model.", parameters: "3B", minimumMemoryGB: 6),
        .init(id: "granite42-3", name: "Granite 4.2", family: "Granite", repository: "ibm-granite/granite-4.2-3b-GGUF", summary: "A recent small Granite model for text tasks.", parameters: "3B", minimumMemoryGB: 6),
        .init(id: "phi4-mini", name: "Phi 4 Mini", family: "Phi", repository: "unsloth/Phi-4-mini-instruct-GGUF", summary: "Microsoft's Phi 4 Mini instruction model.", parameters: "3.8B", minimumMemoryGB: 8),
        .init(id: "llama32-1", name: "Llama 3.2", family: "Llama", repository: "bartowski/Llama-3.2-1B-Instruct-GGUF", summary: "Meta's lightweight instruction model.", parameters: "1B", minimumMemoryGB: 4),
        .init(id: "llama32-3", name: "Llama 3.2", family: "Llama", repository: "bartowski/Llama-3.2-3B-Instruct-GGUF", summary: "Meta's 3B instruction model.", parameters: "3B", minimumMemoryGB: 6),
        .init(id: "smollm2-360", name: "SmolLM 2", family: "SmolLM", repository: "HuggingFaceTB/SmolLM2-360M-Instruct-GGUF", summary: "Hugging Face's 360M instruction model.", parameters: "360M", minimumMemoryGB: 4),
        .init(id: "smollm2-17", name: "SmolLM 2", family: "SmolLM", repository: "HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF", summary: "Hugging Face's 1.7B instruction model.", parameters: "1.7B", minimumMemoryGB: 4),
        .init(id: "ministral3", name: "Ministral 3", family: "Mistral", repository: "unsloth/Ministral-3-3B-Instruct-2512-GGUF", summary: "Mistral's small instruction model, in text mode.", parameters: "3B", minimumMemoryGB: 6)
    ]
}

actor ModelHub {
    struct Repository: Decodable { var id: String; var downloads: Int? }
    struct Detail: Decodable {
        struct File: Decodable {
            struct LFS: Decodable { var sha256: String?; var size: Int64? }
            var rfilename: String; var size: Int64?; var lfs: LFS?
        }
        struct Card: Decodable { var license: String? }
        var sha: String
        var siblings: [File]
        var cardData: Card?
    }
    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let token = Keychain.read("huggingface")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PocketError.message(status == 401 || status == 403 ? "This model needs a Hugging Face token and accepted license terms. Add your token in Settings." : "Hugging Face could not load this repository (HTTP \(status)).")
        }
        return data
    }
    func search(_ query: String) async throws -> [ModelEntry] {
        var url = URLComponents(string: "https://huggingface.co/api/models")!
        url.queryItems = [.init(name: "search", value: query), .init(name: "filter", value: "gguf"), .init(name: "sort", value: "downloads"), .init(name: "direction", value: "-1"), .init(name: "limit", value: "40")]
        let repositories = try JSONDecoder().decode([Repository].self, from: await get(url.url!))
        return repositories.map { .init(id: $0.id, name: $0.id.components(separatedBy: "/").last ?? $0.id, family: "Hugging Face", repository: $0.id, summary: $0.id, parameters: "GGUF", minimumMemoryGB: 0) }
    }
    func files(in repository: String) async throws -> ([HubFile], String?) {
        let parts = repository.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw PocketError.message("Enter a repository in owner/model format.") }
        var components = URLComponents(url: URL(string: "https://huggingface.co/api/models")!.appendingPathComponent(repository), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "blobs", value: "true")]
        let detail = try JSONDecoder().decode(Detail.self, from: await get(components.url!))
        let files = detail.siblings.filter {
            let name = $0.rfilename.lowercased()
            return name.hasSuffix(".gguf") && !name.contains("mmproj") && !name.contains("-of-") && !name.contains("mtp")
        }.map { HubFile(repository: repository, revision: detail.sha, path: $0.rfilename, bytes: $0.lfs?.size ?? $0.size ?? 0, sha256: $0.lfs?.sha256) }.sorted { $0.bytes < $1.bytes }
        guard !files.isEmpty else { throw PocketError.message("No single-file text GGUFs were found. Sharded weights, vision projectors, and safetensors are not supported.") }
        return (files, detail.cardData?.license)
    }
}
