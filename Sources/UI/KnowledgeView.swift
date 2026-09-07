import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeView: View {
    private enum ImportKind {
        case files, folder, archive
        var contentTypes: [UTType] {
            switch self {
            case .files: [.plainText, .pdf, .commaSeparatedText, .json, .html, .data]
            case .folder: [.folder]
            case .archive: [.data]
            }
        }
    }
    @Bindable var state: AppState
    @State private var importKind = ImportKind.files
    @State private var showImporter = false
    @State private var showWikipedia = false
    @State private var readWikipedia = false
    @State private var wikipediaUpdates = false
    @State private var query = ""
    @State private var results: [Citation] = []
    @State private var searching = false
    @State private var didSearch = false
    @State private var citation: Citation?
    @State private var deletingDocument: KnowledgeDocument?
    @State private var deletingArchive: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Local search")
                        Text("Offline knowledge").font(.system(size: 36, design: .serif)).tracking(-1)
                        Text("Import files or download Wikipedia for local search.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    HStack(spacing: 12) {
                        stat("\(state.documents.count)", "documents", "doc.text")
                        stat("\(state.archiveFiles.count)", "offline packs", "globe.europe.africa")
                    }
                    Button { showWikipedia = true } label: {
                        Card {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(alignment: .top) {
                                    Text("W").font(.system(size: 48, design: .serif)).foregroundStyle(Palette.accent)
                                    Spacer()
                                    Text("OFFLINE EDITIONS").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).padding(8).background(Palette.tint, in: Capsule()).foregroundStyle(Palette.accent)
                                }
                                VStack(alignment: .leading, spacing: 7) { Text("Wikipedia").font(.title3.weight(.medium)).foregroundStyle(Palette.ink); Text("Download articles for offline search and answers with sources.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3) }
                                HStack { Text("Browse Wikipedia downloads").font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "arrow.right") }.foregroundStyle(Palette.accent)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("exploreWikipedia")
                    Button { readWikipedia = true } label: {
                        Label("Read Wikipedia offline", systemImage: "book")
                    }.buttonStyle(PrimaryButton()).accessibilityIdentifier("readWikipedia")
                    Button { wikipediaUpdates = true } label: {
                        Label(state.wikipediaUpdates.available.isEmpty ? "Wikipedia updates" : "Wikipedia updates · \(state.wikipediaUpdates.available.count) available", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }.accessibilityIdentifier("wikipediaUpdates")
                    HStack(spacing: 12) {
                        Button { importKind = .files; showImporter = true } label: { Label("Add files", systemImage: "doc.badge.plus") }.buttonStyle(PrimaryButton())
                        Button { importKind = .folder; showImporter = true } label: { Label("Add folder", systemImage: "folder.badge.plus") }.buttonStyle(PrimaryButton())
                    }.disabled(state.importing)
                    if state.importing {
                        Card { VStack(alignment: .leading, spacing: 12) { ProgressView(state.importStatus).font(.caption); Button("Stop indexing") { state.cancelImport() }.font(.caption) } }
                    }
                    ForEach(state.activeJobs.filter { $0.kind == .wikipedia }) { job in DownloadRow(center: state.downloads, job: job) }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(state.semanticSearchAvailable ? "Search by keywords and meaning" : "Keyword search", systemImage: "point.3.connected.trianglepath.dotted").font(.subheadline.weight(.medium))
                            Text(state.semanticSearchAvailable ? "Indexed text is compressed and searched on this iPhone." : "Semantic search isn't available on this device. Keyword search works offline.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                        }
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField("Search your offline knowledge", text: $query).font(.subheadline).submitLabel(.search).onSubmit(search).accessibilityIdentifier("knowledgeSearch")
                        Button(action: search) { Image(systemName: "arrow.right.circle.fill") }.disabled(searching || query.isEmpty)
                    }.padding(15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
                    if searching { ProgressView("Searching locally…") }
                    if didSearch {
                        SectionHeading(title: "Search results", detail: "\(results.count) passages")
                        if results.isEmpty, !searching { Text("No matching passages. Try a specific term or import more sources.").font(.subheadline).foregroundStyle(Palette.muted) }
                        ForEach(results) { result in
                            Button { citation = result } label: {
                                Card { VStack(alignment: .leading, spacing: 8) { Text(result.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text(result.excerpt).font(.caption).foregroundStyle(Palette.muted).lineLimit(4) } }
                            }.buttonStyle(.plain)
                        }
                    }
                    SectionHeading(title: "Your library")
                    if state.documents.isEmpty, state.archiveFiles.isEmpty { Text("Supports text, Markdown, HTML, CSV, JSON, and PDFs with selectable text. Imported files are copies. Reimport them to update the index.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4) }
                    ForEach(state.archiveFiles, id: \.self) { file in
                        HStack(spacing: 12) {
                            Image(systemName: "globe.europe.africa").foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) { Text(file.replacingOccurrences(of: "_", with: " ")).font(.subheadline).lineLimit(2); Text("Offline · compressed ZIM").font(.caption).foregroundStyle(Palette.muted) }
                            Spacer()
                            Button { deletingArchive = file } label: { Image(systemName: "trash").font(.caption) }.accessibilityLabel("Delete \(file)").disabled(state.isGenerating)
                        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(state.documents) { document in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) { Text(document.title).font(.subheadline).lineLimit(2); Text("\(document.passages) passages · \(ByteCountFormatter.string(fromByteCount: document.storedBytes, countStyle: .file)) payload").font(.caption).foregroundStyle(Palette.muted) }
                            Spacer()
                            Button { deletingDocument = document } label: { Image(systemName: "trash").font(.caption) }.accessibilityLabel("Delete \(document.title)").disabled(state.importing || state.isGenerating)
                        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button { importKind = .archive; showImporter = true } label: { Label("Import an existing ZIM archive", systemImage: "square.and.arrow.down").font(.subheadline) }.disabled(state.importing)
                }.padding(22)
            }.background(Palette.background).navigationTitle("Knowledge").navigationBarTitleDisplayMode(.inline)
                .task { await state.refreshKnowledge() }
                .sheet(isPresented: $showWikipedia) { WikipediaPacksView(state: state) }
                .sheet(isPresented: $readWikipedia) { WikipediaBrowserView(state: state) }
                .sheet(isPresented: $wikipediaUpdates) { WikipediaUpdatesView(state: state) }
                .sheet(item: $citation) { CitationView(citation: $0) }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: importKind.contentTypes, allowsMultipleSelection: importKind == .files, onCompletion: handleImport)
                .confirmationDialog("Remove this document from the knowledge index? The original file stays in Files.", isPresented: Binding(get: { deletingDocument != nil }, set: { if !$0 { deletingDocument = nil } }), titleVisibility: .visible) {
                    Button("Remove document", role: .destructive) { if let doc = deletingDocument { Task { await state.removeDocument(doc.id) } }; deletingDocument = nil }
                }
                .confirmationDialog("Delete this downloaded archive? You can download it again.", isPresented: Binding(get: { deletingArchive != nil }, set: { if !$0 { deletingArchive = nil } }), titleVisibility: .visible) {
                    Button("Delete archive", role: .destructive) { if let file = deletingArchive { Task { await state.removeArchive(file) } }; deletingArchive = nil }
                }
        }
    }
    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        Card { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(Palette.accent); Text(value).font(.title2.weight(.medium)); Text(label).font(.caption).foregroundStyle(Palette.muted) } }
    }
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if importKind == .archive {
                if let url = urls.first { Task { await state.importArchive(url) } }
            } else { state.importKnowledge(urls) }
        case .failure(let error): state.error = error.localizedDescription
        }
    }
    private func search() {
        guard !searching, !query.isEmpty else { return }
        searching = true; didSearch = true
        Task {
            defer { searching = false }
            do { results = try await state.knowledge.search(query, archiveFiles: state.archiveFiles) }
            catch { state.error = error.localizedDescription }
        }
    }
}

struct WikipediaPacksView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var packs: [WikiPack] = []
    @State private var loading = true
    @State private var error: String?
    @State private var preparing: String?
    @State private var confirming: WikiPack?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Download Wikipedia").font(.system(size: 36, design: .serif)).tracking(-1)
                    Text("Mini editions contain abridged articles. Full text editions contain complete articles without pictures.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
                    if loading { ProgressView("Checking the Kiwix catalog…").frame(maxWidth: .infinity) }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red); Button("Try again") { Task { await load() } } }
                    ForEach(packs) { pack in
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(pack.name).font(.headline); Spacer(); Text(pack.sizeLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent) }
                                Text(pack.summary).font(.subheadline).foregroundStyle(Palette.muted)
                                HStack { Text(pack.isMini ? "Abridged articles" : "Full text · no pictures"); Spacer(); Text(pack.date) }.font(.caption).foregroundStyle(Palette.muted)
                                if state.archiveFiles.contains(pack.filename) { Label("Available offline", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.accent) }
                                else if let job = state.downloads.jobs.first(where: { $0.id == pack.id && $0.state != .ready }) { DownloadRow(center: state.downloads, job: job) }
                                else {
                                    Button {
                                        confirming = pack
                                    } label: { if preparing == pack.id { ProgressView() } else { Label("Download · \(pack.sizeLabel)", systemImage: "arrow.down.circle") } }.buttonStyle(PrimaryButton()).disabled(preparing != nil)
                                }
                            }
                        }
                    }
                    Text("Archives are provided by Kiwix / openZIM. Wikipedia text is available under CC BY-SA; attribution and source links are preserved in citations. These are dated snapshots, not live Wikipedia.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                    Link("About Kiwix archives", destination: URL(string: "https://kiwix.org/en/about/")!).font(.caption)
                }.padding(24)
            }.background(Palette.background).navigationTitle("Wikipedia packs").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.task { await load() }
                .confirmationDialog("Download \(confirming?.sizeLabel ?? "") to this iPhone? Keep the app open while the completed archive is verified.", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
                    if let pack = confirming { Button("Download \(pack.name)") { download(pack); confirming = nil } }
                }
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { packs = try await WikipediaCatalog.fetch() } catch { self.error = error.localizedDescription }
    }
    private func download(_ pack: WikiPack) {
        preparing = pack.id
        Task {
            defer { preparing = nil }
            do { try state.downloads.start(await WikipediaCatalog.downloadJob(for: pack)) }
            catch { state.error = error.localizedDescription }
        }
    }
}
