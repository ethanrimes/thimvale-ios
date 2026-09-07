import SwiftUI
import WebKit

struct WikipediaBrowserView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var downloads = false
    @State private var updates = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Read and search downloaded articles. No model or internet connection needed.")
                        .foregroundStyle(Palette.muted)
                }
                if state.archiveFiles.isEmpty {
                    ContentUnavailableView("No downloaded Wikipedia", systemImage: "books.vertical", description: Text("Download a pack, or import a ZIM archive in Knowledge."))
                } else {
                    Section("Downloaded packs") {
                        ForEach(state.archiveFiles, id: \.self) { file in
                            NavigationLink {
                                WikipediaArticleList(knowledge: state.knowledge, filename: file)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(Self.packTitle(file)).font(.headline)
                                    Text(file).font(.caption).foregroundStyle(Palette.muted)
                                    Label("Read offline", systemImage: "book").font(.caption).foregroundStyle(Palette.accent)
                                }.padding(.vertical, 6)
                            }.accessibilityIdentifier("wikiPack_" + file)
                        }
                    }
                }
                Button { downloads = true } label: { Label("Download Wikipedia packs", systemImage: "arrow.down.circle") }
                Button { updates = true } label: { Label("Wikipedia updates", systemImage: "arrow.triangle.2.circlepath") }
            }
            .scrollContentBackground(.hidden).background(Palette.background)
            .navigationTitle("Read Wikipedia")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $downloads) { WikipediaPacksView(state: state) }
            .sheet(isPresented: $updates) { WikipediaUpdatesView(state: state) }
        }
    }

    static func packTitle(_ filename: String) -> String {
        filename.replacingOccurrences(of: ".zim", with: "").replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "wikipedia en", with: "Wikipedia · English")
    }
}

private struct WikipediaArticleList: View {
    let knowledge: KnowledgeService
    let filename: String
    @State private var query = ""
    @State private var offset = 0
    @State private var page: WikipediaPage?
    @State private var error: String?
    @State private var loading = false
    @State private var retry = 0
    private var request: String { "\(query)\u{0}\(offset)\u{0}\(retry)" }

    var body: some View {
        List {
            Section {
                Text(WikipediaBrowserView.packTitle(filename)).font(.caption).foregroundStyle(Palette.muted)
                if let page { Text("\(page.articleCount.formatted()) articles · Offline").font(.caption) }
            }
            if loading { ProgressView("Searching this pack…") }
            else if let error {
                Text(error).foregroundStyle(.red)
                Button("Try again") { retry += 1 }
            } else if let page {
                if page.entries.isEmpty {
                    ContentUnavailableView("No matching articles", systemImage: "magnifyingglass", description: Text("Try another title or a shorter search. Topic packs contain only some Wikipedia pages."))
                }
                Section(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Articles A–Z" : "Search results") {
                    ForEach(page.entries) { entry in
                        NavigationLink {
                            WikipediaArticleView(knowledge: knowledge, filename: filename, path: entry.path)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title).font(.headline)
                                if !entry.snippet.isEmpty { Text(entry.snippet).font(.caption).foregroundStyle(Palette.muted).lineLimit(3) }
                            }.padding(.vertical, 3)
                        }.accessibilityIdentifier("wikiArticle_" + entry.path)
                    }
                }
                if offset > 0 || page.hasMore {
                    HStack {
                        Button("Previous") { offset = max(0, offset - 40) }.disabled(offset == 0)
                        Spacer()
                        Text("Page \(offset / 40 + 1)").font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        Button("Next") { offset += 40 }.disabled(!page.hasMore)
                    }.buttonStyle(.borderless)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .navigationTitle("Articles").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search this Wikipedia pack")
        .onChange(of: query) { _, _ in offset = 0 }
        .task(id: request) {
            loading = true; error = nil
            do {
                if !query.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
                let result = try await knowledge.wikipediaPage(in: filename, query: query, offset: offset)
                try Task.checkCancellation()
                page = result; loading = false
            } catch is CancellationError { /* A newer query owns the loading state. */ }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

private struct WikipediaArticleView: View {
    let knowledge: KnowledgeService
    let filename: String
    let path: String
    var fragment: String? = nil
    @State private var article: WikipediaArticle?
    @State private var error: String?
    @State private var destination: ArticleDestination?
    @State private var externalURL: URL?
    @Environment(\.openURL) private var openURL

    private struct ArticleDestination: Hashable {
        let path: String
        let fragment: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error {
                ContentUnavailableView("Couldn't open this page", systemImage: "doc.text.magnifyingglass", description: Text(error))
                Button("Try again") { Task { await load() } }.padding()
            } else if let article {
                HStack {
                    Label("Offline article", systemImage: "checkmark.circle").font(.caption)
                    Spacer()
                    Text("Text view").font(.caption).foregroundStyle(Palette.muted)
                }.foregroundStyle(Palette.accent).padding(.horizontal, 20).padding(.vertical, 10)
                WikipediaWebView(article: article, fragment: fragment, failure: { error = $0 }) { url in
                    if let target = WikipediaHTML.localPath(url) {
                        destination = ArticleDestination(path: target, fragment: url.fragment)
                    } else if ["https", "http"].contains(url.scheme ?? "") { externalURL = url }
                }
                HStack {
                    Text("Wikipedia contributors · CC BY-SA").font(.caption2).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Source & license") {
                        externalURL = URL(string: "https://en.wikipedia.org/wiki/")!.appendingPathComponent(article.title.replacingOccurrences(of: " ", with: "_"))
                    }.font(.caption2)
                }.padding(14)
            } else { ProgressView("Opening article…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Palette.background)
        .navigationTitle(article?.title ?? "Article").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $destination) { target in
            WikipediaArticleView(knowledge: knowledge, filename: filename, path: target.path, fragment: target.fragment)
        }
        .alert("Open this website online?", isPresented: Binding(get: { externalURL != nil }, set: { if !$0 { externalURL = nil } })) {
            if let url = externalURL { Button("Open in browser") { openURL(url); externalURL = nil } }
            Button("Cancel", role: .cancel) { externalURL = nil }
        } message: { Text(externalURL?.host ?? "An internet connection is required.") }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { article = try await knowledge.wikipediaArticle(in: filename, path: path) }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

private struct WikipediaWebView: UIViewRepresentable {
    let article: WikipediaArticle
    let fragment: String?
    let failure: (String) -> Void
    let follow: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(article: article, fragment: fragment, failure: failure, follow: follow) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.allowsLinkPreview = false
        view.accessibilityIdentifier = "wikipediaArticleBody"
        view.loadHTMLString(article.html, baseURL: WikipediaHTML.localURL(path: article.path))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let article: WikipediaArticle
        let fragment: String?
        let failure: (String) -> Void
        let follow: (URL) -> Void
        private var initialDocument = true
        init(article: WikipediaArticle, fragment: String?, failure: @escaping (String) -> Void, follow: @escaping (URL) -> Void) {
            self.article = article; self.fragment = fragment; self.failure = failure; self.follow = follow
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            // loadHTMLString reports its supplied base URL on some iOS versions,
            // and about:blank on others. Allow this app-supplied document once.
            if initialDocument, action.navigationType == .other,
               url.absoluteString == "about:blank" || WikipediaHTML.localPath(url) == article.path {
                initialDocument = false; decisionHandler(.allow); return
            }
            if action.navigationType == .linkActivated {
                if WikipediaHTML.localPath(url) == article.path, url.fragment != nil {
                    decisionHandler(.cancel)
                    scroll(to: url.fragment!, in: webView)
                } else { decisionHandler(.cancel); follow(url) }
            } else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let fragment else { return }
            scroll(to: fragment, in: webView)
        }
        private func scroll(to fragment: String, in webView: WKWebView) {
            // Only app-authored code runs. The argument is JSON-escaped, never
            // interpolated as code from an archive or a URL.
            if let data = try? JSONEncoder().encode(fragment.removingPercentEncoding ?? fragment), let argument = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("(() => { const e = document.getElementById(\(argument)) || document.getElementsByName(\(argument))[0]; if (e) { for (let p = e.parentElement; p; p = p.parentElement) { if (p.tagName === 'DETAILS') p.open = true; } e.scrollIntoView(); } })()", completionHandler: nil)
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { failure(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { failure(error.localizedDescription) }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            failure("The article reader was closed to free memory. Tap Try again to reopen it.")
        }
    }
}
