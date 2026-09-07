package com.ethanrimes.thimvale

import android.content.Context
import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeTests {
    private val base: Context
        get() = ApplicationProvider.getApplicationContext()

    private fun isolated(): Context {
        val dir = File(base.cacheDir, "regression-${UUID.randomUUID()}").apply { mkdirs() }
        return object : ContextWrapper(base) {
            override fun getFilesDir(): File = File(dir, "files").apply { mkdirs() }

            override fun getExternalFilesDir(type: String?): File =
                File(dir, type ?: "external").apply { mkdirs() }
        }
    }

    private fun fixture(name: String): File =
        File(base.getExternalFilesDir("fixtures"), name).also {
            assertTrue("Run scripts/install-test-fixtures.sh first: $name", it.exists())
        }

    @Test
    fun actualModelStreamsReusesAndReleasesWeights() = runBlocking {
        val runtime = NativeEngine(base)
        val file = fixture("smoke-model.gguf")
        try {
            runtime.select(file)
            assertEquals(file.absolutePath, runtime.loadedPath)
            val messages =
                JSONArray()
                    .put(JSONObject().put("role", "system").put("content", "Answer briefly."))
                    .put(
                        JSONObject()
                            .put("role", "user")
                            .put("content", "Name the capital of France.")
                    )
            var callbacks = 0
            val answer = runtime.answer(file, messages, 48) { callbacks++ }
            assertTrue(answer.isNotBlank())
            assertTrue(callbacks > 2)
            assertEquals(file.absolutePath, runtime.loadedPath)
            assertTrue(runtime.answer(file, messages, 24) {}.isNotBlank())
            val job =
                async(Dispatchers.IO) {
                    runCatching {
                        runtime.answer(file, messages, 512) { if (it.length > 12) runtime.stop() }
                    }
                }
            assertTrue(job.await().isFailure)
            runtime.release()
            assertNull(runtime.loadedPath)
            assertTrue(runtime.answer(file, messages, 24) {}.isNotBlank())
        } finally {
            runtime.release()
        }
    }

    @Test
    fun actualWikipediaBrowseSearchReadAndMissingPage() {
        val library = Library(isolated())
        fixture("smoke-wikipedia.zim").copyTo(library.file("smoke-wikipedia.zim"))
        val wiki = Wikipedia(library)
        try {
            val titles = wiki.browse("smoke-wikipedia.zim", "", 0)
            assertEquals(40, titles.size)
            val hits = wiki.browse("smoke-wikipedia.zim", "bowline", 0)
            val bowline = hits.first { it.title.equals("Bowline", true) }
            val article = wiki.article("smoke-wikipedia.zim", bowline.path)
            assertTrue(article.text.contains("fixed loop", true))
            assertTrue(article.html.contains("Sheet_bend"))
            assertTrue(article.text.length > 6000)
            assertTrue(wiki.search("bowline").isNotEmpty())
            assertThrows(Exception::class.java) {
                wiki.article("smoke-wikipedia.zim", "definitely_missing_thimvale_page")
            }
        } finally {
            wiki.close()
        }
    }

    @Test
    fun catalogAndDownloadMetadataAreReal() = runBlocking {
        val library = Library(isolated())
        assertEquals(39, library.models.size)
        assertTrue(library.models.count { it.fourB } >= 6)
        val network = Network(library)
        val files = network.modelFiles("LiquidAI/LFM2.5-230M-GGUF")
        assertTrue(
            files.any {
                it.title.contains("Q4_K_M") && it.bytes > 100_000_000 && it.sha256.length == 64
            }
        )
        val packs = network.wikipedia()
        assertTrue(packs.any { it.name.startsWith("wikipedia_en_all_mini") })
        val knots = packs.first { it.name.startsWith("wikipedia_en_knots") }
        val metadata = network.verifiedDownload(knots)
        assertEquals(64, metadata.sha256.length)
        assertTrue(metadata.bytes > 1_000_000)
    }

    @Test
    fun libraryScopesAndConcurrentPersistence() = runBlocking {
        val context = isolated()
        val library = Library(context)
        assertThrows(Exception::class.java) { library.file("../private.gguf") }
        assertEquals(Permission.ASK, library.permission(Capability.WRITE))
        library.setPermission(Capability.READ, Permission.ALLOW)
        assertEquals(Permission.ASK, library.permission(Capability.WRITE))
        assertEquals(Permission.ALLOW, Library(context).permission(Capability.READ))
        (1..20)
            .map { index ->
                async(Dispatchers.IO) { LocalState(context).change { it.put("key$index", index) } }
            }
            .awaitAll()
        assertTrue((1..20).all { library.state.read().getInt("key$it") == it })
        assertEquals(4, "abcdef".byteInputStream().readBounded(4).size)
    }
}
