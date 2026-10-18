package com.jackwallner.bond.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CardGiftcard
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.capitalizedWords
import com.jackwallner.bond.model.nextOccurrence
import com.jackwallner.bond.ui.Formats
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.BarButton
import com.jackwallner.bond.ui.components.DatePickerSheet
import com.jackwallner.bond.ui.components.Detent
import com.jackwallner.bond.ui.components.FormTextField
import com.jackwallner.bond.ui.components.GroupRow
import com.jackwallner.bond.ui.components.GroupSection
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.MenuPickerRow
import com.jackwallner.bond.ui.components.RowDivider
import com.jackwallner.bond.ui.components.SheetScaffold
import com.jackwallner.bond.ui.components.ToggleRow
import com.jackwallner.bond.ui.components.TopBar
import com.jackwallner.bond.ui.components.ValueChip
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.FormatStyle
import java.util.UUID
import kotlinx.coroutines.launch

/** `MilestonesView.swift`. */
@Composable
fun MilestonesScreen() {
    val graph = LocalGraph.current
    val service = graph.milestones
    val sheets = LocalSheets.current
    val scope = rememberCoroutineScope()
    val colors = Bond.colors
    LaunchedEffect(graph.pairing.coupleId) { service.refresh() }

    fun openEditor(existing: MilestoneDto?) {
        sheets.present("milestoneEditor", Detent.LARGE) { dismiss -> MilestoneEditorSheet(existing, onClose = dismiss) }
    }

    Column(Modifier.fillMaxSize().testTag("screen.milestones")) {
        TopBar("Milestones", large = true, trailing = {
            IconButton(onClick = { openEditor(null) }, modifier = Modifier.semantics { contentDescription = "Add milestone" }.testTag("milestones.add")) {
                Icon(Icons.Rounded.Add, null, tint = colors.accent)
            }
        })
        if (service.milestones.isEmpty()) {
            Unavailable(
                Icons.Rounded.CalendarMonth, "No milestones yet",
                "Add your anniversary, birthdays, or any date worth remembering. Little Gestures pings you a week before, the day before, and on the day.",
                Modifier.testTag("milestones.empty"),
            )
            return@Column
        }
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val sorted = service.milestones.map { it to it.nextOccurrence(now, zone) }.sortedBy { it.second }
        LazyColumn(contentPadding = PaddingValues(vertical = Spacing.base)) {
            item {
                GroupSection {
                    sorted.forEachIndexed { index, (milestone, next) ->
                        if (index > 0) RowDivider(start = 56.dp)
                        key(milestone.id) {
                        val state = rememberSwipeToDismissBoxState()
                        SwipeToDismissBox(
                            state, enableDismissFromStartToEnd = false,
                            onDismiss = { value ->
                                if (value == SwipeToDismissBoxValue.EndToStart) scope.launch { runCatching { service.delete(milestone) } }
                                scope.launch { state.reset() }
                            },
                            backgroundContent = {
                                Box(Modifier.fillMaxSize().background(colors.danger).padding(horizontal = Spacing.l), contentAlignment = Alignment.CenterEnd) {
                                    Icon(Icons.Rounded.Delete, null, tint = Color.White)
                                }
                            },
                        ) {
                            Box(Modifier.background(colors.cardFill)) { MilestoneRow(milestone, next, now, zone) { openEditor(milestone) } }
                        }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MilestoneRow(milestone: MilestoneDto, next: LocalDate, now: Instant, zone: ZoneId, onClick: () -> Unit) {
    val colors = Bond.colors
    // Whole days from now to the occurrence's midnight, like the iOS calendar diff.
    val days = maxOf(0L, (next.atStartOfDay(zone).toInstant().epochSecond - now.epochSecond) / 86_400)
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = Spacing.base, vertical = 10.dp)
            .testTag("milestone.row.${milestone.label ?: milestone.kind}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (milestone.kind == "birthday") Icons.Rounded.CardGiftcard else Icons.Rounded.Favorite, null,
            tint = colors.accent, modifier = Modifier.width(28.dp),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            BText(milestone.label ?: milestone.kind.capitalizedWords(), BondType.headline)
            BText(Formats.date(next), BondType.caption, colors.inkSecondary)
        }
        BText("${days}d", BondType.callout.copy(fontFeatureSettings = "tnum"), colors.inkSecondary)
    }
}

private val KINDS = listOf("anniversary", "birthday", "custom")

/** `MilestoneEditorView.swift`. */
@Composable
fun MilestoneEditorSheet(existing: MilestoneDto?, onClose: () -> Unit) {
    val graph = LocalGraph.current
    val scope = rememberCoroutineScope()
    val colors = Bond.colors
    var label by remember { mutableStateOf(existing?.label ?: "") }
    var kind by remember { mutableStateOf(existing?.kind ?: "anniversary") }
    var date by remember { mutableStateOf(existing?.date ?: LocalDate.now()) }
    var recur by remember { mutableStateOf(existing?.recur ?: true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var pickingDate by remember { mutableStateOf(false) }

    fun save() {
        val coupleId = graph.pairing.coupleId ?: run { errorMessage = "Not paired."; return }
        val draft = MilestoneDto(
            id = existing?.id ?: UUID.randomUUID(), coupleId = coupleId, kind = kind,
            label = label.ifEmpty { null }, date = date, recur = recur, createdAt = existing?.createdAt,
        )
        scope.launch {
            try {
                graph.milestones.upsert(draft)
                onClose()
            } catch (e: Exception) {
                errorMessage = e.message ?: "Couldn't save. Check your connection and try again."
            }
        }
    }

    SheetScaffold(
        if (existing == null) "New milestone" else "Edit milestone",
        leading = { BarButton("Cancel", tag = "milestone.cancel", onClick = onClose) },
        trailing = { BarButton("Save", bold = true, tag = "milestone.save", onClick = ::save) },
    ) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().navigationBarsPadding()
                .padding(vertical = Spacing.base).testTag("milestone.editor"),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            GroupSection(footer = {
                BText(
                    "You'll get a heads-up 1 week before, the day before, and on the day at 9 AM.",
                    BondType.footnote, colors.inkSecondary,
                )
            }) {
                FormTextField(label, { label = it }, "Label (e.g. \"Our anniversary\")", tag = "milestone.label")
                RowDivider()
                MenuPickerRow("Kind", KINDS, kind, { it.capitalizedWords() }, tag = "milestone.kind") { kind = it }
                RowDivider()
                GroupRow {
                    BText("Date", BondType.body, modifier = Modifier.weight(1f))
                    ValueChip(Formats.date(date, FormatStyle.MEDIUM), "milestone.date") { pickingDate = true }
                }
                RowDivider()
                ToggleRow("Repeat yearly", recur, tag = "milestone.recur") { recur = it }
            }
            errorMessage?.let { GroupSection { GroupRow { BText(it, BondType.footnote, colors.danger) } } }
        }
    }
    if (pickingDate) {
        DatePickerSheet(date, onDismiss = { pickingDate = false }) { picked -> date = picked; pickingDate = false }
    }
}
