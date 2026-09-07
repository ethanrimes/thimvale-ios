package com.ethanrimes.thimvale

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import java.io.File
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class AppNavigationTests {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private fun model(): AppModel = ViewModelProvider(compose.activity)[AppModel::class.java]

    private fun installFixture(extension: String): String {
        val model = model()
        val name = "regression-${if (extension == "gguf") "model" else "wikipedia"}.$extension"
        val source =
            File(
                compose.activity.getExternalFilesDir("fixtures"),
                "smoke-${if (extension == "gguf") "model" else "wikipedia"}.$extension",
            )
        val destination = model.library.file(name)
        if (!destination.exists()) source.copyTo(destination)
        compose.runOnIdle { model.refresh() }
        return name
    }

    @Test
    fun modelFiltersAndIndependentPermissionControls() {
        compose.onNodeWithContentDescription("Models", useUnmergedTree = true).performClick()
        compose.onNodeWithText("4B").performClick()
        compose.onNodeWithText("Qwen 3.5", substring = false).assertExists()
        compose.onNodeWithText("0.8B", substring = false).assertDoesNotExist()
        compose.onNodeWithContentDescription("Permissions", useUnmergedTree = true).performClick()
        compose.onNodeWithText("Search knowledge").assertExists()
        val model = model()
        val previous = model.library.permission(Capability.KNOWLEDGE)
        compose.onAllNodesWithText("Off").onFirst().performClick()
        assertEquals(Permission.DENY, model.library.permission(Capability.KNOWLEDGE))
        assertEquals(Permission.ASK, model.library.permission(Capability.WRITE))
        compose.runOnIdle {
            model.library.setPermission(Capability.KNOWLEDGE, previous)
            model.refresh()
        }
    }

    @Test
    fun reviewOptOutAndUpdateScreen() {
        compose.onNodeWithContentDescription("Settings").performClick()
        compose
            .onNodeWithContentDescription("I've already reviewed")
            .performScrollTo()
            .performClick()
        compose.onNodeWithContentDescription("I've already reviewed").assertIsOn()
        compose.onNodeWithContentDescription("I've already reviewed").performClick()
        compose.onNodeWithContentDescription("I've already reviewed").assertIsOff()
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithContentDescription("Knowledge", useUnmergedTree = true).performClick()
        compose.onNodeWithText("Check pack updates").performClick()
        compose.onNodeWithText("Wikipedia updates", substring = false).assertExists()
        compose.onNodeWithText("Check now").assertExists()
    }

    @Test
    fun approvalRechecksRevocationAndRejectsUnknownFolders() {
        val model = model()
        val answer = Message("assistant")
        compose.runOnIdle {
            model.change { it.copy(tab = 0, messages = listOf(answer), work = true) }
            model.library.setPermission(Capability.KNOWLEDGE, Permission.ASK)
        }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        try {
            val job =
                scope.launch {
                    model.execute(
                        ToolCall("search_knowledge", JSONObject().put("query", "bowline")),
                        answer.id,
                    )
                }
            compose.waitUntil(10_000) { model.ui.value.approval != null }
            compose.onNodeWithText("Allow once").assertIsDisplayed()
            compose.runOnIdle { model.library.setPermission(Capability.KNOWLEDGE, Permission.DENY) }
            compose.onNodeWithText("Allow once").performClick()
            compose.waitUntil(10_000) { job.isCompleted }
            assertTrue(model.ui.value.messages.last().events.last().output.contains("revoked"))
            assertTrue(model.ui.value.messages.last().sources.isEmpty())
            val unknown =
                scope.launch {
                    model.execute(
                        ToolCall(
                            "read_file",
                            JSONObject().put("folder", "unknown").put("path", "notes.txt"),
                        ),
                        answer.id,
                    )
                }
            compose.waitUntil(10_000) { unknown.isCompleted }
            assertNull(model.ui.value.approval)
            assertTrue(
                model.ui.value.messages.last().events.last().output.contains("no longer connected")
            )
        } finally {
            scope.cancel()
            model.library.setPermission(Capability.KNOWLEDGE, Permission.ASK)
        }
    }

    @Test
    fun realWorkAnswerRetrievesOfflineEvidenceAndKeepsWeightsLoaded() {
        val model = model()
        val filename = installFixture("gguf")
        installFixture("zim")
        compose.runOnIdle {
            model.newChat()
            model.select(filename)
        }
        compose.waitUntil(60_000) { !model.ui.value.busy }
        assertNotNull(model.engine.loadedPath)
        compose.runOnIdle {
            model.library.setPermission(Capability.KNOWLEDGE, Permission.ALLOW)
            model.change {
                it.copy(
                    tab = 0,
                    work = true,
                    draft = "What is a bowline? Answer briefly using the sources.",
                )
            }
        }
        compose.onNodeWithContentDescription("Send message").performClick()
        compose.waitUntil(120_000) { !model.ui.value.busy }
        val answer = model.ui.value.messages.last()
        assertTrue("No sources: ${model.ui.value.error}", answer.sources.isNotEmpty())
        assertEquals("search_knowledge", answer.events.first().name)
        assertEquals("Completed", answer.events.first().state)
        assertTrue("No answer: ${model.ui.value.error}", answer.text.isNotBlank())
        assertNotNull(model.engine.loadedPath)
        compose.runOnIdle { model.library.setPermission(Capability.KNOWLEDGE, Permission.ASK) }
    }
}
