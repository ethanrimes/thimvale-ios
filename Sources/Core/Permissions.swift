import Foundation

enum ToolName: String, Codable, CaseIterable, Identifiable, Sendable {
    case searchKnowledge = "search_knowledge"
    case listFiles = "list_files"
    case readFile = "read_file"
    case writeFile = "write_file"
    case webSearch = "web_search"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .searchKnowledge: "Search knowledge"
        case .listFiles: "List files"
        case .readFile: "Read files"
        case .writeFile: "Create files"
        case .webSearch: "Search the web"
        }
    }
    var subtitle: String {
        switch self {
        case .searchKnowledge: "Find and cite passages in your offline library."
        case .listFiles: "See filenames in folders you connect."
        case .readFile: "Open text in your connected folders."
        case .writeFile: "Create new text files. Existing files are never replaced."
        case .webSearch: "Send a search query to Brave. Requires your API key and internet."
        }
    }
    var symbol: String {
        switch self {
        case .searchKnowledge: "books.vertical"
        case .listFiles: "folder"
        case .readFile: "doc.text"
        case .writeFile: "square.and.pencil"
        case .webSearch: "globe"
        }
    }
}

enum PermissionLevel: String, Codable, CaseIterable, Identifiable {
    case deny = "Off", ask = "Ask", allow = "Allow"
    var id: String { rawValue }
}

struct PermissionPolicy: Codable {
    var levels: [ToolName: PermissionLevel] = [
        .searchKnowledge: .allow, .listFiles: .ask, .readFile: .ask, .writeFile: .ask, .webSearch: .deny
    ]
    subscript(_ tool: ToolName) -> PermissionLevel {
        get { levels[tool] ?? .deny }
        set { levels[tool] = newValue }
    }
    func requiresApproval(for tool: ToolName, mode: ConversationMode) throws -> Bool {
        guard mode == .work else { throw PocketError.message("Tools are unavailable in Chat mode.") }
        guard self[tool] != .deny else { throw PocketError.message("\(tool.title) is turned off.") }
        return self[tool] == .ask
    }
}

struct ToolCall: Codable, Equatable, Sendable {
    var tool: ToolName
    var query: String?
    var folder: String?
    var path: String?
    var content: String?
    var offset: Int?

    var preview: String {
        switch tool {
        case .searchKnowledge, .webSearch: query ?? ""
        case .listFiles: "Folder: \(folder ?? "")\nPath: \(path ?? ".")"
        case .readFile: "Folder: \(folder ?? "")\nFile: \(path ?? "")\nOffset: \(offset ?? 0)"
        case .writeFile: "Folder: \(folder ?? "")\nNew file: \(path ?? "")\n\n\(content ?? "")"
        }
    }

    /// Accept a single, explicit action, never JSON embedded in prose or retrieved text.
    static func parse(_ output: String) -> ToolCall? {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "</think>", options: .backwards) {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("```json\n"), text.hasSuffix("```") { text = String(text.dropFirst(8).dropLast(3)) }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { return nil }
        return try? JSONDecoder().decode(ToolCall.self, from: Data(text.utf8))
    }

    /// Detect unsupported call syntax for recovery, never for execution.
    static func looksLikeCall(_ output: String) -> Bool {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = text.range(of: "</think>", options: .backwards) { text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if text.hasPrefix("```"), let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if text.hasPrefix("<tool_call>") || text.hasPrefix("<|tool_call") { return true }
        let namedTool = text.contains("\"name\"") && ToolName.allCases.contains { text.contains("\"" + $0.rawValue + "\"") }
        if text.hasPrefix("{"), text.contains("\"tool\"") || namedTool { return true }
        if text.hasPrefix("[") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        return ToolName.allCases.contains { text.hasPrefix($0.rawValue + "(") }
    }
}

struct AgentBudget {
    let maximumCalls: Int
    private(set) var calls = 0
    private var repeated: [String: Int] = [:]
    init(maximumCalls: Int = 6) { self.maximumCalls = maximumCalls }
    mutating func consume(_ call: ToolCall) throws {
        guard calls < maximumCalls else { throw PocketError.message("Work stopped after \(maximumCalls) tool calls. Ask a follow-up to continue.") }
        let key = "\(call.tool.rawValue):\(call.preview)"
        guard repeated[key, default: 0] < 2 else { throw PocketError.message("Work stopped because the model repeated the same action.") }
        repeated[key, default: 0] += 1
        calls += 1
    }
}
