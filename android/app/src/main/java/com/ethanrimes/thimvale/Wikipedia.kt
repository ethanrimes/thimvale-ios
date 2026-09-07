package com.ethanrimes.thimvale

import java.net.URI
import org.jsoup.Jsoup
import org.jsoup.safety.Safelist
import org.kiwix.libkiwix.JNIKiwix
import org.kiwix.libzim.Archive
import org.kiwix.libzim.Query
import org.kiwix.libzim.Searcher

data class ArticleEntry(val path: String, val title: String)

data class Article(val path: String, val title: String, val html: String, val text: String)

object WikiHTML {
    const val ORIGIN = "https://offline.thimvale.invalid/"

    fun url(path: String): String =
        URI("https", "offline.thimvale.invalid", "/$path", null).toASCIIString()

    fun link(href: String, from: String): String? =
        runCatching {
                val uri = URI(url(from)).resolve(href)
                if (uri.scheme !in setOf("http", "https") || uri.rawUserInfo != null) return null
                if (
                    uri.host in setOf("en.wikipedia.org", "en.m.wikipedia.org") &&
                        uri.path.startsWith("/wiki/")
                )
                    url(uri.path.removePrefix("/wiki/")) + (uri.rawFragment?.let { "#$it" } ?: "")
                else uri.toASCIIString()
            }
            .getOrNull()

    fun render(title: String, html: String, path: String): String {
        val parsed = Jsoup.parse(html)
        parsed.select("script,style,iframe,form,object,embed,meta,base,link,svg,math").remove()
        val allow =
            Safelist.none()
                .addTags(
                    "p",
                    "div",
                    "span",
                    "h1",
                    "h2",
                    "h3",
                    "h4",
                    "ul",
                    "ol",
                    "li",
                    "table",
                    "tbody",
                    "tr",
                    "td",
                    "th",
                    "caption",
                    "a",
                    "sup",
                    "sub",
                    "b",
                    "strong",
                    "em",
                    "i",
                    "blockquote",
                    "br",
                    "hr",
                    "pre",
                    "code",
                    "details",
                    "summary",
                )
                .addAttributes(":all", "id")
                .addAttributes("a", "href")
        val clean = Jsoup.parse(Jsoup.clean(parsed.body().html(), allow))
        clean.select("a[href]").forEach { a ->
            link(a.attr("href"), path)?.let { a.attr("href", it) } ?: a.removeAttr("href")
        }
        clean.select("table").forEach { table ->
            table.wrap("<details><summary>Article facts</summary></details>")
        }
        if (clean.select("h1").isEmpty()) clean.body().prependElement("h1").text(title)
        return """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; script-src 'none'"><style>body{font:17px/1.6 sans-serif;padding:12px 20px;background:#f7f6f0;color:#222923;overflow-wrap:break-word}h1,h2,h3{font-family:serif;line-height:1.2}h1{font-size:36px}a{color:#32554a}table{display:block;overflow:auto}td,th{min-width:5em;padding:6px}details{margin:20px 0}pre{white-space:pre-wrap}</style></head><body>${clean.body().html()}<hr><p>Wikipedia contributors · CC BY-SA. This is an offline text edition.</p></body></html>"""
    }
}

class Wikipedia(private val library: Library) {
    private val binding = JNIKiwix(library.context)
    // Serialized native access. Keep only one archive open to bound native caches.
    private var cached: Pair<String, Archive>? = null

    private fun archive(filename: String): Archive {
        require(filename.endsWith(".zim")) { "Choose a ZIM archive." }
        cached
            ?.takeIf { it.first == filename }
            ?.let {
                return it.second
            }
        cached?.second?.dispose()
        cached = null
        val archive = Archive(library.file(filename).absolutePath)
        cached = filename to archive
        return archive
    }

    @Synchronized
    fun close() {
        cached?.second?.dispose()
        cached = null
    }

    @Synchronized
    fun browse(filename: String, query: String, offset: Int): List<ArticleEntry> {
        require(offset in 0..1_000_000 && query.length <= 400)
        val archive = archive(filename)
        if (query.isBlank())
            return (offset until minOf(offset + 40, archive.articleCount)).map { index ->
                val entry = archive.getEntryByTitle(index)
                ArticleEntry(entry.path, entry.title)
            }
        require(archive.hasFulltextIndex()) { "This pack has no full-text index." }
        val searcher = Searcher(archive)
        val request = Query(query)
        val search = searcher.search(request)
        val iterator = search.getResults(offset, 40)
        return try {
            buildList {
                while (iterator.hasNext()) {
                    val entry = iterator.next()
                    add(ArticleEntry(entry.path, entry.title))
                }
            }
        } finally {
            iterator.dispose()
            search.dispose()
            request.dispose()
            searcher.dispose()
        }
    }

    @Synchronized
    fun article(filename: String, path: String): Article {
        require(path.isNotBlank() && path.length <= 2000)
        val item = archive(filename).getEntryByPath(path).getItem(true)
        require(item.mimetype.startsWith("text/html") && item.size <= 4 * 1024 * 1024) {
            "This reader supports HTML articles up to 4 MB."
        }
        val blob = item.data
        val raw =
            try {
                blob.data.toString(Charsets.UTF_8)
            } finally {
                blob.dispose()
            }
        return Article(
            item.path,
            item.title,
            WikiHTML.render(item.title, raw, item.path),
            Jsoup.parse(raw).apply { select("script,style").remove() }.text(),
        )
    }

    @Synchronized
    fun search(query: String): List<Evidence> {
        val ignored =
            setOf(
                "what",
                "is",
                "are",
                "the",
                "an",
                "of",
                "about",
                "tell",
                "me",
                "please",
                "explain",
                "answer",
                "briefly",
                "using",
                "sources",
                "source",
                "wikipedia",
                "how",
                "does",
                "do",
                "and",
                "in",
                "to",
                "for",
            )
        val keywords = TextIndex.terms(query).filter { it !in ignored }.distinct().take(12)
        val lookup = keywords.joinToString(" ").ifBlank { query.take(400) }
        val preferred = WikiEdition.preferred(library.files("zim").map { it.name })
        return preferred
            .take(8)
            .flatMap { filename ->
                browse(filename, lookup, 0).take(3).map { entry ->
                    val article = article(filename, entry.path)
                    Evidence(
                        "",
                        article.title,
                        "$filename · ${article.path}",
                        article.text.take(2200),
                        "https://en.wikipedia.org/wiki/" +
                            URI(null, null, article.path.removePrefix("A/"), null).rawPath,
                    )
                }
            }
            .take(4)
    }
}
