package com.jackwallner.bond.ui.screens

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.PersonSearch
import androidx.compose.material.icons.rounded.QuestionAnswer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.BackButton
import com.jackwallner.bond.ui.components.InlineError
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.SealedCard
import com.jackwallner.bond.ui.components.TopBar
import com.jackwallner.bond.ui.components.icon
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Radius
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import java.time.LocalDate
import kotlinx.coroutines.launch

/** An empty state like `ContentUnavailableView`. */
@Composable
fun Unavailable(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, description: String, modifier: Modifier = Modifier) {
    val colors = Bond.colors
    Column(
        modifier.fillMaxSize().padding(horizontal = Spacing.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, tint = colors.inkSecondary, modifier = Modifier.size(48.dp))
        Spacer(Modifier.size(Spacing.base))
        BText(title, BondType.title2.bold, align = TextAlign.Center)
        Spacer(Modifier.size(Spacing.s))
        BText(description, BondType.subheadline, colors.inkSecondary, align = TextAlign.Center)
    }
}

/** `DailyCheckInView.swift`: one shared question, answers sealed until both reply. */
@Composable
fun DailyCheckInScreen(onBack: (() -> Unit)? = null) {
    val graph = LocalGraph.current
    val checkIn = graph.checkIn
    val pairing = graph.pairing
    val sheets = LocalSheets.current
    LaunchedEffect(pairing.solo, pairing.coupleId) {
        if (!pairing.solo && !graph.seed.enabled) checkIn.loadTodaysQuestion()
    }
    Column(Modifier.fillMaxSize().testTag("screen.checkIn")) {
        TopBar("Check-In", large = onBack == null, leading = onBack?.let { { BackButton(it) } })
        Box(Modifier.weight(1f)) {
            when {
                pairing.solo -> Unavailable(
                    Icons.Rounded.PersonSearch, "For Couples Only",
                    "Daily Check-In is designed for couples to share and compare answers. Pair up with someone to get started.",
                    Modifier.testTag("checkIn.solo"),
                )
                checkIn.isLoading && checkIn.todaysQuestion == null -> Column(
                    Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    CircularProgressIndicator(color = Bond.colors.accent)
                    Spacer(Modifier.size(Spacing.s))
                    BText("Loading today's question...", BondType.subheadline, Bond.colors.inkSecondary)
                }
                !graph.subscriptions.isPremium -> Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.base).testTag("checkIn.teaser"),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xl),
                ) {
                    QuestionCard()
                    UnlockCard(
                        Icons.Rounded.QuestionAnswer, "Answer together",
                        "Little Gestures+ unlocks answering today's question and seeing each other's response once you've both replied.",
                        onUnlock = { sheets.presentPaywall() },
                    )
                }
                else -> CheckInContent()
            }
        }
    }
}

@Composable
private fun QuestionCard() {
    val colors = Bond.colors
    val question = LocalGraph.current.checkIn.todaysQuestion
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.card)).background(colors.cardFill).padding(Spacing.base)
            .testTag("checkIn.question"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.m),
    ) {
        if (question != null) {
            val lang = question.loveLanguage
            lang?.let { Icon(it.icon, null, tint = colors.tint(it), modifier = Modifier.size(30.dp)) }
            BText(question.question, BondType.title3, align = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.base))
            lang?.let {
                Box(Modifier.clip(CircleShape).background(colors.tint(it).copy(alpha = 0.12f)).padding(horizontal = Spacing.m, vertical = Spacing.xs)) {
                    BText(it.title, BondType.caption, colors.tint(it))
                }
            }
        }
    }
}

@Composable
private fun AnswerBlock(title: String, tint: Color, text: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.AccountCircle, null, tint = tint)
            Spacer(Modifier.width(Spacing.s))
            BText(title, BondType.subheadline.bold)
        }
        BText(
            text, BondType.body,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.inline)).background(tint.copy(alpha = 0.08f)).padding(Spacing.base),
        )
    }
}

@Composable
private fun CheckInContent() {
    val graph = LocalGraph.current
    val checkIn = graph.checkIn
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val colors = Bond.colors
    var response by remember { mutableStateOf("") }
    var revealed by remember { mutableStateOf(false) }
    val partnerText = checkIn.partnerResponse?.response
    val dayKey = LocalDate.now().toString()

    // First visit of the day stays sealed until the tap; later visits skip the ceremony.
    LaunchedEffect(partnerText, checkIn.myResponse) {
        if (partnerText == null || checkIn.myResponse == null) return@LaunchedEffect
        if (graph.flags.revealShown(dayKey)) {
            revealed = true
        } else {
            graph.flags.markRevealShown(dayKey)
            revealed = false
        }
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(Spacing.base),
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        QuestionCard()
        val mine = checkIn.myResponse
        if (mine != null) {
            AnswerBlock("Your answer", Color(0xFF0A84FF), mine.response, Modifier.testTag("checkIn.mine"))
            if (partnerText != null) {
                val rotation by animateFloatAsState(
                    if (revealed) 180f else 0f, spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessLow), label = "flip",
                )
                Box(
                    Modifier.fillMaxWidth().clickable(enabled = !revealed) {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        revealed = true
                    }.testTag("checkIn.partner"),
                ) {
                    val showBack = rotation > 90f
                    Box(Modifier.graphicsLayer { rotationY = rotation; cameraDistance = 12f * density }.alpha(if (showBack) 0f else 1f)) {
                        SealedCard("Their answer", "Tap to reveal")
                    }
                    if (showBack) {
                        val who = graph.pairing.partnerProfile?.displayName?.takeIf { it.isNotEmpty() } ?: "They"
                        Box(
                            Modifier.graphicsLayer { rotationY = rotation - 180f; cameraDistance = 12f * density }
                                .semantics { liveRegion = LiveRegionMode.Polite },
                        ) {
                            AnswerBlock("Their answer", colors.accent, partnerText)
                        }
                        BText("$who answered.", BondType.caption2, Color.Transparent, modifier = Modifier.size(1.dp))
                    }
                }
            } else {
                SealedCard("Their answer", "Sealed until they answer", Modifier.testTag("checkIn.sealed"))
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
                BasicTextField(
                    value = response,
                    onValueChange = { response = it },
                    minLines = 3,
                    maxLines = 6,
                    textStyle = BondType.body.copy(color = colors.ink),
                    cursorBrush = SolidColor(colors.accent),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.inline)).background(colors.cardFill)
                        .padding(Spacing.base).heightIn(min = 72.dp).testTag("checkIn.answer"),
                    decorationBox = { inner ->
                        Box {
                            if (response.isEmpty()) BText("Type your answer...", BondType.body, colors.inkTertiary)
                            inner()
                        }
                    },
                )
                PrimaryButton(
                    "Submit answer", enabled = response.isNotBlank() && !checkIn.isLoading, isLoading = checkIn.isLoading,
                    tag = "checkIn.submit",
                ) {
                    scope.launch {
                        checkIn.submitResponse(response)
                        if (checkIn.myResponse != null) response = ""
                    }
                }
                checkIn.lastError?.let { InlineError(it) }
            }
        }
    }
}
