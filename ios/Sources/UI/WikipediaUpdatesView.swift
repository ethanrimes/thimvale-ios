import SwiftUI

struct WikipediaUpdatesView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selected: WikipediaUpdate?
    @State private var preparing: String?
    @State private var downloadError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Checks for new editions when this app reconnects, and when you reopen it online. Downloads start only when you choose Update.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Button { Task { await state.wikipediaUpdates.checkNow() } } label: {
                        if state.wikipediaUpdates.checking { ProgressView("Checking Kiwix…") }
                        else { Label("Check for updates", systemImage: "arrow.clockwise") }
                    }.disabled(state.wikipediaUpdates.checking || state.wikipediaUpdates.eligibleFiles.isEmpty)
                    if let date = state.wikipediaUpdates.lastChecked { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.muted) }
                    if let error = state.wikipediaUpdates.error { Text(error).font(.caption).foregroundStyle(Palette.muted) }
                    if let downloadError { Text(downloadError).font(.caption).foregroundStyle(.red) }
                }
                if state.wikipediaUpdates.eligibleFiles.isEmpty {
                    ContentUnavailableView("No packs to update", systemImage: "books.vertical", description: Text("Download a Wikipedia pack first. Imported Kiwix packs need their original dated filenames to check for updates."))
                } else if state.wikipediaUpdates.available.isEmpty, !state.wikipediaUpdates.checking {
                    Text(state.wikipediaUpdates.lastChecked == nil ? "Check for a newer edition of your downloaded packs." : "No newer matching editions in the last catalog check.")
                        .foregroundStyle(Palette.muted)
                }
                ForEach(state.wikipediaUpdates.available) { update in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(update.pack.name).font(.headline)
                            Text("\(WikipediaEdition.parse(update.currentFilename)?.month ?? "") → \(WikipediaEdition.parse(update.pack.filename)?.month ?? "")")
                                .font(.subheadline.monospaced())
                            Text("\(update.pack.edition.capitalized) edition · \(update.pack.sizeLabel)").font(.caption).foregroundStyle(Palette.muted)
                        }
                        if let job = state.downloads.jobs.first(where: { $0.filename == update.pack.filename && $0.state != .ready }) {
                            DownloadRow(center: state.downloads, job: job)
                        } else {
                            Button { selected = update } label: {
                                if preparing == update.id { ProgressView("Preparing update…") }
                                else { Label("Update · \(update.pack.sizeLabel)", systemImage: "arrow.down.circle") }
                            }.disabled(preparing != nil)
                        }
                    }
                }
                Section("Your existing packs stay available") {
                    Text("Updates download a complete new pack, not a small patch. Free space is needed for both editions during the download. After verification, Q&A uses the newer edition; the previous file stays available to browse. You can remove it in Knowledge when ready.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("Automatic checks run while the app is active, or when you next open it. iOS doesn't guarantee running the app just because connectivity returns while it's closed.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Wikipedia updates").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Download the newer edition?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                if let update = selected { Button("Update") { download(update); selected = nil } }
                Button("Cancel", role: .cancel) { selected = nil }
            } message: { Text("This downloads \(selected?.pack.sizeLabel ?? "a full pack"). The old edition will be kept. Your cellular-download setting still applies.") }
        }
    }
    private func download(_ update: WikipediaUpdate) {
        preparing = update.id; downloadError = nil
        Task {
            defer { preparing = nil }
            do { try state.downloads.start(await WikipediaCatalog.downloadJob(for: update.pack)) }
            catch { downloadError = error.localizedDescription }
        }
    }
}
