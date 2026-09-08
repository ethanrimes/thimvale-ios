import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @Bindable var state: AppState
    @State private var query = ""
    @State private var family = "All"
    @State private var scope = "Discover"
    @State private var sizeFilter = "All sizes"
    @State private var visionOnly = false
    @State private var selected: ModelEntry?
    @State private var importFile = false
    @State private var hubResults: [ModelEntry] = []
    @State private var hubSearching = false
    @State private var searched = false
    @State private var repositoryPrompt = false
    @State private var repository = ""
    @FocusState private var searchFocused: Bool
    private var visible: [ModelEntry] {
        let all = scope == "Hugging Face" ? hubResults : state.models
        return all.filter { model in
            (scope != "Downloaded" || model.isDownloaded)
                && (!visionOnly || model.vision == true || model.projectorFilename != nil)
                && (family == "All" || model.family == family || scope == "Hugging Face")
                && (scope != "Discover" || sizeFilter != "4B class" || model.isFourBillionClass)
                && (scope != "Discover" || sizeFilter != "Higher RAM" || model.needsHigherMemory)
                && (scope == "Hugging Face" || model.matchesLibrarySearch(query))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Local models")
                        Text("Choose a model").font(.system(size: 34, design: .serif)).tracking(-1)
                        Text("Download a model or import a GGUF file.").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Picker("Model source", selection: $scope) { ForEach(["Discover", "Downloaded", "Hugging Face"], id: \.self) { Text($0) } }.pickerStyle(.segmented).onChange(of: scope) { _, _ in family = "All"; sizeFilter = "All sizes"; visionOnly = false }
                    if scope != "Hugging Face" {
                        Toggle(isOn: $visionOnly) { Label("Vision models", systemImage: "eye") }.font(.subheadline).accessibilityIdentifier("visionModelsFilter")
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField(scope == "Hugging Face" ? "Search Hugging Face GGUF models" : "Search models or families", text: $query).font(.subheadline).autocorrectionDisabled().textInputAutocapitalization(.never).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false; if scope == "Hugging Face" { searchHub() } }.accessibilityIdentifier("modelSearch")
                        if scope == "Hugging Face" { Button { searchHub() } label: { Image(systemName: "arrow.right.circle.fill") }.disabled(hubSearching) }
                    }.padding(15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
                    if scope == "Discover" {
                        Picker("Model size", selection: $sizeFilter) {
                            Text("All sizes").tag("All sizes")
                            Text("4B class").tag("4B class")
                            Text("Higher RAM").tag("Higher RAM")
                        }.pickerStyle(.segmented).accessibilityIdentifier("modelSizeFilter")
                        if sizeFilter == "4B class" {
                            Text("About 3.5–4.5B total parameters, including Phi 4 Mini and Nanbeige. Start with Q4 on an iPhone with roughly 8 GB RAM or more. Free memory and context still matter.")
                                .font(.caption).foregroundStyle(Palette.muted)
                        } else if sizeFilter == "Higher RAM" {
                            Text("For devices with roughly 12 GB RAM or more. These Q4 downloads are around 4.5–6 GB, before context and runtime memory. Active parameter counts do not describe memory use.")
                                .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("higherRAMGuidance")
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["All"] + ModelCatalog.families, id: \.self) { item in
                                    Button { family = item } label: {
                                        Text(item).font(.caption.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 9).foregroundStyle(family == item ? Palette.background : Palette.muted).background(family == item ? Palette.accent : Palette.surface, in: Capsule())
                                    }.accessibilityIdentifier("family_" + item)
                                }
                            }
                        }
                    }
                    if !state.activeJobs.isEmpty {
                        VStack(spacing: 10) { ForEach(state.activeJobs.filter { $0.kind != .wikipedia }) { job in DownloadRow(center: state.downloads, job: job) } }
                    }
                    if scope == "Discover", !visionOnly, sizeFilter == "All sizes", family == "All", query.isEmpty, let recommended = state.models.first {
                        Button { selected = recommended } label: {
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack { Eyebrow(text: "Suggested model"); Spacer(); Image(systemName: "iphone").foregroundStyle(Palette.accent) }
                                    HStack(spacing: 13) {
                                        FamilyIcon(family: recommended.family)
                                        VStack(alignment: .leading, spacing: 5) { Text(recommended.name + " · " + recommended.parameters).font(.title3.weight(.semibold)); Text("\(recommended.parameters) parameters · GGUF").font(.caption).foregroundStyle(Palette.muted) }
                                    }
                                    HStack { Text(recommended.isDownloaded ? "Downloaded" : "View model").font(.subheadline.weight(.medium)); Spacer(); Image(systemName: "arrow.right") }.foregroundStyle(Palette.accent)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    if hubSearching { ProgressView("Searching Hugging Face…").frame(maxWidth: .infinity).padding() }
                    else if visible.isEmpty {
                        ContentUnavailableView(scope == "Hugging Face" && !searched ? "Search Hugging Face" : "No models found", systemImage: "square.stack.3d.up", description: Text(scope == "Hugging Face" ? "Search or enter an owner/model repository. Image input needs a matching mmproj GGUF." : "Try another filter, download a model, or import a GGUF from Files."))
                    } else {
                        SectionHeading(title: scope == "Downloaded" ? "On this iPhone" : "Model library", detail: "\(visible.count) models")
                        // Curated and Hub results are small. Keep row layout eager
                        // while typing: the count and suggested card change as the
                        // keyboard resizes the scroll view. Avoid coupling nested
                        // lazy-row sizing to those simultaneous transitions.
                        VStack(spacing: 10) { ForEach(visible) { model in modelRow(model) } }
                    }
                    Button { repositoryPrompt = true } label: { Label("Open a Hugging Face repository", systemImage: "link").font(.subheadline).frame(maxWidth: .infinity).padding(18).background(Palette.tint, in: RoundedRectangle(cornerRadius: 18)) }
                    Text("Memory guidance is approximate. Actual support depends on the architecture, quantization, context, and free memory. Models have individual licenses.").font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively).background(Palette.background)
                .navigationTitle("Models").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { importFile = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import GGUF model") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { searchFocused = false } }
                }
                .sheet(item: $selected) { ModelDetailView(state: state, model: $0) }
                .fileImporter(isPresented: $importFile, allowedContentTypes: [.data]) { result in
                    if case .success(let url) = result { Task { await state.importModel(url) } }
                    else if case .failure(let error) = result { state.error = error.localizedDescription }
                }
                .alert("Open repository", isPresented: $repositoryPrompt) {
                    TextField("owner/model or huggingface.co URL", text: $repository).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Open") {
                        let input = repository.trimmingCharacters(in: .whitespacesAndNewlines)
                        let repo = input.hasPrefix("https://huggingface.co/") ? String(input.dropFirst("https://huggingface.co/".count)).split(separator: "/").prefix(2).joined(separator: "/") : input
                        selected = .init(id: repo, name: repo.split(separator: "/").last.map(String.init) ?? repo, family: "Hugging Face", repository: repo, summary: "Custom Hugging Face repository", parameters: "GGUF", minimumMemoryGB: 0)
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
    private func searchHub() {
        guard !hubSearching else { return }
        hubSearching = true; searched = true
        Task {
            defer { hubSearching = false }
            do { hubResults = try await state.hub.search(query) }
            catch { state.error = error.localizedDescription }
        }
    }
    private func modelRow(_ model: ModelEntry) -> some View {
        Button { selected = model } label: {
            HStack(spacing: 13) {
                FamilyIcon(family: model.family)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text("\(model.parameters) · \(model.family)").font(.caption).foregroundStyle(Palette.muted)
                    Label(model.visionLabel, systemImage: model.visionLabel == "Vision" ? "eye" : "text.alignleft")
                        .font(.caption2).foregroundStyle(model.visionLabel == "Vision" ? Palette.accent : Palette.muted)
                    if model.needsHigherMemory { Text("Higher RAM · 12+ GB suggested").font(.caption2).foregroundStyle(Palette.muted) }
                    if state.selectedModelID == model.id { Text(state.modelSession.label).font(.caption2).foregroundStyle(Palette.accent) }
                }
                Spacer(minLength: 0)
                if model.isDownloaded { Image(systemName: state.selectedModelID == model.id ? "checkmark.circle.fill" : "checkmark.circle").foregroundStyle(Palette.accent) }
                else { Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(Palette.accent) }
            }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("model_" + model.id)
    }
}

struct ModelDetailView: View {
    @Bindable var state: AppState
    let model: ModelEntry
    @Environment(\.dismiss) private var dismiss
    @State private var files: [HubFile] = []
    @State private var selectedFile: String?
    @State private var license: String?
    @State private var loading = false
    @State private var loadError: String?
    @State private var confirmDelete = false
    @State private var projectors: [HubFile] = []
    @State private var selectedProjector: String?
    @State private var importVision = false
    @State private var confirmDeleteVision = false
    private var current: ModelEntry { state.models.first { $0.id == model.id } ?? model }
    private var selected: HubFile? { files.first { $0.id == selectedFile } }
    private var job: DownloadJob? { state.downloads.jobs.first { $0.kind == .model && $0.model?.id == model.id && $0.state != .ready } }
    private var visionJob: DownloadJob? { state.downloads.jobs.first { $0.kind == .projector && $0.filename == current.projectorFilename && $0.state != .ready } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    FamilyIcon(family: model.family)
                    VStack(alignment: .leading, spacing: 8) { Text(model.name).font(.system(.largeTitle, design: .serif)); Text("\(model.parameters) · \(model.family)").font(.subheadline).foregroundStyle(Palette.accent); Text(model.summary).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4) }
                    Label(current.vision == true ? "Vision · text and images" : current.visionLabel, systemImage: current.vision == true ? "eye" : "text.alignleft").font(.subheadline).foregroundStyle(Palette.accent).accessibilityIdentifier("modelCapability")
                    if current.isDownloaded {
                        Card { Label("Downloaded on this iPhone", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                        Button("Use this model") { state.selectModel(current); state.selectedTab = 0; dismiss() }.buttonStyle(PrimaryButton()).disabled(state.isGenerating)
                        Button("Delete downloaded model", role: .destructive) { confirmDelete = true }.font(.subheadline).disabled(state.isGenerating)
                    } else if let job { DownloadRow(center: state.downloads, job: job) }
                    else if loading { ProgressView("Loading verified file sizes…").frame(maxWidth: .infinity) }
                    else if let loadError { Text(loadError).font(.subheadline).foregroundStyle(.red); Button("Try again") { Task { await load() } } }
                    else {
                        if let selected {
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack { Text("Download size").foregroundStyle(Palette.muted); Spacer(); Text(selected.sizeLabel).fontWeight(.semibold) }
                                    HStack { Text("Format").foregroundStyle(Palette.muted); Spacer(); Text("GGUF · model weights") }
                                    if model.minimumMemoryGB > 0 { HStack { Text("Suggested device RAM").foregroundStyle(Palette.muted); Spacer(); Text("\(model.minimumMemoryGB)+ GB") } }
                                    Text(selected.path).font(.caption.monospaced()).foregroundStyle(Palette.muted).lineLimit(3)
                                }.font(.subheadline)
                            }
                            if model.minimumMemoryGB > Int(ProcessInfo.processInfo.physicalMemory / 1_000_000_000) { Label("This model may exceed your device's memory. A smaller model is recommended.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                            Button("Download · \(selected.sizeLabel)") {
                                do {
                                    try state.download(selected, model: model, license: license)
                                } catch { state.error = error.localizedDescription }
                            }.buttonStyle(PrimaryButton())
                        }
                        DisclosureGroup("Choose quantization (\(files.count) files)") {
                            ForEach(files) { file in
                                Button { selectedFile = file.id } label: {
                                    HStack { VStack(alignment: .leading, spacing: 4) { Text(file.path).lineLimit(2); Text(file.sizeLabel).foregroundStyle(Palette.muted) }; Spacer(); if selectedFile == file.id { Image(systemName: "checkmark") } }.font(.caption).padding(.vertical, 8)
                                }
                            }
                        }.font(.subheadline)
                    }
                    if current.vision == true || !projectors.isEmpty || current.family == "Imported" || current.family == "Hugging Face" {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Image input", systemImage: "photo").font(.headline)
                                if state.projectorURL(for: current) != nil {
                                    Text("Vision file installed. Attach an image in Chat; compatibility is checked on first use.").font(.subheadline)
                                    Button("Remove vision file", role: .destructive) { confirmDeleteVision = true }.disabled(state.isGenerating || state.importing)
                                } else {
                                    Text("Image input needs a separate vision file (mmproj) made for these exact model weights. It uses additional storage and memory. Audio and video are not supported.").font(.caption).foregroundStyle(Palette.muted)
                                    if !current.isDownloaded { Text("Download the model above, then add its vision file here.").font(.subheadline) }
                                    else if let visionJob { DownloadRow(center: state.downloads, job: visionJob) }
                                    else if loading { ProgressView("Finding vision files…") }
                                    else if !projectors.isEmpty {
                                        Picker("Vision file", selection: $selectedProjector) {
                                            ForEach(projectors) { file in Text(file.path + " · " + file.sizeLabel).tag(Optional(file.id)) }
                                        }.pickerStyle(.menu)
                                        if let file = projectors.first(where: { $0.id == selectedProjector }) {
                                            Button("Download vision file · \(file.sizeLabel)") {
                                                do { try state.downloadProjector(file, model: current) } catch { state.error = error.localizedDescription }
                                            }.disabled(state.isGenerating || state.importing).accessibilityIdentifier("downloadVisionFile")
                                        }
                                    } else if current.isDownloaded, !current.repository.isEmpty {
                                        Text(loadError ?? "No vision file found in this repository. You can import a matching one from Files.").font(.caption).foregroundStyle(Palette.muted)
                                        Button("Check repository again") { Task { await load() } }
                                    }
                                    if current.isDownloaded {
                                        Button("Import matching vision file") { importVision = true }.disabled(state.isGenerating || state.importing).accessibilityIdentifier("importVisionFile")
                                    }
                                }
                            }
                        }
                    }
                    if !model.repository.isEmpty {
                        Link(destination: URL(string: "https://huggingface.co/")!.appendingPathComponent(model.repository)) { Label("Model card & license", systemImage: "arrow.up.right.square").font(.subheadline) }
                        Text("License: \(license ?? current.license ?? "see model card"). By downloading, you agree to the model publisher's terms. Some repositories require a Hugging Face token in Settings.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Text("Downloads are verified before use. Loading checks architecture support; a download alone does not establish compatibility. iOS may pause work when the app goes into the background.").font(.caption).foregroundStyle(Palette.muted)
                }.padding(24)
            }.background(Palette.background).navigationTitle("Model details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: current.localFilename) { if !model.repository.isEmpty || !current.isDownloaded { await load() } }
                .fileImporter(isPresented: $importVision, allowedContentTypes: [.data]) { result in
                    switch result {
                    case .success(let url): Task { await state.importProjector(url, model: current) }
                    case .failure(let error): if (error as NSError).code != NSUserCancelledError { state.error = error.localizedDescription }
                    }
                }
                .confirmationDialog("Remove the vision file? The text model will stay downloaded.", isPresented: $confirmDeleteVision, titleVisibility: .visible) { Button("Remove vision file", role: .destructive) { state.removeProjector(current) } }
                .confirmationDialog("Delete \(current.name) from this iPhone? You can download it again.", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Delete model", role: .destructive) { state.removeModel(current); dismiss() } }
        }
    }
    private func load() async {
        loading = true; loadError = nil
        defer { loading = false }
        do {
            let response = try await state.hub.assets(in: model.repository, revision: current.repositoryRevision)
            files = response.weights; license = response.license; projectors = response.projectors
            selectedProjector = projectors.first { $0.path.localizedCaseInsensitiveContains("f16") || $0.path.localizedCaseInsensitiveContains("f32") }?.id ?? projectors.first?.id
            selectedFile = files.first { $0.path.localizedCaseInsensitiveContains(model.preferredQuant) }?.id ?? files.first?.id
        } catch { loadError = error.localizedDescription }
    }
}

struct DownloadRow: View {
    @Bindable var center: DownloadCenter
    var job: DownloadJob
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: job.kind == .model ? "square.stack.3d.up" : "globe.europe.africa")
                    Text(job.title).font(.subheadline.weight(.medium)).lineLimit(2)
                    Spacer()
                    if job.state == .downloading { Button { center.pause(job.id) } label: { Image(systemName: "pause.circle") }.accessibilityLabel("Pause download") }
                    if job.state == .failed || job.state == .paused { Button { center.resume(job.id) } label: { Image(systemName: "play.circle") }.accessibilityLabel("Resume download") }
                }
                if job.state == .validating { ProgressView("Verifying file…").font(.caption) }
                else { ProgressView(value: job.progress) }
                Text("\(ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: job.expectedBytes, countStyle: .file)) · \(job.state.rawValue.capitalized)").font(.caption).foregroundStyle(Palette.muted)
                if let error = job.error { Text(error).font(.caption).foregroundStyle(.red) }
                if job.state == .failed || job.state == .paused { Button("Remove transfer", role: .destructive) { center.forget(job.id) }.font(.caption) }
            }
        }
    }
}
