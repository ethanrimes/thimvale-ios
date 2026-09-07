import SwiftUI
import UniformTypeIdentifiers

struct PermissionsView: View {
    @Bindable var state: AppState
    @State private var folderPicker = false
    @State private var settings = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Work mode")
                        Text("Tool permissions").font(.system(size: 34, design: .serif)).tracking(-1)
                        Text("Choose which tools models can use in Work mode.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    Card {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "hand.raised").font(.title2).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 6) { Text("Only in Work mode").font(.subheadline.weight(.semibold)); Text("Chat has no tools. In Work, Off blocks a tool, Ask shows each proposed action, and Allow grants access without a prompt.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(3) }
                        }
                    }
                    ForEach(ToolName.allCases) { tool in
                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: tool.symbol).frame(width: 23).foregroundStyle(Palette.accent)
                                    VStack(alignment: .leading, spacing: 5) { Text(tool.title).font(.subheadline.weight(.semibold)); Text(tool.subtitle).font(.caption).foregroundStyle(Palette.muted).lineSpacing(2) }
                                }
                                Picker(tool.title + " permission", selection: Binding(get: { state.policy[tool] }, set: { state.policy[tool] = $0; state.save() })) {
                                    ForEach(PermissionLevel.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented).accessibilityIdentifier("permission_\(tool.rawValue)")
                            }
                        }
                    }
                    SectionHeading(title: "Connected folders", detail: "\(state.folders.count)")
                    Text("Tools can access only these folders. Connecting a folder doesn't index it; import it in Knowledge for retrieval. Revoking access here doesn't erase previously indexed copies.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                    ForEach(state.folders) { folder in
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) { Text(folder.name).font(.subheadline); Text(folder.isExports ? "App folder · visible in Files" : folder.id).font(.caption.monospaced()).foregroundStyle(Palette.muted) }
                            Spacer()
                            if !folder.isExports { Button("Revoke") { state.folders.removeAll { $0.id == folder.id }; state.save() }.font(.caption) }
                        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button { folderPicker = true } label: { Label("Connect a folder", systemImage: "folder.badge.plus") }.buttonStyle(PrimaryButton())
                    Button { settings = true } label: { Label("Manage web search & Hugging Face keys", systemImage: "key").font(.caption) }
                }.padding(22)
            }.background(Palette.background).navigationTitle("Permissions").navigationBarTitleDisplayMode(.inline)
                .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in
                    switch result { case .success(let url): state.connectFolder(url); case .failure(let error): state.error = error.localizedDescription }
                }.sheet(isPresented: $settings) { SettingsView(state: state) }
        }
    }
}

struct ApprovalView: View {
    @Bindable var state: AppState
    let request: ApprovalRequest
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: request.call.tool.symbol).font(.largeTitle).foregroundStyle(Palette.accent)
                    Text("Allow this action?").font(.system(.largeTitle, design: .serif))
                    Text(request.call.tool.title).font(.headline)
                    Text(request.call.tool.subtitle).font(.subheadline).foregroundStyle(Palette.muted)
                    if request.call.tool == .webSearch { Label("This query will be sent to Brave Search over the internet.", systemImage: "globe").font(.subheadline) }
                    Text(request.call.preview).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                }.padding(24)
            }.background(Palette.background).navigationTitle("Permission request").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 14) {
                        Button("Allow once") { state.approve(true) }.buttonStyle(PrimaryButton()).accessibilityIdentifier("allowTool")
                        Button("Don't allow", role: .cancel) { state.approve(false) }.font(.subheadline).accessibilityIdentifier("denyTool")
                    }.padding(24).background(Palette.background)
                }
        }
    }
}

struct SettingsView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var hfToken = ""
    @State private var braveKey = ""
    @State private var saved = false
    @AppStorage("cellularDownloads") private var cellular = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Downloads") {
                    Toggle("Allow cellular downloads", isOn: $cellular)
                    Text("Applies to new downloads. Large downloads can use significant mobile data. Existing transfers retain their network policy.").font(.caption).foregroundStyle(Palette.muted)
                }
                Section("Hugging Face") {
                    SecureField("Optional read token", text: $hfToken).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Text("For private or gated repositories. Accept the model's license on Hugging Face first. The token stays in this device's Keychain.").font(.caption).foregroundStyle(Palette.muted)
                    Link("Manage Hugging Face tokens", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                }
                Section("Web search") {
                    SecureField("Brave Search API key", text: $braveKey).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Text("Requires a Brave API key. Queries are sent directly to Brave. After saving a key, enable Search the web in Permissions.").font(.caption).foregroundStyle(Palette.muted)
                    Link("Get a Brave Search API key", destination: URL(string: "https://api-dashboard.search.brave.com")!)
                }
                Section {
                    Button(saved ? "Keys saved" : "Save keys") {
                        do { try Keychain.save(hfToken.trimmingCharacters(in: .whitespacesAndNewlines), account: "huggingface"); try Keychain.save(braveKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "brave"); saved = true }
                        catch { state.error = error.localizedDescription }
                    }
                }
                Section("Your data") {
                    Label("No analytics or hosted inference", systemImage: "checkmark.shield")
                    Text("Conversations, models, and knowledge stay in app storage and are excluded from backups. Deleting the app removes them. Share important answers and export files you want to keep.").font(.caption).foregroundStyle(Palette.muted)
                    Text("Text models only. Generation stops when the app enters the background. Model performance and tool use vary; review source passages and proposed writes.").font(.caption).foregroundStyle(Palette.muted)
                }
                Section("PocketMind 0.1") {
                    Link("Source code", destination: URL(string: "https://github.com/ethanrimes/pocketmind-ios")!)
                    NavigationLink("Open-source acknowledgments") { ScrollView { Text(acknowledgments).font(.caption).padding() }.navigationTitle("Acknowledgments") }
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { hfToken = Keychain.read("huggingface"); braveKey = Keychain.read("brave") }
        }.tint(Palette.accent)
    }
    private var acknowledgments: String {
        guard let url = Bundle.main.url(forResource: "Acknowledgments", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "llama.cpp, minja, nlohmann/json, SwiftSoup, libzim and Kiwix." }
        return text
    }
}
