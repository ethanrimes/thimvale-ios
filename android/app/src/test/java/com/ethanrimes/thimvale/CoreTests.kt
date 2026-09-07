package com.ethanrimes.thimvale

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CoreTests {
    @Test
    fun toolCallsAreStrictAndCapabilitiesIndependent() {
        assertEquals(
            Capability.WRITE,
            ToolCall.parse(
                    """{"tool":"write_file","arguments":{"folder":"abc","path":"note.txt","content":"hi"}}"""
                )!!
                .capability,
        )
        assertEquals(
            Capability.READ,
            ToolCall.parse("""{"tool":"read_file","arguments":{}}""")!!.capability,
        )
        assertNull(ToolCall.parse("Ordinary answer"))
        assertThrows(Exception::class.java) {
            ToolCall.parse("""{"tool":"shell","arguments":{}}""")
        }
        assertThrows(Exception::class.java) {
            ToolCall.parse("""{"tool":"read_file","arguments":{},"approved":true}""")
        }
    }

    @Test
    fun streamsHideOnlyControlEnvelopesAndIncompleteThoughts() {
        assertEquals("", streamedAnswer("<thi", false))
        assertEquals("", streamedAnswer("<think>unfinished", false))
        assertEquals("Answer [1]", streamedAnswer("<think>text</think>Answer [1]", true))
        assertEquals("", streamedAnswer("{\"tool\":", true))
        assertEquals("{\"count\":2}", streamedAnswer("{\"count\":2}", false))
        assertEquals("Hello", streamedAnswer("Hello", true))
    }

    @Test
    fun pathsStayInsideSelectedFolder() {
        assertEquals(listOf("notes", "trip.md"), TextIndex.pathParts("notes/trip.md"))
        listOf("../secrets", "/root", "notes//file", "a/./b", "a/../b", "a\\b", "a\u0000b")
            .forEach { path ->
                assertThrows(IllegalArgumentException::class.java) { TextIndex.pathParts(path) }
            }
    }

    @Test
    fun vectorsAreCompactAndCompressionPreservesUnicode() {
        val text = "Bowline knots form a fixed loop. Café 日本語. ".repeat(50)
        val compressed = TextIndex.compress(text)
        assertTrue(compressed.size < text.toByteArray().size / 4)
        assertEquals(text, TextIndex.decompress(compressed))
        assertEquals(256, TextIndex.vector(text).size)
        assertTrue(
            TextIndex.similarity(TextIndex.vector("bowline knot"), TextIndex.vector(text)) >
                TextIndex.similarity(TextIndex.vector("quantum physics"), TextIndex.vector(text))
        )
        assertTrue(TextIndex.chunks(text).all { it.length <= 1400 })
    }

    @Test
    fun updatesMatchExactSeriesAndKeepUnknownImports() {
        assertNull(WikiEdition.parse("../../wikipedia_en_all_mini_2026-01.zim"))
        assertNull(WikiEdition.parse("wikipedia_en_all_mini_2026-13.zim"))
        val files =
            listOf(
                "wikipedia_en_knots_maxi_2026-01.zim",
                "wikipedia_en_knots_maxi_2026-07.zim",
                "wikipedia_en_all_mini_2026-06.zim",
                "my-wikipedia.zim",
            )
        assertEquals(files.drop(1).toSet(), WikiEdition.preferred(files).toSet())
        assertNotEquals(WikiEdition.parse(files[1])!!.series, WikiEdition.parse(files[2])!!.series)
    }

    @Test
    fun reviewsAreInfrequentOptOutAndStoreOnly() {
        val day = 86_400_000L
        fun eligible(
            store: Boolean = true,
            reviewed: Boolean = false,
            enabled: Boolean = true,
            interactions: Int = 5,
            last: Long = 0,
            version: String = "",
        ) =
            ReviewPolicy.eligible(
                200 * day,
                day,
                interactions,
                last,
                version,
                "0.1.2",
                enabled,
                reviewed,
                store,
            )
        assertTrue(eligible())
        assertFalse(eligible(store = false))
        assertFalse(eligible(reviewed = true))
        assertFalse(eligible(enabled = false))
        assertFalse(eligible(interactions = 4))
        assertFalse(eligible(last = 100 * day))
        assertFalse(eligible(version = "0.1.2"))
        assertTrue(eligible(last = 79 * day))
    }

    @Test
    fun untrustedWikipediaCannotLoadNetworkResourcesOrScripts() {
        val output =
            WikiHTML.render(
                "Bowline",
                """<script>alert(1)</script><img src="https://evil.test/x"><iframe src="https://evil.test"></iframe><a href="javascript:alert(1)">Bad</a><a href="Sheet_bend">Sheet bend</a><h2 id="History">History</h2><p>Text</p>""",
                "Bowline",
            )
        assertFalse(output.contains("<script"))
        assertFalse(output.contains("<img"))
        assertFalse(output.contains("<iframe"))
        assertFalse(output.contains("javascript:"))
        assertTrue(output.contains("https://offline.thimvale.invalid/Sheet_bend"))
        assertTrue(output.contains("default-src 'none'"))
        assertTrue(output.contains("id=\"History\""))
        assertNull(WikiHTML.link("file:///private", "Bowline"))
        assertNull(WikiHTML.link("https://user:pass@evil.test/", "Bowline"))
        assertEquals(
            "https://offline.thimvale.invalid/Sheet_bend",
            WikiHTML.link("https://en.wikipedia.org/wiki/Sheet_bend", "Bowline"),
        )
    }

    @Test
    fun messagesRoundTripSourcesAndToolStates() {
        val original =
            Message(
                "assistant",
                "A loop [1]",
                listOf(Evidence("1", "Bowline", "knots.zim", "Fixed loop")),
                listOf(ToolEvent("search_knowledge", "bowline", "Found", "Completed")),
                "tokens",
            )
        assertEquals(original, Message.from(JSONObject(original.json().toString())))
    }
}
