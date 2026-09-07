package com.ethanrimes.thimvale

import java.security.MessageDigest
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

fun stableId(value: String): String =
    MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") {
        "%02x".format(it)
    }

fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

fun jsonArray(values: Iterable<JSONObject>) = JSONArray().apply { values.forEach(::put) }

data class Model(
    val id: String,
    val name: String,
    val family: String,
    val repository: String,
    val summary: String,
    val parameters: String,
    val memory: Int,
    val quant: String,
) {
    val fourB: Boolean
        get() = parameters.removeSuffix("B").toDoubleOrNull()?.let { it >= 3.5 && it < 4.5 } == true

    companion object {
        fun from(j: JSONObject) =
            Model(
                j.getString("id"),
                j.getString("name"),
                j.getString("family"),
                j.getString("repository"),
                j.getString("summary"),
                j.getString("parameters"),
                j.getInt("minimumMemoryGB"),
                j.optString("preferredQuant", "Q4_K_M"),
            )
    }
}

data class Evidence(
    val id: String,
    val title: String,
    val location: String,
    val text: String,
    val url: String = "",
) {
    fun json() =
        JSONObject()
            .put("id", id)
            .put("title", title)
            .put("location", location)
            .put("text", text)
            .put("url", url)

    companion object {
        fun from(j: JSONObject) =
            Evidence(
                j.getString("id"),
                j.getString("title"),
                j.getString("location"),
                j.getString("text"),
                j.optString("url"),
            )
    }
}

data class ToolEvent(
    val name: String,
    val input: String,
    val output: String = "",
    val state: String = "Running",
) {
    fun json() =
        JSONObject().put("name", name).put("input", input).put("output", output).put("state", state)

    companion object {
        fun from(j: JSONObject) =
            ToolEvent(
                j.getString("name"),
                j.getString("input"),
                j.optString("output"),
                j.optString("state"),
            )
    }
}

data class Message(
    val role: String,
    val text: String = "",
    val sources: List<Evidence> = emptyList(),
    val events: List<ToolEvent> = emptyList(),
    val raw: String = "",
    val id: String = UUID.randomUUID().toString(),
) {
    fun json() =
        JSONObject()
            .put("id", id)
            .put("role", role)
            .put("text", text)
            .put("raw", raw)
            .put("sources", jsonArray(sources.map { it.json() }))
            .put("events", jsonArray(events.map { it.json() }))

    companion object {
        fun from(j: JSONObject) =
            Message(
                j.getString("role"),
                j.optString("text"),
                j.optJSONArray("sources")?.objects()?.map(Evidence::from).orEmpty(),
                j.optJSONArray("events")?.objects()?.map(ToolEvent::from).orEmpty(),
                j.optString("raw"),
                j.getString("id"),
            )
    }
}

enum class Capability(val title: String) {
    KNOWLEDGE("Search knowledge"),
    LIST("List folders"),
    READ("Read files"),
    WRITE("Create files"),
    WEB("Web search"),
}

enum class Permission {
    DENY,
    ASK,
    ALLOW,
}

data class ToolCall(val tool: String, val args: JSONObject) {
    val capability: Capability
        get() =
            when (tool) {
                "search_knowledge" -> Capability.KNOWLEDGE
                "list_files" -> Capability.LIST
                "read_file" -> Capability.READ
                "write_file" -> Capability.WRITE
                "web_search" -> Capability.WEB
                else -> error("Unknown tool: $tool")
            }

    companion object {
        fun looksLikeCall(text: String): Boolean {
            val clean = visibleAnswer(text).trimStart()
            return Regex(
                    "^(?:\\[\\s*)?(?:search_knowledge|list_files|read_file|write_file|web_search)\\s*\\("
                )
                .containsMatchIn(clean) ||
                clean.startsWith("<tool_call") ||
                clean.startsWith("<|tool_call") ||
                clean.startsWith("<function") ||
                (clean.startsWith("{") && clean.contains("\"tool\""))
        }

        fun parse(text: String): ToolCall? {
            val clean =
                visibleAnswer(text)
                    .removePrefix("```json")
                    .removePrefix("```")
                    .removeSuffix("```")
                    .trim()
            if (!clean.startsWith("{")) return null
            val j =
                runCatching { JSONObject(clean) }
                    .getOrElse {
                        if (clean.contains("\"tool\"")) throw it
                        return null
                    }
            if (!j.has("tool")) return null
            require(j.length() == 2 && j.has("tool") && j.has("arguments")) {
                "Malformed tool call."
            }
            return ToolCall(j.getString("tool"), j.getJSONObject("arguments")).also {
                it.capability
            }
        }
    }
}

fun sourceExcerpt(source: Evidence): String {
    val excerpt = source.text.take(600)
    val boundary = Regex("[.!?](?:\\s|$)").findAll(excerpt).lastOrNull()?.range?.first
    val quoted = if (boundary != null) excerpt.take(boundary + 1) else excerpt
    return "From the retrieved source:\n\n“$quoted” [${source.id}]"
}

fun visibleAnswer(raw: String): String {
    val start = raw.indexOf("<think>")
    if (start < 0) return if ("<think>".startsWith(raw.trim()) && raw.isNotBlank()) "" else raw
    val end = raw.indexOf("</think>", start)
    return if (end < 0) raw.substring(0, start)
    else (raw.substring(0, start) + raw.substring(end + 8)).trimStart()
}

fun streamedAnswer(raw: String, work: Boolean): String {
    val text = visibleAnswer(raw)
    val start = text.trimStart()
    if (work && (ToolCall.looksLikeCall(text) || start == "[")) return ""
    if (
        work &&
            (start.startsWith("{") ||
                listOf("```json", "<tool_call>", "<function").any {
                    it.startsWith(start) || start.startsWith(it)
                })
    )
        return ""
    return text
}

data class WikiEdition(val series: String, val month: String) {
    companion object {
        private val format =
            Regex(
                "^(wikipedia_en_[a-z0-9_]+_(?:mini|nopic|maxi))_(20[0-9]{2}-(?:0[1-9]|1[0-2]))\\.zim$"
            )

        fun parse(name: String): WikiEdition? =
            format.matchEntire(name)?.let { WikiEdition(it.groupValues[1], it.groupValues[2]) }

        fun preferred(files: List<String>): List<String> =
            files.filter { parse(it) == null } +
                files
                    .mapNotNull { name -> parse(name)?.let { it.series to name } }
                    .groupBy({ it.first }, { it.second })
                    .values
                    .map { it.maxOrNull()!! }
    }
}

object ReviewPolicy {
    private const val DAY = 86_400_000L

    fun eligible(
        now: Long,
        firstUse: Long,
        interactions: Int,
        last: Long,
        lastVersion: String,
        version: String,
        enabled: Boolean,
        reviewed: Boolean,
        store: Boolean,
    ) =
        store &&
            enabled &&
            !reviewed &&
            interactions >= 5 &&
            now - firstUse >= 7 * DAY &&
            (last == 0L || now - last >= 120 * DAY) &&
            version != lastVersion
}
