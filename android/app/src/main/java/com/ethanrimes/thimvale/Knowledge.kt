package com.ethanrimes.thimvale

import android.content.ContentValues
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.DeflaterOutputStream
import java.util.zip.InflaterInputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.jsoup.Jsoup

data class Folder(val id: String, val name: String, val uri: String)

object TextIndex {
    fun terms(text: String): List<String> =
        Regex("[\\p{L}\\p{N}]{2,}")
            .findAll(text.lowercase())
            .map { it.value.take(80) }
            .take(20_000)
            .toList()

    // 2048-bit lexical feature vectors, not a claim of semantic sentence embeddings.
    fun vector(text: String): ByteArray =
        ByteArray(256).apply {
            terms(text).forEach { term ->
                val bit = (term.hashCode() and Int.MAX_VALUE) % 2048
                this[bit / 8] = (this[bit / 8].toInt() or (1 shl (bit % 8))).toByte()
            }
        }

    fun similarity(a: ByteArray, b: ByteArray): Double {
        var intersection = 0
        var union = 0
        a.indices.forEach { i ->
            val x = a[i].toInt() and 255
            val y = b[i].toInt() and 255
            intersection += Integer.bitCount(x and y)
            union += Integer.bitCount(x or y)
        }
        return if (union == 0) 0.0 else intersection.toDouble() / union
    }

    fun compress(text: String): ByteArray =
        ByteArrayOutputStream()
            .also { out -> DeflaterOutputStream(out).use { it.write(text.toByteArray()) } }
            .toByteArray()

    fun decompress(bytes: ByteArray): String =
        InflaterInputStream(bytes.inputStream()).use { it.readBytes().toString(Charsets.UTF_8) }

    fun chunks(text: String): List<String> =
        if (text.isBlank()) emptyList()
        else (text.indices step 1100).map { text.substring(it, minOf(text.length, it + 1400)) }

    fun pathParts(path: String): List<String> =
        path.split('/').also { parts ->
            require(
                path.length <= 1000 &&
                    parts.all {
                        it.isNotBlank() &&
                            it != "." &&
                            it != ".." &&
                            !it.contains('\\') &&
                            it.none(Char::isISOControl)
                    }
            ) {
                "Use a relative path inside a connected folder."
            }
        }
}

class Knowledge(private val library: Library) {
    private val resolver = library.context.contentResolver
    private val db =
        SQLiteDatabase.openOrCreateDatabase(
                File(library.context.filesDir, "knowledge.sqlite"),
                null,
            )
            .apply {
                execSQL(
                    "CREATE TABLE IF NOT EXISTS passages (id INTEGER PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL, location TEXT NOT NULL, content BLOB NOT NULL, vector BLOB NOT NULL)"
                )
                execSQL("CREATE VIRTUAL TABLE IF NOT EXISTS keywords USING fts4(terms)")
            }

    fun folders(): List<Folder> =
        library.state
            .read()
            .optJSONArray("folders")
            ?.objects()
            ?.map { Folder(it.getString("id"), it.getString("name"), it.getString("uri")) }
            .orEmpty()

    fun connect(uri: Uri) {
        val grant = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            resolver.takePersistableUriPermission(uri, grant)
        } catch (_: SecurityException) {
            resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val root =
            DocumentFile.fromTreeUri(library.context, uri)
                ?: error("This provider cannot share a folder.")
        require(root.canRead()) { "This folder isn't readable." }
        val existing = folders()
        if (existing.any { it.uri == uri.toString() }) return
        library.state.change {
            it.put(
                "folders",
                jsonArray(
                    existing.map { f ->
                        JSONObject().put("id", f.id).put("name", f.name).put("uri", f.uri)
                    } +
                        JSONObject()
                            .put("id", stableId(uri.toString()).take(12))
                            .put("name", root.name ?: "Folder")
                            .put("uri", uri.toString())
                ),
            )
        }
    }

    fun root(id: String): DocumentFile {
        val folder =
            folders().firstOrNull { it.id == id } ?: error("That folder is no longer connected.")
        return DocumentFile.fromTreeUri(library.context, Uri.parse(folder.uri))?.takeIf {
            it.canRead()
        } ?: error("Folder access was revoked. Reconnect it in Knowledge.")
    }

    private fun resolve(id: String, path: String): DocumentFile {
        var file = root(id)
        for (part in TextIndex.pathParts(path)) file =
            file.findFile(part) ?: error("This file doesn't exist in the connected folder.")
        return file
    }

    fun list(id: String, path: String): String =
        (if (path.isBlank()) root(id) else resolve(id, path)).listFiles().take(200).joinToString(
            "\n"
        ) {
            (if (it.isDirectory) "folder " else "file ") + it.name
        }

    private fun readDocument(file: DocumentFile): String {
        require(file.isFile && file.length() <= 1024 * 1024) {
            "Choose a text file no larger than 1 MB."
        }
        val name = file.name.orEmpty()
        require(
            name.substringAfterLast('.', "").lowercase() in
                setOf("txt", "md", "csv", "json", "html", "htm", "log")
        ) {
            "This version reads TXT, Markdown, CSV, JSON, HTML and log files."
        }
        val bytes =
            resolver.openInputStream(file.uri)?.use { it.readBounded(1024 * 1024 + 1) }
                ?: error("Cannot read this file.")
        require(bytes.size <= 1024 * 1024) { "This file exceeds the 1 MB limit." }
        val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        return if (name.endsWith(".html") || name.endsWith(".htm")) Jsoup.parse(text).text()
        else text
    }

    fun read(id: String, path: String): Evidence {
        val file = resolve(id, path)
        return Evidence("", file.name ?: path, "$id/$path", readDocument(file).take(12_000))
    }

    fun create(id: String, path: String, content: String): String {
        require(content.toByteArray().size <= 256 * 1024) { "File writes are limited to 256 KB." }
        val parts = TextIndex.pathParts(path)
        val directory =
            if (parts.size == 1) root(id) else resolve(id, parts.dropLast(1).joinToString("/"))
        require(directory.isDirectory && directory.canWrite()) { "This folder is read-only." }
        require(directory.findFile(parts.last()) == null) {
            "A file with this name already exists. Overwriting is not supported."
        }
        val file =
            directory.createFile("text/plain", parts.last())
                ?: error("The provider couldn't create this file.")
        try {
            resolver.openOutputStream(file.uri, "wt")?.use { it.write(content.toByteArray()) }
                ?: error("The new file isn't writable.")
        } catch (e: Exception) {
            file.delete()
            throw e
        }
        return "Created ${file.name} in the connected folder."
    }

    @Synchronized
    private fun removeSource(source: String) {
        db.execSQL(
            "DELETE FROM keywords WHERE rowid IN (SELECT id FROM passages WHERE source = ?)",
            arrayOf(source),
        )
        db.delete("passages", "source = ?", arrayOf(source))
    }

    suspend fun disconnect(id: String) =
        withContext(Dispatchers.IO) {
            val folder = folders().first { it.id == id }
            synchronized(this@Knowledge) {
                db.beginTransaction()
                try {
                    val prefix = "$id/"
                    db.rawQuery(
                            "SELECT DISTINCT source FROM passages WHERE substr(source, 1, ?) = ?",
                            arrayOf(prefix.length.toString(), prefix),
                        )
                        .use { c -> while (c.moveToNext()) removeSource(c.getString(0)) }
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
            }
            library.state.change {
                it.put(
                    "folders",
                    jsonArray(
                        folders()
                            .filter { f -> f.id != id }
                            .map { f ->
                                JSONObject().put("id", f.id).put("name", f.name).put("uri", f.uri)
                            }
                    ),
                )
            }
            runCatching {
                resolver.releasePersistableUriPermission(
                    Uri.parse(folder.uri),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
        }

    suspend fun indexFolder(id: String): String =
        withContext(Dispatchers.IO) {
            val collected = mutableListOf<Triple<String, String, String>>()
            var skipped = 0
            var totalCharacters = 0
            fun visit(dir: DocumentFile, prefix: String, depth: Int) {
                require(depth <= 12) { "Folder nesting exceeds the 12-level limit." }
                dir.listFiles().forEach { file ->
                    require(collected.size < 1000) { "Index up to 1,000 text files per folder." }
                    val path = prefix + (file.name ?: return@forEach)
                    if (file.isDirectory) visit(file, "$path/", depth + 1)
                    else {
                        val text =
                            try {
                                readDocument(file)
                            } catch (_: Exception) {
                                skipped++
                                return@forEach
                            }
                        totalCharacters += text.length
                        require(totalCharacters <= 16 * 1024 * 1024) {
                            "Index up to 16 million text characters per folder. Split larger collections into folders."
                        }
                        collected += Triple(path, file.name ?: path, text)
                    }
                }
            }
            visit(root(id), "", 0)
            synchronized(this@Knowledge) {
                db.beginTransaction()
                try {
                    val prefix = "$id/"
                    db.rawQuery(
                            "SELECT DISTINCT source FROM passages WHERE substr(source, 1, ?) = ?",
                            arrayOf(prefix.length.toString(), prefix),
                        )
                        .use { c -> while (c.moveToNext()) removeSource(c.getString(0)) }
                    collected.forEach { (path, title, text) ->
                        TextIndex.chunks(text).forEachIndexed { index, chunk ->
                            val row =
                                db.insertOrThrow(
                                    "passages",
                                    null,
                                    ContentValues().apply {
                                        put("source", "$id/$path")
                                        put("title", title)
                                        put("location", "$id/$path · passage ${index + 1}")
                                        put("content", TextIndex.compress(chunk))
                                        put("vector", TextIndex.vector(chunk))
                                    },
                                )
                            db.execSQL(
                                "INSERT INTO keywords(rowid, terms) VALUES (?, ?)",
                                arrayOf<Any>(
                                    row,
                                    TextIndex.terms(chunk).distinct().joinToString(" "),
                                ),
                            )
                        }
                    }
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
            }
            "Indexed ${collected.size} text files; skipped $skipped unsupported or unreadable files."
        }

    @Synchronized
    fun search(query: String): List<Evidence> {
        val terms = TextIndex.terms(query).distinct().take(24)
        if (terms.isEmpty()) return emptyList()
        val vector = TextIndex.vector(query)
        val matches = mutableListOf<Pair<Double, Evidence>>()
        val expression = terms.joinToString(" OR ") { "\"$it\"" }
        db.rawQuery(
                "SELECT p.title, p.location, p.content, p.vector FROM passages p JOIN keywords k ON k.rowid = p.id WHERE keywords MATCH ? LIMIT 500",
                arrayOf(expression),
            )
            .use { c ->
                while (c.moveToNext()) matches +=
                    TextIndex.similarity(vector, c.getBlob(3)) to
                        Evidence(
                            "",
                            c.getString(0),
                            c.getString(1),
                            TextIndex.decompress(c.getBlob(2)),
                        )
            }
        return matches.sortedByDescending { it.first }.take(4).map { it.second }
    }

    suspend fun importLibrary(uri: Uri) =
        withContext(Dispatchers.IO) {
            val document =
                DocumentFile.fromSingleUri(library.context, uri)
                    ?: error("Cannot open this document.")
            val name = document.name ?: error("The file has no name.")
            require(name.endsWith(".gguf") || name.endsWith(".zim")) {
                "Choose a GGUF model or ZIM archive."
            }
            val target = library.file(name)
            require(!target.exists()) { "A file with this name is already installed." }
            val pending = File.createTempFile("import-", ".pending", library.directory)
            try {
                resolver.openInputStream(uri)?.use { input ->
                    pending.outputStream().use { out ->
                        val buffer = ByteArray(128 * 1024)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            require(library.directory.usableSpace > n + 64L * 1024 * 1024) {
                                "Not enough free storage."
                            }
                            out.write(buffer, 0, n)
                        }
                    }
                } ?: error("Cannot read the selected file.")
                Downloads.validateHeader(pending, target.extension)
                require(!target.exists() && pending.renameTo(target)) {
                    "Cannot install this file."
                }
            } finally {
                pending.delete()
            }
        }
}
