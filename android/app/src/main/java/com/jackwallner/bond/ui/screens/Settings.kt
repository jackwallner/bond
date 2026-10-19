package com.jackwallner.bond.ui.screens

import android.content.Intent
import android.net.Uri
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Email
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.NotificationsOff
import androidx.compose.material.icons.rounded.ReportProblem
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.BuildConfig
import com.jackwallner.bond.data.Accent
import com.jackwallner.bond.data.Appearance
import com.jackwallner.bond.data.Membership
import com.jackwallner.bond.data.StoreLinks
import com.jackwallner.bond.ui.Formats
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.BarButton
import com.jackwallner.bond.ui.components.GroupRow
import com.jackwallner.bond.ui.components.GroupSection
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.MenuPickerRow
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.RowDivider
import com.jackwallner.bond.ui.components.SheetScaffold
import com.jackwallner.bond.ui.components.TopBar
import com.jackwallner.bond.ui.openLink
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondColors
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import com.jackwallner.bond.ui.theme.semibold
import java.time.ZoneId
import java.time.format.FormatStyle
import kotlinx.coroutines.launch

private enum class Confirm { UNPAIR, DELETE }

/** `SettingsView.swift`. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen() {
    val graph = LocalGraph.current
    val sheets = LocalSheets.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val colors = Bond.colors
    val pairing = graph.pairing
    val store = graph.subscriptions
    var confirm by remember { mutableStateOf<Confirm?>(null) }
    var isDeleting by remember { mutableStateOf(false) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    var isRestoring by remember { mutableStateOf(false) }
    var showRestoreResult by remember { mutableStateOf(false) }
    var showReviewerCode by remember { mutableStateOf(false) }
    var notificationsOn by remember { mutableStateOf(graph.notifications.isAuthorized) }

    // Re-read the permission whenever the app comes back from system Settings.
    LaunchedEffect(graph.resumeTick) { notificationsOn = graph.notifications.isAuthorized }
    LaunchedEffect(pairing.justPaired) { if (pairing.justPaired) sheets.dismiss("pairing") }

    fun openPairing() = sheets.present("pairing") { dismiss -> PairingSheet(onClose = dismiss) }

    Column(Modifier.fillMaxSize().testTag("screen.settings")) {
        TopBar("Settings")
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = Spacing.base),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            GroupSection(header = "Account") {
                GroupRow(onClick = if (isDeleting) null else ({ confirm = Confirm.DELETE }), tag = "settings.delete") {
                    if (isDeleting) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = colors.danger, strokeWidth = 2.dp)
                        Spacer(Modifier.width(Spacing.s))
                        BText("Deleting…", BondType.body, colors.danger)
                    } else {
                        BText("Delete account", BondType.body, colors.danger)
                    }
                }
                deleteError?.let { RowDivider(); GroupRow { BText(it, BondType.footnote, colors.danger) } }
            }

            GroupSection(header = "Pairing") {
                if (pairing.solo || pairing.coupleId == null) {
                    LinkRow(Icons.Rounded.Favorite, "Connect a partner", tag = "settings.pair") { openPairing() }
                    GroupRow {
                        BText(
                            "Little Gestures is just for you right now. Pair to share reminders. You keep everything you've already added.",
                            BondType.caption, colors.inkSecondary,
                        )
                    }
                } else {
                    val name = pairing.partnerProfile?.displayName
                    GroupRow {
                        Box(Modifier.size(36.dp).clip(CircleShape).background(colors.accent), contentAlignment = Alignment.Center) {
                            BText(initials(name), BondType.subheadline.bold, Color.White)
                        }
                        Spacer(Modifier.width(Spacing.m))
                        Column {
                            BText(name?.takeIf { it.isNotEmpty() } ?: "Your partner", BondType.headline)
                            BText("Paired", BondType.caption, colors.inkSecondary)
                        }
                    }
                    RowDivider()
                    GroupRow(onClick = { confirm = Confirm.UNPAIR }, tag = "settings.unpair") { BText("Unpair", BondType.body, colors.danger) }
                    RowDivider()
                    LinkRow(Icons.Rounded.ReportProblem, "Report a concern") { openLink(context, StoreLinks.REPORT_CONCERN_URI) }
                    GroupRow {
                        BText(
                            "Unpairing immediately stops your partner from sending you anything. Reporting lets us know about abusive content.",
                            BondType.caption, colors.inkSecondary,
                        )
                    }
                }
            }

            GroupSection(header = Membership.PLUS) {
                GroupRow(tag = "settings.status") {
                    BText("Status", BondType.body, modifier = Modifier.weight(1f))
                    val since = store.premiumSince
                    BText(
                        when {
                            !store.isPremium -> "Free"
                            since != null -> "${Membership.PLUS} since ${Formats.date(since.atZone(ZoneId.systemDefault()).toLocalDate(), FormatStyle.LONG)}"
                            else -> Membership.PLUS
                        },
                        BondType.callout, colors.inkSecondary, align = TextAlign.End,
                    )
                }
                RowDivider()
                if (store.isPremium) {
                    LinkRow(null, "Manage subscription", tag = "settings.manage") {
                        openLink(context, StoreLinks.manageSubscriptionURL(store.activeProductId))
                    }
                } else {
                    GroupRow(onClick = { sheets.presentPaywall() }, tag = "settings.tryPlus") {
                        Icon(Icons.Rounded.AutoAwesome, null, tint = colors.accent, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(Spacing.m))
                        BText("Try ${Membership.PLUS} free", BondType.body.semibold, colors.accent)
                    }
                }
                RowDivider()
                GroupRow(
                    onClick = if (isRestoring) null else ({
                        scope.launch {
                            isRestoring = true
                            store.restore()
                            isRestoring = false
                            if (!store.isPremium) showRestoreResult = true
                        }
                    }),
                    tag = "settings.restore",
                ) {
                    if (isRestoring) CircularProgressIndicator(Modifier.size(18.dp), color = colors.accent, strokeWidth = 2.dp)
                    else BText("Restore purchases", BondType.body, colors.accent)
                }
            }

            GroupSection(header = "Theme") {
                Accent.entries.forEachIndexed { index, accent ->
                    if (index > 0) RowDivider()
                    GroupRow(onClick = { graph.theme.updateAccent(accent) }, tag = "settings.accent.${accent.raw}") {
                        val swatch = if (colors.isDark) BondColors.dark(accent).accent else BondColors.light(accent).accent
                        Box(Modifier.size(14.dp).clip(CircleShape).background(swatch))
                        Spacer(Modifier.width(Spacing.m))
                        BText(accent.title, BondType.body, modifier = Modifier.weight(1f))
                        if (graph.theme.accent == accent) Icon(Icons.Rounded.CheckCircle, null, tint = colors.accent, modifier = Modifier.size(20.dp))
                    }
                }
                RowDivider()
                MenuPickerRow("Appearance", Appearance.entries, graph.theme.appearance, { it.title }, tag = "settings.appearance") {
                    graph.theme.updateAppearance(it)
                }
            }

            GroupSection(header = "Notifications") {
                GroupRow(onClick = {
                    val intent = Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(AndroidSettings.EXTRA_APP_PACKAGE, context.packageName)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    runCatching { context.startActivity(intent) }
                }, tag = "settings.notifications") {
                    val asked = graph.notifications.permissionAsked
                    val denied = !notificationsOn && asked
                    Icon(
                        if (denied) Icons.Rounded.NotificationsOff else Icons.Rounded.Notifications, null,
                        tint = if (denied) colors.warning else colors.inkSecondary, modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(Spacing.m))
                    BText(
                        when {
                            notificationsOn -> "On"
                            asked -> "Off, open Settings"
                            else -> "Not yet enabled"
                        },
                        BondType.body, modifier = Modifier.weight(1f),
                    )
                    Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, tint = colors.inkSecondary, modifier = Modifier.size(18.dp))
                }
            }

            GroupSection(header = "Help") {
                LinkRow(Icons.Rounded.Star, "Rate on Google Play", tag = "settings.rate") {
                    graph.review.markOpenedWriteReview()
                    val market = Intent(Intent.ACTION_VIEW, Uri.parse(StoreLinks.PLAY_MARKET_URI)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    runCatching { context.startActivity(market) }.onFailure { openLink(context, StoreLinks.PLAY_LISTING_URL) }
                }
                RowDivider()
                LinkRow(Icons.Rounded.Email, "Send Feedback", tag = "settings.feedback") {
                    sheets.present("feedback") { dismiss -> FeedbackSheet(onClose = dismiss) }
                }
            }

            Column {
                GroupSection {
                    LinkRow(null, "Privacy policy") { openLink(context, StoreLinks.PRIVACY_URL) }
                    RowDivider()
                    LinkRow(null, "Terms of service") { openLink(context, StoreLinks.TERMS_URL) }
                    RowDivider()
                    LinkRow(null, "Support") { openLink(context, StoreLinks.SUPPORT_URI) }
                }
                BText(
                    "Version ${BuildConfig.VERSION_NAME} (build ${BuildConfig.VERSION_CODE})",
                    BondType.footnote, colors.inkTertiary, align = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = Spacing.m).combinedClickable(onClick = {}, onLongClick = { showReviewerCode = true })
                        .padding(vertical = Spacing.s).testTag("settings.version"),
                )
            }
        }
    }

    when (confirm) {
        Confirm.UNPAIR -> ConfirmDialog(
            "Unpair?", "You'll keep your reminders. Your partner will keep theirs.", "Unpair",
            onConfirm = { confirm = null; scope.launch { pairing.leaveCouple() } },
            onDismiss = { confirm = null },
        )
        Confirm.DELETE -> ConfirmDialog(
            "Delete account?",
            "This permanently deletes your account and everything you created. If you're paired, your partner keeps their own reminders, " +
                "your shared milestones, and their account, they'll just be unpaired. This can't be undone. " +
                "(Any Google Play subscription is managed separately in the Play Store.)",
            "Delete everything",
            onConfirm = {
                confirm = null
                scope.launch {
                    isDeleting = true
                    deleteError = null
                    try {
                        graph.deleteAccount()
                    } catch (e: Exception) {
                        deleteError = "Couldn't delete your account. Check your connection and try again."
                    } finally {
                        isDeleting = false
                    }
                }
            },
            onDismiss = { confirm = null },
        )
        null -> Unit
    }
    if (showRestoreResult) {
        AlertDialog(
            onDismissRequest = { showRestoreResult = false },
            title = { BText("Restore Purchases", BondType.headline) },
            text = { BText(store.lastError ?: "No active ${Membership.PLUS} purchase found for this Google account.", BondType.subheadline, colors.inkSecondary) },
            confirmButton = { TextButton(onClick = { showRestoreResult = false }) { BText("OK", BondType.body.semibold, colors.accent) } },
            containerColor = colors.surfaceElevated,
        )
    }
    if (showReviewerCode) ReviewerCodeDialog { showReviewerCode = false }
}

private fun initials(name: String?): String {
    if (name.isNullOrEmpty()) return "?"
    return name.split(" ").filter { it.isNotEmpty() }.take(2).mapNotNull { it.firstOrNull() }.joinToString("").uppercase()
}

@Composable
private fun LinkRow(icon: ImageVector?, title: String, tag: String? = null, onClick: () -> Unit) {
    val colors = Bond.colors
    GroupRow(onClick = onClick, tag = tag) {
        icon?.let {
            Icon(it, null, tint = colors.accent, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(Spacing.m))
        }
        BText(title, BondType.body, colors.accent)
    }
}

/** iOS `confirmationDialog` with one destructive action. */
@Composable
fun ConfirmDialog(title: String, message: String, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val colors = Bond.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { BText(title, BondType.headline) },
        text = { BText(message, BondType.subheadline, colors.inkSecondary) },
        confirmButton = {
            TextButton(onClick = onConfirm, modifier = Modifier.testTag("confirm.action")) { BText(action, BondType.body.semibold, colors.danger) }
        },
        dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.testTag("confirm.cancel")) { BText("Cancel", BondType.body, colors.accent) } },
        containerColor = colors.surfaceElevated,
    )
}

/** `ReviewPromptSheet.swift`: feedback is its own path, never a branch of a rating question. */
@Composable
fun FeedbackSheet(onClose: () -> Unit) {
    val graph = LocalGraph.current
    val context = LocalContext.current
    val colors = Bond.colors
    var text by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val trimmed = text.trim()
    SheetScaffold("Help us improve", leading = {
        BarButton("Not now", tag = "feedback.notNow") {
            graph.review.markShown()
            onClose()
        }
    }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().navigationBarsPadding()
                .padding(horizontal = Spacing.xl).padding(bottom = Spacing.xl).testTag("feedback"),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            BText("What would make Little Gestures work better for you?", BondType.subheadline, colors.inkSecondary)
            BasicTextField(
                value = text,
                onValueChange = { text = it },
                textStyle = BondType.body.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.accent),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp).clip(RoundedCornerShape(12.dp)).background(colors.surface)
                    .padding(10.dp).focusRequester(focus).testTag("feedback.text"),
            )
            BText("Opens your mail app with a draft to the developer. No analytics, just your words.", BondType.caption, colors.inkSecondary)
            PrimaryButton("Send feedback", enabled = trimmed.isNotEmpty(), tag = "feedback.send") {
                graph.review.markFeedbackSubmitted()
                openLink(context, StoreLinks.feedbackMailUri(trimmed))
                onClose()
            }
        }
    }
}

/** Private unlock for Google Play's review team; only the code's SHA-256 ships in the app. */
@Composable
private fun ReviewerCodeDialog(onDismiss: () -> Unit) {
    val store = LocalGraph.current.subscriptions
    val colors = Bond.colors
    var code by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surfaceElevated,
        title = { BText("Reviewer Access", BondType.headline) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                BText("Enter the reviewer code provided with this app's review notes.", BondType.subheadline, colors.inkSecondary)
                OutlinedTextField(
                    code, { code = it; failed = false }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                    textStyle = BondType.body.copy(color = colors.ink),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = colors.accent, unfocusedBorderColor = colors.hairline, cursorColor = colors.accent),
                    modifier = Modifier.testTag("reviewer.code"),
                )
                if (failed) BText("That code isn't valid.", BondType.caption, colors.danger)
            }
        },
        confirmButton = {
            TextButton(onClick = { if (store.activateReviewAccess(code)) onDismiss() else failed = true }, modifier = Modifier.testTag("reviewer.unlock")) {
                BText("Unlock", BondType.headline, colors.accent)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { BText("Cancel", BondType.body, colors.inkSecondary) } },
    )
}
