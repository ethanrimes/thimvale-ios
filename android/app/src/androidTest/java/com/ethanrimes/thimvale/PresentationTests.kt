package com.ethanrimes.thimvale

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class PresentationTests {
    @get:Rule val compose = createComposeRule()

    @Test
    fun sourcesStartCollapsedAndExpand() {
        compose.setContent {
            MaterialTheme {
                Expandable("Sources 1") { androidx.compose.material3.Text("Bowline source") }
            }
        }
        compose.onNodeWithText("Bowline source").assertDoesNotExist()
        compose.onNodeWithText("Sources 1").performClick()
        compose.onNodeWithText("Bowline source").assertIsDisplayed()
        compose.onNodeWithText("Sources 1").performClick()
        compose.onNodeWithText("Bowline source").assertDoesNotExist()
    }

    @Test
    fun toolsAreCompactUntilExpanded() {
        compose.setContent {
            MaterialTheme {
                ToolRow(ToolEvent("read_file", "notes/trip.md", "The source text", "Completed"))
            }
        }
        compose.onNodeWithText("The source text").assertDoesNotExist()
        compose.onNodeWithText("✓ read_file  ·  Completed").performClick()
        compose.onNodeWithText("The source text").assertIsDisplayed()
        compose.onNodeWithText("notes/trip.md").assertIsDisplayed()
    }

    @Test
    fun inlineCitationHasItsSourceAndNoSeparateCard() {
        compose.setContent {
            MaterialTheme {
                AnswerText(
                    "A fixed loop [1].",
                    listOf(Evidence("1", "Bowline", "knots.zim", "A fixed loop")),
                ) {}
            }
        }
        compose.onNodeWithText("A fixed loop [1].").assertIsDisplayed()
        compose.onNodeWithText("Bowline").assertDoesNotExist()
    }
}
