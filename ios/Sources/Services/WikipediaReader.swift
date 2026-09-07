import Foundation
import SwiftSoup

struct WikipediaEntry: Identifiable, Sendable {
    let path: String
    let title: String
    let snippet: String
    var id: String { path }
}

struct WikipediaPage: Sendable {
    let entries: [WikipediaEntry]
    let hasMore: Bool
    let articleCount: Int
}

struct WikipediaArticle: Sendable {
    let title: String
    let path: String
    let html: String
}

/// Archive HTML is untrusted. Only reader markup survives; no scripts, remote
/// resources, forms, styles from the archive, or automatic navigation are allowed.
enum WikipediaHTML {
    static let host = "offline.thimvale.invalid"

    static func localURL(path: String, fragment: String? = nil) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = host
        parts.path = "/" + path; parts.fragment = fragment
        return parts.url!
    }

    static func localPath(_ url: URL) -> String? {
        guard url.scheme == "https", url.host == host, url.user == nil, url.password == nil, url.port == nil else { return nil }
        return String(url.path.dropFirst())
    }

    static func link(_ href: String, from path: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        if trimmed.hasPrefix("#") { return trimmed }
        guard let url = URL(string: trimmed, relativeTo: localURL(path: path))?.absoluteURL.standardized,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { return nil }
        if let host = url.host?.lowercased(), ["en.wikipedia.org", "en.m.wikipedia.org"].contains(host), url.path.hasPrefix("/wiki/") {
            return localURL(path: String(url.path.dropFirst(6)), fragment: url.fragment).absoluteString
        }
        return url.absoluteString
    }

    static func render(_ html: String, title: String, path: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        try doc.select("script, style, iframe, object, embed, form, input, button, meta, link, base, noscript, .mw-editsection").remove()
        for table in try doc.select("table.infobox") {
            let wrapper = try SwiftSoup.parseBodyFragment("<details><summary>Article facts</summary></details>").select("details").first()!
            try table.replaceWith(wrapper)
            try wrapper.appendChild(table)
        }
        let allowed = try Whitelist.none()
            .addTags("a", "p", "div", "span", "section", "article", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "strong", "b", "em", "i", "u", "s", "small", "sub", "sup", "blockquote", "pre", "code", "br", "hr", "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption", "details", "summary", "figure", "figcaption")
            .addAttributes(":all", "id")
            .addAttributes("a", "href", "name")
            .addAttributes("th", "colspan", "rowspan", "scope")
            .addAttributes("td", "colspan", "rowspan")
        // The allowlist deliberately has no resource-bearing elements or attributes.
        let cleaned = try SwiftSoup.clean(try doc.body()?.html() ?? "", allowed) ?? ""
        let body = try SwiftSoup.parseBodyFragment(cleaned)
        for anchor in try body.select("a[href]") {
            if let target = link(try anchor.attr("href"), from: path) { try anchor.attr("href", target) }
            else { try anchor.removeAttr("href") }
        }
        if try body.select("h1").isEmpty() { try body.body()?.prependElement("h1").text(title) }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; font-src 'none'; media-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        :root { color-scheme: light dark; font: -apple-system-body; }
        body { margin: 0 auto; padding: 24px; max-width: 760px; background: #f7f6f1; color: #202621; line-height: 1.65; overflow-wrap: anywhere; }
        h1,h2,h3,h4 { font-family: Georgia,serif; line-height: 1.2; font-weight: 500; }
        h1 { font-size: 2.2em; margin-top: 0; } h2 { margin-top: 1.8em; border-bottom: 1px solid #ccd2cc; padding-bottom: 8px; }
        a { color: #2e574a; text-decoration: underline; } table { display: block; overflow-x: auto; border-collapse: collapse; max-width: 100%; }
        td,th { border: 1px solid #ccd2cc; padding: 8px; min-width: 5em; overflow-wrap: normal; word-break: normal; } pre { white-space: pre-wrap; } blockquote { margin: 16px; padding-left: 16px; border-left: 3px solid #ccd2cc; }
        details { margin: 16px 0; } summary { color: #637268; cursor: pointer; padding: 8px 0; }
        @media (prefers-color-scheme: dark) { body { background: #111413; color: #e3e9e4; } a { color: #94c9ab; } }
        </style></head><body>\(try body.body()?.html() ?? "")</body></html>
        """
    }
}
