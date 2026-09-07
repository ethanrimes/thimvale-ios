import SwiftUI

struct ChatView: View {
    @Bindable var state: AppState
    @State private var draft = ""
    @State private var history = false
    @State private var settings = false
    @State private var source: Citation?
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("Conversation mode", selection: Binding(get: { state.current.mode }, set: state.setMode)) {
                        ForEach(ConversationMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 180).disabled(state.isGenerating).accessibilityIdentifier("modePicker")
                    Spacer()
                    Button { state.selectedTab = 1 } label: {
                        HStack(spacing: 5) {
                            Circle().fill(state.selectedModel == nil ? Color.secondary : Palette.accent).frame(width: 5, height: 5)
                            Text(state.selectedModel.map { $0.name + " " + $0.parameters } ?? "Pick a model").lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }.font(.caption).foregroundStyle(Palette.accent)
                    }.accessibilityIdentifier("modelPicker")
                }.padding(.horizontal, 22).padding(.vertical, 14)
                if state.current.messages.isEmpty { welcome }
                else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(state.current.messages) { message in messageView(message).id(message.id) }
                                if state.isGenerating {
                                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text(state.status).font(.caption).foregroundStyle(Palette.muted) }.id("status")
                                }
                            }.padding(22)
                        }
                        .onChange(of: state.current.messages.last?.content) { _, _ in proxy.scrollTo(state.current.messages.last?.id, anchor: .bottom) }
                        .onChange(of: state.isGenerating) { _, _ in proxy.scrollTo("status", anchor: .bottom) }
                    }
                }
            }
            .background(Palette.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { history = true } label: { Image(systemName: "line.3.horizontal") }.accessibilityLabel("Conversation history")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) { BrandMark(size: 26); Text(AppIdentity.displayName.lowercased()).font(.system(.headline, design: .rounded)).accessibilityIdentifier("appWordmark") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { state.newConversation() } label: { Image(systemName: "square.and.pencil") }.disabled(state.isGenerating).accessibilityLabel("New conversation")
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $history) { historySheet }
            .sheet(isPresented: $settings) { SettingsView(state: state) }
            .sheet(item: $source) { CitationView(citation: $0) }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 7) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Eyebrow(text: "Local chat")
                }.padding(.top, 30)
                Text(state.current.mode == .chat ? "Start a conversation." : "Work with your files.")
                    .font(.system(size: 38, weight: .regular, design: .serif)).tracking(-1.5).fixedSize(horizontal: false, vertical: true)
                Text(state.current.mode == .chat ? "Choose a model, then send a message. Conversations run on your iPhone." : "Search your documents and offline Wikipedia, or create files. Set tool access in Permissions.")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label("On-device", systemImage: "iphone")
                    Label("No account", systemImage: "person.crop.circle.badge.checkmark")
                }.font(.caption).foregroundStyle(Palette.accent)
                VStack(spacing: 10) {
                    suggestion(state.current.mode == .chat ? "Explain a topic" : "Search documents", subtitle: state.current.mode == .chat ? "Ask about a subject" : "Find passages in your offline library", symbol: state.current.mode == .chat ? "text.bubble" : "text.magnifyingglass", prompt: state.current.mode == .chat ? "Explain " : "Search my knowledge library for ")
                    suggestion(state.current.mode == .chat ? "Draft a message" : "Summarize files", subtitle: state.current.mode == .chat ? "Choose the recipient and tone" : "Read files from a connected folder", symbol: "square.and.pencil", prompt: state.current.mode == .chat ? "Draft a message to " : "List my connected files and summarize ")
                }
                if state.current.mode == .work {
                    Button { state.selectedTab = 3 } label: { Label("Edit tool permissions", systemImage: "hand.raised").font(.caption) }
                }
            }.padding(.horizontal, 26).padding(.bottom, 24)
        }
    }
    private func suggestion(_ title: String, subtitle: String, symbol: String, prompt: String) -> some View {
        Button { draft = prompt; composing = true } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(.subheadline, weight: .medium)).foregroundStyle(Palette.ink); Text(subtitle).font(.caption).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.muted)
            }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
        }.buttonStyle(.plain)
    }
    private var composer: some View {
        VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField(state.current.mode == .work ? "Describe a task" : "Message", text: $draft, axis: .vertical)
                    .font(.subheadline).lineLimit(1...5).focused($composing).padding(.vertical, 10).accessibilityIdentifier("messageInput")
                Button {
                    if state.isGenerating { state.stop() }
                    else {
                        composing = false
                        if state.send(draft) { draft = "" }
                    }
                } label: {
                    Image(systemName: state.isGenerating ? "stop.fill" : "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.background)
                        .frame(width: 38, height: 38).background(Palette.accent, in: Circle())
                }.disabled(!state.isGenerating && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(state.isGenerating ? "Stop generation" : "Send message").accessibilityIdentifier("sendMessage")
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line))
            Text(state.current.mode == .chat ? "Your conversation stays on this iPhone." : "Tools follow your permissions. Web search uses the internet.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 8).background(Palette.background)
    }
    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if message.role == "assistant" { BrandMark(size: 24) }
                Text(message.role == "user" ? "YOU" : AppIdentity.displayName.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted)
                Spacer()
                if !message.content.isEmpty { ShareLink(item: message.content) { Image(systemName: "square.and.arrow.up").font(.caption) }.accessibilityLabel("Share message") }
            }
            if !message.activity.isEmpty {
                DisclosureGroup("\(message.activity.count) work step\(message.activity.count == 1 ? "" : "s")") {
                    ForEach(Array(message.activity.enumerated()), id: \.offset) { _, item in Text(item).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) }
                }.font(.caption).foregroundStyle(Palette.muted)
            }
            if !message.content.isEmpty { Text(.init(AppState.visibleAnswer(message.content))).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(message.role + "Message") }
            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !state.isGenerating && CitationValidator.cited(in: message.content, from: message.citations).isEmpty {
                        Text("The model didn't add inline citations. Check the sources below.")
                            .font(.caption).foregroundStyle(Palette.muted)
                            .accessibilityIdentifier("missingInlineCitations")
                    }
                    Eyebrow(text: "Evidence retrieved · tap to inspect")
                    let unique = message.citations.reduce(into: [Citation]()) { list, citation in if !list.contains(where: { $0.id == citation.id }) { list.append(citation) } }
                    ForEach(unique) { citation in
                        Button { source = citation } label: {
                            HStack(spacing: 8) { Image(systemName: "doc.text.magnifyingglass"); Text(citation.title).lineLimit(1); Spacer(); Text("[\(citation.id)]").font(.system(size: 9, design: .monospaced)) }.font(.caption).padding(11).background(Palette.tint, in: RoundedRectangle(cornerRadius: 10))
                        }.accessibilityIdentifier("citation_" + citation.id)
                    }
                }
            }
        }.padding(message.role == "user" ? 16 : 0).background(message.role == "user" ? Palette.tint : .clear, in: RoundedRectangle(cornerRadius: 20))
    }
    private var historySheet: some View {
        NavigationStack {
            List {
                ForEach(state.conversations) { item in
                    Button { state.selectConversation(item.id); history = false } label: {
                        VStack(alignment: .leading, spacing: 5) { Text(item.title).foregroundStyle(Palette.ink); Text("\(item.mode.rawValue) · \(item.updatedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Palette.muted) }
                    }.disabled(state.isGenerating)
                        .swipeActions { Button("Delete", role: .destructive) { state.deleteConversation(item.id) }.disabled(state.isGenerating) }
                }
            }.navigationTitle("Conversations").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { history = false } } }
        }
    }
}

struct CitationView: View {
    var citation: Citation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Eyebrow(text: "Source \(citation.id)")
                    Text(citation.title).font(.system(.largeTitle, design: .serif))
                    Text(citation.location).font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
                    Divider()
                    Text(citation.excerpt).font(.body).lineSpacing(6).textSelection(.enabled)
                    Text("This is the original retrieved passage. A citation identifies evidence; it does not guarantee the model interpreted it correctly.").font(.caption).foregroundStyle(Palette.muted)
                    if let link = citation.sourceURL, let url = URL(string: link), url.scheme == "https" { Link("Open original source online", destination: url).font(.subheadline) }
                }.padding(24)
            }.background(Palette.background).navigationTitle("Evidence").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
