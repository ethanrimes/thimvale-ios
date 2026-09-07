package com.ethanrimes.thimvale

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.parser.Parser

data class RemoteFile(
    val name: String,
    val url: String,
    val bytes: Long,
    val sha256: String,
    val title: String = name,
    val license: String = "",
) {
    fun json() =
        JSONObject()
            .put("name", name)
            .put("url", url)
            .put("bytes", bytes)
            .put("sha256", sha256)
            .put("title", title)
            .put("license", license)

    companion object {
        fun from(j: JSONObject) =
            RemoteFile(
                j.getString("name"),
                j.getString("url"),
                j.getLong("bytes"),
                j.optString("sha256"),
                j.optString("title"),
                j.optString("license"),
            )
    }
}

class Network(private val library: Library) {
    private val http =
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(45, TimeUnit.SECONDS)
            .build()

    private fun body(request: Request): String =
        http.newCall(request).execute().use { response ->
            check(response.isSuccessful) {
                when (response.code) {
                    401,
                    403 -> "Access denied. Check the token and repository license terms."
                    else -> "The server returned HTTP ${response.code}. Try again later."
                }
            }
            val input = response.body ?: error("The server returned no data.")
            require(input.contentLength() <= 12 * 1024 * 1024) { "Server response is too large." }
            input.byteStream().use { stream ->
                val bytes = stream.readBounded(12 * 1024 * 1024 + 1)
                require(bytes.size <= 12 * 1024 * 1024) { "Server response is too large." }
                bytes.toString(Charsets.UTF_8)
            }
        }

    private fun hub(url: String): String =
        body(
            Request.Builder()
                .url(url)
                .apply {
                    library.secrets
                        .get("huggingface")
                        .takeIf { it.isNotBlank() }
                        ?.let { header("Authorization", "Bearer $it") }
                }
                .build()
        )

    suspend fun searchModels(query: String): List<Model> =
        withContext(Dispatchers.IO) {
            val url =
                "https://huggingface.co/api/models"
                    .toHttpUrl()
                    .newBuilder()
                    .addQueryParameter("search", query)
                    .addQueryParameter("filter", "gguf")
                    .addQueryParameter("sort", "downloads")
                    .addQueryParameter("direction", "-1")
                    .addQueryParameter("limit", "40")
                    .build()
            JSONArray(hub(url.toString())).objects().map { j ->
                val id = j.getString("id")
                Model(id, id.substringAfter('/'), "Hugging Face", id, id, "GGUF", 0, "Q4_K_M")
            }
        }

    suspend fun modelFiles(repository: String): List<RemoteFile> =
        withContext(Dispatchers.IO) {
            require(
                Regex("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+").matches(repository) &&
                    repository.split('/').none { it == "." || it == ".." }
            ) {
                "Enter a repository in owner/model format."
            }
            val json = JSONObject(hub("https://huggingface.co/api/models/$repository?blobs=true"))
            val sha = json.getString("sha")
            require(Regex("[a-f0-9]{40}").matches(sha)) { "The repository revision is invalid." }
            val license = json.optJSONObject("cardData")?.optString("license").orEmpty()
            json
                .getJSONArray("siblings")
                .objects()
                .filter { j ->
                    j.getString("rfilename").lowercase().let {
                        it.endsWith(".gguf") &&
                            !it.contains("mmproj") &&
                            !it.contains("-of-") &&
                            !it.contains("mtp")
                    }
                }
                .map { j ->
                    val path = j.getString("rfilename")
                    val lfs =
                        j.optJSONObject("lfs") ?: error("This file has no verified LFS metadata.")
                    val url =
                        "https://huggingface.co"
                            .toHttpUrl()
                            .newBuilder()
                            .addPathSegments(repository)
                            .addPathSegment("resolve")
                            .addPathSegment(sha)
                            .addPathSegments(path)
                            .build()
                    RemoteFile(
                        stableId(repository + sha + path).take(12) +
                            "-" +
                            path.substringAfterLast('/'),
                        url.toString(),
                        lfs.getLong("size"),
                        lfs.getString("sha256"),
                        path.substringAfterLast('/'),
                        license,
                    )
                }
                .sortedBy { it.bytes }
                .also {
                    require(it.isNotEmpty()) {
                        "No single-file text GGUFs found. Sharded weights and vision projectors aren't supported."
                    }
                }
        }

    suspend fun wikipedia(): List<RemoteFile> =
        withContext(Dispatchers.IO) {
            val xml =
                body(
                    Request.Builder()
                        .url(
                            "https://library.kiwix.org/catalog/v2/entries?lang=eng&category=wikipedia&count=200"
                        )
                        .build()
                )
            Jsoup.parse(xml, "", Parser.xmlParser())
                .select("entry")
                .mapNotNull { entry ->
                    val link =
                        entry.select("link").firstOrNull { it.attr("type") == "application/x-zim" }
                            ?: return@mapNotNull null
                    val remote = link.attr("href").removeSuffix(".meta4").toHttpUrl()
                    val name = remote.pathSegments.last()
                    if (
                        WikiEdition.parse(name) == null ||
                            remote.host !in setOf("download.kiwix.org", "lb.download.kiwix.org") ||
                            !entry.select("tags").text().contains("_ftindex:yes")
                    )
                        return@mapNotNull null
                    val url = "https://download.kiwix.org/zim/wikipedia/$name"
                    val size = link.attr("length").toLongOrNull() ?: return@mapNotNull null
                    val edition = WikiEdition.parse(name)!!
                    RemoteFile(
                        name,
                        url,
                        size,
                        "",
                        (entry.selectFirst("title")?.text() ?: name) +
                            " · " +
                            edition.series.substringAfterLast('_') +
                            " · " +
                            edition.month,
                        "Wikipedia contributors · CC BY-SA",
                    )
                }
                .sortedBy { it.bytes }
                .also {
                    require(it.isNotEmpty()) {
                        "No compatible indexed English Wikipedia packs were returned."
                    }
                }
        }

    suspend fun verifiedDownload(file: RemoteFile): RemoteFile =
        withContext(Dispatchers.IO) {
            if (file.name.endsWith(".zim")) {
                val xml = body(Request.Builder().url(file.url + ".meta4").build())
                val metadata = Jsoup.parse(xml, "", Parser.xmlParser())
                val hash =
                    metadata.select("hash").firstOrNull { it.attr("type") == "sha-256" }?.text()
                        ?: error("No SHA-256 checksum is available for this pack.")
                val size =
                    metadata.selectFirst("size")?.text()?.toLongOrNull()
                        ?: error("No verified size is available.")
                file.copy(bytes = size, sha256 = hash)
            } else {
                // Resolve gated repositories with OkHttp, which strips Authorization on cross-host
                // redirects.
                // DownloadManager receives only the final HTTPS URL, never the account token.
                val request =
                    Request.Builder()
                        .url(file.url)
                        .head()
                        .apply {
                            library.secrets
                                .get("huggingface")
                                .takeIf { it.isNotBlank() }
                                ?.let { header("Authorization", "Bearer $it") }
                        }
                        .build()
                http.newCall(request).execute().use { response ->
                    check(response.isSuccessful) {
                        "The download couldn't be authorized. Accept its license and check your token."
                    }
                    val url = response.request.url
                    require(
                        url.isHttps &&
                            (url.host == "huggingface.co" ||
                                url.host.endsWith(".huggingface.co") ||
                                url.host == "hf.co" ||
                                url.host.endsWith(".hf.co"))
                    ) {
                        "Unexpected download host."
                    }
                    file.copy(url = url.toString())
                }
            }
        }

    suspend fun webSearch(query: String): List<Evidence> =
        withContext(Dispatchers.IO) {
            require(query.isNotBlank() && query.length <= 400) { "Use a shorter search query." }
            val key = library.secrets.get("brave")
            require(key.isNotBlank()) { "Add a Brave Search API key in Settings." }
            val url =
                "https://api.search.brave.com/res/v1/web/search"
                    .toHttpUrl()
                    .newBuilder()
                    .addQueryParameter("q", query)
                    .addQueryParameter("count", "5")
                    .build()
            val result =
                JSONObject(
                    body(Request.Builder().url(url).header("X-Subscription-Token", key).build())
                )
            result.optJSONObject("web")?.optJSONArray("results")?.objects().orEmpty().take(5).map {
                Evidence(
                    "",
                    it.getString("title"),
                    "Brave web search",
                    Jsoup.parse(it.optString("description")).text(),
                    it.getString("url"),
                )
            }
        }
}
