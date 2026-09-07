package com.ethanrimes.thimvale

import android.content.Context
import android.content.ContextWrapper
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StorageIntegrationTests {
    @Test
    fun actualDocumentProviderReadCreateIndexReplaceAndDisconnect() = runBlocking {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val root = File(base.cacheDir, "storage-regression-${UUID.randomUUID()}").apply { mkdirs() }
        val context =
            object : ContextWrapper(base) {
                override fun getFilesDir() = File(root, "files").apply { mkdirs() }

                override fun getExternalFilesDir(type: String?) =
                    File(root, type ?: "external").apply { mkdirs() }
            }
        val library = Library(context)
        val knowledge = Knowledge(library)
        val tree =
            DocumentsContract.buildTreeDocumentUri("com.ethanrimes.thimvale.debug.fixtures", "root")
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, "root")
        val directory =
            DocumentsContract.createDocument(
                base.contentResolver,
                parent,
                DocumentsContract.Document.MIME_TYPE_DIR,
                UUID.randomUUID().toString(),
            )!!
        val scoped =
            DocumentsContract.buildTreeDocumentUri(
                tree.authority,
                DocumentsContract.getDocumentId(directory),
            )
        base.grantUriPermission(
            base.packageName,
            scoped,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        library.state.change {
            it.put(
                "folders",
                JSONArray()
                    .put(
                        JSONObject()
                            .put("id", "test")
                            .put("name", "Fixture folder")
                            .put("uri", scoped.toString())
                    ),
            )
        }
        assertTrue(
            knowledge
                .create("test", "notes.txt", "A bowline creates a fixed loop in a rope.")
                .contains("Created")
        )
        assertTrue(knowledge.read("test", "notes.txt").text.contains("fixed loop"))
        assertTrue(knowledge.list("test", "").contains("notes.txt"))
        assertThrows(Exception::class.java) { knowledge.create("test", "notes.txt", "overwrite") }
        assertThrows(Exception::class.java) { knowledge.read("test", "../notes.txt") }
        knowledge.indexFolder("test")
        assertTrue(knowledge.search("bowline").any { it.text.contains("fixed loop") })
        val note =
            DocumentsContract.buildDocumentUriUsingTree(
                scoped,
                DocumentsContract.getTreeDocumentId(scoped) + "/notes.txt",
            )
        base.contentResolver.openOutputStream(note, "wt")!!.use {
            it.write("New text about a zeppelin.".toByteArray())
        }
        knowledge.indexFolder("test")
        assertTrue(knowledge.search("bowline").isEmpty())
        assertTrue(knowledge.search("zeppelin").isNotEmpty())
        knowledge.disconnect("test")
        assertTrue(knowledge.search("zeppelin").isEmpty())
        assertTrue(knowledge.folders().isEmpty())
        DocumentsContract.deleteDocument(base.contentResolver, note)
        DocumentsContract.deleteDocument(base.contentResolver, directory)
        Unit
    }

    @Test
    fun systemDownloadVerifiesRealPackAndRejectsWrongChecksum() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<ThimvaleApplication>()
        val library = app.library
        val network = Network(library)
        val downloads = Downloads(library)
        val originalCellular = library.state.read().optBoolean("cellular", false)
        // Fresh emulators may expose their host connection as a metered cellular network.
        library.state.change { it.put("cellular", true) }
        val pack =
            network.verifiedDownload(
                network.wikipedia().first { it.name.startsWith("wikipedia_en_knots") }
            )
        val valid = pack.copy(name = "download-regression-${UUID.randomUUID()}.zim")
        val id = downloads.enqueue(valid)
        try {
            withTimeout(120_000) {
                while (!library.file(valid.name).exists()) {
                    delay(1000)
                    downloads.verify(id)
                }
            }
            assertEquals(valid.bytes, library.file(valid.name).length())
            val bad =
                pack.copy(name = "bad-checksum-${UUID.randomUUID()}.zim", sha256 = "0".repeat(64))
            val badId = downloads.enqueue(bad)
            try {
                withTimeout(120_000) {
                    while (
                        downloads.statuses().none {
                            it.id == badId && it.state.contains("Checksum verification failed")
                        }
                    ) {
                        delay(1000)
                        downloads.verify(badId)
                    }
                }
                assertFalse(library.file(bad.name).exists())
            } finally {
                downloads.cancel(badId)
            }
        } finally {
            downloads.cancel(id)
            // This UUID-named file was created by this test, not selected from user data.
            library.file(valid.name).delete()
            library.state.change { it.put("cellular", originalCellular) }
        }
    }
}
