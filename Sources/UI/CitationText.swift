import SwiftUI

enum InlineCitations {
    static func text(_ text: String, sources: [Citation]) -> AttributedString {
        var rendered = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        let plain = String(rendered.characters)
        let ids = Set(sources.map(\.id))
        let pattern = try! NSRegularExpression(pattern: "\\[([1-9][0-9]*)\\]")
        for match in pattern.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let number = Range(match.range(at: 1), in: plain), ids.contains(String(plain[number])),
                  let range = Range(match.range, in: plain),
                  let lower = AttributedString.Index(range.lowerBound, within: rendered),
                  let upper = AttributedString.Index(range.upperBound, within: rendered) else { continue }
            let selection = lower..<upper
            guard !rendered[selection].runs.contains(where: { $0.inlinePresentationIntent?.contains(.code) == true }) else { continue }
            rendered[selection].link = URL(string: "thimvale-citation://source/" + plain[number])
        }
        return rendered
    }

    static func source(for url: URL, in sources: [Citation]) -> Citation? {
        guard url.scheme == "thimvale-citation", url.host == "source", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        return sources.first { url.path == "/" + $0.id }
    }
}

struct CitationText: View {
    let text: String
    let sources: [Citation]
    let identifier: String
    let inspect: (Citation) -> Void

    var body: some View {
        Text(InlineCitations.text(text, sources: sources))
            .font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(identifier)
            .environment(\.openURL, OpenURLAction { url in
                if let source = InlineCitations.source(for: url, in: sources) { inspect(source); return .handled }
                if ["http", "https"].contains(url.scheme ?? "") { return .systemAction }
                return .discarded
            })
    }
}

struct MessageSourcesView: View {
    let sources: [Citation]
    let inspect: (Citation) -> Void
    @State private var expanded = false
    private var unique: [Citation] {
        sources.reduce(into: []) { list, citation in
            if !list.contains(where: { $0.id == citation.id }) { list.append(citation) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                    Text("Sources").font(.caption)
                    Text("\(unique.count)").font(.caption.monospaced())
                }.foregroundStyle(Palette.muted).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("messageSources")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                ForEach(unique) { citation in
                    Button { inspect(citation) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text("[\(citation.id)]").font(.caption.monospaced()).foregroundStyle(Palette.accent)
                            Text(citation.title).font(.caption).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("citation_" + citation.id)
                }
            }
        }
    }
}
