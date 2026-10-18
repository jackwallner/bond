package com.jackwallner.bond.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FamilyRestroom
import androidx.compose.material.icons.rounded.FlightTakeoff
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.VolunteerActivism
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.model.ReminderTemplateGroup
import com.jackwallner.bond.model.ReminderTemplateStore
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.BackButton
import com.jackwallner.bond.ui.components.BarButton
import com.jackwallner.bond.ui.components.Chevron
import com.jackwallner.bond.ui.components.GroupRow
import com.jackwallner.bond.ui.components.GroupSection
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.RowDivider
import com.jackwallner.bond.ui.components.SheetScaffold
import com.jackwallner.bond.ui.components.icon
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import com.jackwallner.bond.ui.theme.semibold
import kotlinx.coroutines.launch

/** The SF Symbol each pack carries on iOS (`ReminderTemplate.swift`), as a Material icon. */
val ReminderTemplateGroup.icon: ImageVector
    get() = when (id) {
        "daily_affirmations" -> Icons.Rounded.FormatQuote
        "date_night" -> Icons.Rounded.AutoAwesome
        "long_distance" -> Icons.Rounded.FlightTakeoff
        "new_parents" -> Icons.Rounded.FamilyRestroom
        "appreciation" -> Icons.Rounded.Favorite
        else -> Icons.Rounded.VolunteerActivism
    }

/** `ReminderTemplatesView.swift`: a teaser for free users, the packs for Little Gestures+. */
@Composable
fun ReminderTemplatesSheet(onClose: () -> Unit) {
    val graph = LocalGraph.current
    val sheets = LocalSheets.current
    var detail by remember { mutableStateOf<ReminderTemplateGroup?>(null) }
    val open = detail
    if (open != null) {
        BackHandler { detail = null }
        TemplateGroupDetail(open, onBack = { detail = null }, onFinished = onClose)
        return
    }
    SheetScaffold("Templates", leading = { BarButton("Done", tag = "templates.done", onClick = onClose) }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(vertical = Spacing.base)
                .testTag(if (graph.subscriptions.isPremium) "templates.list" else "templates.teaser"),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            if (!graph.subscriptions.isPremium) {
                GroupSection {
                    ReminderTemplateStore.groups.forEachIndexed { index, group ->
                        if (index > 0) RowDivider(start = 60.dp)
                        GroupRow { GroupLabel(group); BText("${group.reminders.size}", BondType.caption.semibold, Bond.colors.inkTertiary) }
                    }
                }
                UnlockCard(
                    Icons.Rounded.Layers, PremiumFeature.TEMPLATES.gateHeadline, PremiumFeature.TEMPLATES.gateSubhead,
                    onUnlock = { sheets.presentPaywall() }, modifier = Modifier.padding(horizontal = Spacing.base),
                )
            } else {
                ReminderTemplateStore.groups.forEach { group ->
                    GroupSection(header = "${group.reminders.size} reminders") {
                        GroupRow(onClick = { detail = group }, tag = "templates.group.${group.id}") {
                            GroupLabel(group)
                            Chevron()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.GroupLabel(group: ReminderTemplateGroup) {
    Icon(group.icon, null, tint = Bond.colors.accent, modifier = Modifier.width(32.dp).size(26.dp))
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f).padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        BText(group.title, BondType.headline)
        BText(group.subtitle, BondType.caption, Bond.colors.inkSecondary)
    }
}

/** `TemplateGroupDetailView`: what the pack includes and one button to add it all. */
@Composable
private fun TemplateGroupDetail(group: ReminderTemplateGroup, onBack: () -> Unit, onFinished: () -> Unit) {
    val graph = LocalGraph.current
    val scope = rememberCoroutineScope()
    val colors = Bond.colors
    var isCreating by remember { mutableStateOf(false) }
    var created by remember { mutableIntStateOf(0) }
    var showConfirmation by remember { mutableStateOf(false) }
    var importError by remember { mutableStateOf<String?>(null) }

    fun createAll() {
        val me = graph.auth.currentUserId ?: return
        val coupleId = graph.pairing.coupleId ?: return
        isCreating = true
        created = 0
        importError = null
        val target = if (graph.pairing.solo) me else graph.pairing.partnerProfile?.id ?: me
        val drafts = ReminderTemplateStore.drafts(group, coupleId, me, target)
        scope.launch {
            try {
                graph.reminders.bulkInsert(drafts)
                graph.rescheduleNotifications()
                created = drafts.size
                showConfirmation = true
            } catch (e: Exception) {
                created = 0
                importError = "Couldn't add templates. Check your connection and try again."
            } finally {
                isCreating = false
            }
        }
    }

    SheetScaffold(group.title, leading = { BackButton(onBack) }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(vertical = Spacing.base)
                .testTag("templates.detail"),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            GroupSection {
                Column(Modifier.padding(Spacing.base), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    BText(group.title, BondType.title2.bold)
                    BText(group.subtitle, BondType.subheadline, colors.inkSecondary)
                }
            }
            GroupSection(header = "Includes") {
                group.reminders.forEachIndexed { index, template ->
                    if (index > 0) RowDivider(start = 52.dp)
                    GroupRow {
                        Icon(template.loveLanguage.icon, null, tint = colors.tint(template.loveLanguage), modifier = Modifier.width(24.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            BText(template.title, BondType.subheadline)
                            template.body?.let { BText(it, BondType.caption, colors.inkSecondary) }
                        }
                        Spacer(Modifier.width(Spacing.s))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(8.dp).clip(CircleShape).background(colors.tint(template.loveLanguage)))
                            template.triggerRecurrence?.let {
                                Spacer(Modifier.width(4.dp))
                                BText(it.title, BondType.caption2, colors.inkSecondary)
                            }
                        }
                    }
                }
            }
            Column(Modifier.padding(horizontal = Spacing.base), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                PrimaryButton("Add ${group.reminders.size} reminders", isLoading = isCreating, tag = "templates.add", onClick = ::createAll)
                importError?.let { BText(it, BondType.footnote, colors.danger) }
            }
        }
    }

    if (showConfirmation) {
        AlertDialog(
            onDismissRequest = { showConfirmation = false; onFinished() },
            title = { BText("Templates added!", BondType.headline) },
            text = {
                BText(
                    "$created reminders added, spread across the coming days so they arrive one at a time, not all at once. Customize any of them anytime.",
                    BondType.subheadline, colors.inkSecondary,
                )
            },
            confirmButton = {
                TextButton(onClick = { showConfirmation = false; onFinished() }, modifier = Modifier.testTag("templates.confirm")) {
                    BText("Done", BondType.body.semibold, colors.accent)
                }
            },
            containerColor = colors.surfaceElevated,
        )
    }
}
