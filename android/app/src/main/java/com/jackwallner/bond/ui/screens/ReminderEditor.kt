package com.jackwallner.bond.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.model.Geofence
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.RecurrencePreset
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderTarget
import com.jackwallner.bond.model.ReminderTrigger
import com.jackwallner.bond.model.StarterChip
import com.jackwallner.bond.model.StarterChips
import com.jackwallner.bond.model.TriggerKind
import com.jackwallner.bond.model.toMinute
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.BarButton
import com.jackwallner.bond.ui.components.DateTimeRow
import com.jackwallner.bond.ui.components.FormTextField
import com.jackwallner.bond.ui.components.GroupRow
import com.jackwallner.bond.ui.components.GroupSection
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.MenuPickerRow
import com.jackwallner.bond.ui.components.RowDivider
import com.jackwallner.bond.ui.components.Segmented
import com.jackwallner.bond.ui.components.SheetScaffold
import com.jackwallner.bond.ui.components.ToggleRow
import com.jackwallner.bond.ui.components.icon
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.semibold
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.random.Random
import kotlinx.coroutines.launch

private fun todayAt(hour: Int): Instant = LocalDate.now().atTime(hour, 0).atZone(ZoneId.systemDefault()).toInstant()

private fun minutesOfDay(instant: Instant): Int = instant.atZone(ZoneId.systemDefault()).let { it.hour * 60 + it.minute }

/** `ReminderEditorView.swift`: new or edit, with the same validation and save rules. */
@Composable
fun ReminderEditorSheet(existing: ReminderDto?, prefill: StarterChip?, onClose: () -> Unit) {
    val graph = LocalGraph.current
    val sheets = LocalSheets.current
    val scope = rememberCoroutineScope()
    val store = graph.subscriptions
    val pairing = graph.pairing
    val me = graph.auth.currentUserId
    val colors = Bond.colors
    val now = remember { Instant.now().toMinute() }

    var title by remember { mutableStateOf(existing?.title ?: prefill?.title ?: "") }
    var note by remember { mutableStateOf(existing?.body ?: "") }
    var language by remember { mutableStateOf(existing?.loveLanguage ?: prefill?.loveLanguage ?: LoveLanguage.WORDS) }
    var target by remember { mutableStateOf(if (existing == null || existing.targetId == me) ReminderTarget.ME else ReminderTarget.PARTNER) }
    var surpriseHidden by remember { mutableStateOf(existing?.surpriseHiddenFromPartner ?: false) }
    var kind by remember { mutableStateOf(TriggerKind.ONE_TIME) }
    var fireAt by remember { mutableStateOf(now.plusSeconds(3600)) }
    var recurrence by remember { mutableStateOf(RecurrencePreset.WEEKLY) }
    var windowStart by remember { mutableStateOf(now.plusSeconds(3600)) }
    var windowEnd by remember { mutableStateOf(now.plusSeconds(86_400)) }
    var repeatsDaily by remember { mutableStateOf(false) }
    var dailyStart by remember { mutableStateOf(todayAt(18)) }
    var dailyEnd by remember { mutableStateOf(todayAt(21)) }
    var geofence by remember { mutableStateOf<Geofence?>(null) }
    var geofenceLabel by remember { mutableStateOf("Home") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var lastFreeKind by remember { mutableStateOf(TriggerKind.ONE_TIME) }
    var hydrated by remember { mutableStateOf(false) }

    if (!hydrated) {
        hydrated = true
        when (val t = existing?.trigger) {
            is ReminderTrigger.OneTime -> { kind = TriggerKind.ONE_TIME; fireAt = t.fireAt }
            is ReminderTrigger.Recurring -> {
                kind = TriggerKind.RECURRING
                fireAt = t.nextFire
                RecurrencePreset.fromRrule(t.rrule)?.let { recurrence = it }
            }
            is ReminderTrigger.Location -> { kind = TriggerKind.LOCATION; geofence = t.geofence; geofenceLabel = t.geofence.label }
            is ReminderTrigger.RandomWindow -> { kind = TriggerKind.RANDOM_WINDOW; repeatsDaily = false; windowStart = t.start; windowEnd = t.end }
            is ReminderTrigger.RandomRecurring -> { kind = TriggerKind.RANDOM_WINDOW; repeatsDaily = true; dailyStart = t.start; dailyEnd = t.end }
            null -> Unit
        }
        if (!kind.isPremium) lastFreeKind = kind
    }

    // Place reminders need background location, which Android doesn't request; an
    // iPhone-made one stays editable here, but a new one can't pick the kind.
    val kinds = TriggerKind.entries.filter { it.availableOnAndroid || it == kind }
    val trimmedTitle = title.trim()
    val isValid = trimmedTitle.isNotEmpty() && when (kind) {
        TriggerKind.LOCATION -> geofence != null
        TriggerKind.RANDOM_WINDOW -> if (repeatsDaily) minutesOfDay(dailyEnd) > minutesOfDay(dailyStart) else windowEnd.isAfter(windowStart)
        TriggerKind.ONE_TIME, TriggerKind.RECURRING -> true
    }

    fun selectKind(newKind: TriggerKind) {
        if (newKind.isPremium && !store.isPremium) {
            kind = lastFreeKind
            sheets.presentPaywall()
        } else {
            kind = newKind
            if (!newKind.isPremium) lastFreeKind = newKind
        }
    }

    fun save() {
        val self = me
        val coupleId = pairing.coupleId
        if (self == null || coupleId == null) {
            errorMessage = "Not set up yet. Please finish setup first."
            return
        }
        val targetId = if (target == ReminderTarget.ME) self else pairing.partnerProfile?.id ?: self
        if (kind.isPremium && !store.isPremium) {
            sheets.presentPaywall()
            return
        }
        var draft = (existing ?: ReminderDto(
            id = UUID.randomUUID(), coupleId = coupleId, authorId = self, targetId = targetId, title = title,
            body = note.ifEmpty { null }, loveLanguage = language, triggerType = "one_time", fireAt = fireAt,
            surpriseHiddenFromPartner = surpriseHidden,
        )).copy(
            title = title,
            body = note.ifEmpty { null },
            loveLanguage = language,
            targetId = targetId,
            surpriseHiddenFromPartner = target == ReminderTarget.PARTNER && surpriseHidden,
        )
        draft = when (kind) {
            TriggerKind.ONE_TIME -> draft.copy(triggerType = "one_time", fireAt = fireAt, rrule = null, geofence = null, windowStart = null, windowEnd = null)
            TriggerKind.RECURRING -> draft.copy(triggerType = "recurring", fireAt = fireAt, rrule = recurrence.rrule, geofence = null, windowStart = null, windowEnd = null)
            TriggerKind.LOCATION -> {
                val g = geofence ?: run { errorMessage = "Pick a location first."; return }
                draft.copy(triggerType = "location", geofence = g.copy(label = geofenceLabel), fireAt = null, rrule = null, windowStart = null, windowEnd = null)
            }
            TriggerKind.RANDOM_WINDOW -> if (repeatsDaily) {
                if (minutesOfDay(dailyEnd) <= minutesOfDay(dailyStart)) {
                    errorMessage = "The end time must be after the start time."
                    return
                }
                draft.copy(
                    triggerType = "random_window", rrule = RecurrencePreset.DAILY.rrule, windowStart = dailyStart, windowEnd = dailyEnd,
                    fireAt = ReminderTrigger.RandomRecurring(dailyStart, dailyEnd).upcomingFireDate(), geofence = null,
                )
            } else {
                if (!windowEnd.isAfter(windowStart)) {
                    errorMessage = "Window end must be after start."
                    return
                }
                val span = windowEnd.epochSecond - windowStart.epochSecond
                val pick = windowStart.plusSeconds(Random.nextLong(0, span + 1))
                draft.copy(triggerType = "random_window", fireAt = pick, windowStart = windowStart, windowEnd = windowEnd, rrule = null, geofence = null)
            }
        }
        isSaving = true
        scope.launch {
            try {
                graph.reminders.upsert(draft)
                graph.rescheduleNotifications()
                onClose()
            } catch (e: Exception) {
                errorMessage = e.message ?: "Couldn't save. Check your connection and try again."
            } finally {
                isSaving = false
            }
        }
    }

    SheetScaffold(
        if (existing == null) "New reminder" else "Edit reminder",
        leading = { BarButton("Cancel", tag = "editor.cancel", onClick = onClose) },
        trailing = {
            if (isSaving) {
                Box(Modifier.padding(horizontal = Spacing.base)) { CircularProgressIndicator(Modifier.size(20.dp), color = colors.accent, strokeWidth = 2.dp) }
            } else {
                BarButton("Save", enabled = isValid, bold = true, tag = "editor.save", onClick = ::save)
            }
        },
    ) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().navigationBarsPadding()
                .padding(vertical = Spacing.base).testTag("editor"),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            GroupSection(footer = if (trimmedTitle.isEmpty()) ({ BText("Add a title to save.", BondType.footnote, colors.inkSecondary) }) else null) {
                FormTextField(title, { title = it }, "Title", tag = "editor.title")
                RowDivider()
                FormTextField(note, { note = it }, "Note (optional)", tag = "editor.note", singleLine = false, minLines = 2)
            }

            GroupSection {
                LoveLanguagePicker(language) { language = it }
                RowDivider()
                if (pairing.solo) {
                    GroupRow {
                        BText("For", BondType.body, modifier = Modifier.weight(1f))
                        BText("You", BondType.body, colors.inkSecondary)
                    }
                } else {
                    GroupRow {
                        BText("For", BondType.body)
                        Spacer(Modifier.width(Spacing.base))
                        Segmented(ReminderTarget.entries, target, { it.title }, Modifier.weight(1f)) { target = it }
                    }
                    if (target == ReminderTarget.PARTNER) {
                        RowDivider()
                        ToggleRow("Surprise (hidden from partner)", surpriseHidden, tag = "editor.surprise") { surpriseHidden = it }
                    }
                }
            }

            GroupSection(
                header = "When",
                footer = if (!store.isPremium) ({ BText("Surprise-in-a-window needs Little Gestures+.", BondType.caption, colors.inkSecondary) }) else null,
            ) {
                MenuPickerRow("Schedule", kinds, kind, { it.title }, tag = "editor.schedule", onSelect = ::selectKind)
                RowDivider()
                when (kind) {
                    TriggerKind.ONE_TIME -> DateTimeRow("Date & time", fireAt, { fireAt = it }, tag = "editor.fireAt")
                    TriggerKind.RECURRING -> {
                        DateTimeRow("Starting", fireAt, { fireAt = it }, tag = "editor.fireAt")
                        RowDivider()
                        MenuPickerRow("Repeat", RecurrencePreset.entries, recurrence, { it.title }, tag = "editor.repeat") { recurrence = it }
                    }
                    TriggerKind.LOCATION -> {
                        GroupRow {
                            Box(Modifier.weight(1f)) { FormTextField(geofenceLabel, { geofenceLabel = it }, "Place name", tag = "editor.place") }
                            if (geofence != null) Icon(Icons.Rounded.CheckCircle, null, tint = colors.success)
                        }
                        geofence?.let { g ->
                            RowDivider()
                            GroupRow {
                                Icon(Icons.Rounded.Place, null, tint = colors.inkSecondary, modifier = Modifier.size(16.dp))
                                Spacer(Modifier.width(Spacing.s))
                                BText(
                                    String.format(java.util.Locale.US, "%.4f, %.4f (200m radius)", g.latitude, g.longitude) +
                                        "\nArrival alerts fire on iPhone. Android can't trigger place reminders yet.",
                                    BondType.caption2, colors.inkSecondary,
                                )
                            }
                        }
                    }
                    TriggerKind.RANDOM_WINDOW -> {
                        ToggleRow("Repeat every day", repeatsDaily, tag = "editor.repeatDaily") { repeatsDaily = it }
                        RowDivider()
                        if (repeatsDaily) {
                            DateTimeRow("Between", dailyStart, { dailyStart = it }, showDate = false, tag = "editor.dailyStart")
                            RowDivider()
                            DateTimeRow("and", dailyEnd, { dailyEnd = it }, showDate = false, tag = "editor.dailyEnd")
                            RowDivider()
                            if (minutesOfDay(dailyEnd) <= minutesOfDay(dailyStart)) {
                                Hint("The end time must be after the start time.", colors.warning)
                            } else {
                                Hint("Fires once a day, at a different random time in this window each day.", colors.inkSecondary)
                            }
                        } else {
                            DateTimeRow("Earliest", windowStart, { windowStart = it }, tag = "editor.windowStart")
                            RowDivider()
                            DateTimeRow("Latest", windowEnd, { windowEnd = it }, tag = "editor.windowEnd")
                            RowDivider()
                            if (!windowEnd.isAfter(windowStart)) {
                                Hint("Latest must be after Earliest.", colors.warning)
                            } else {
                                Hint("Little Gestures will pick one random moment in this window.", colors.inkSecondary)
                            }
                        }
                    }
                }
            }

            errorMessage?.let { message ->
                GroupSection { GroupRow { BText(message, BondType.footnote, colors.danger) } }
            }

            Column {
                com.jackwallner.bond.ui.components.SectionHeader(
                    if (existing == null) "Need an idea?" else "Templates",
                    modifier = Modifier.padding(horizontal = Spacing.base),
                )
                if (existing == null && trimmedTitle.isEmpty()) {
                    Row(
                        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.base, vertical = Spacing.s),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.s),
                    ) {
                        StarterChips.forPreferences(graph.prefs.focusAreas, graph.prefs.partnerLoveLanguage).forEach { chip ->
                            Row(
                                Modifier.clip(CircleShape).background(colors.cardFill).border(BorderStroke(0.5.dp, colors.hairline), CircleShape)
                                    .clickable { title = chip.title; language = chip.loveLanguage }
                                    .padding(horizontal = Spacing.m, vertical = Spacing.s)
                                    .semantics { contentDescription = "Use suggestion: ${chip.title}" }
                                    .testTag("editor.chip.${chip.title}"),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(chip.loveLanguage.icon, null, tint = colors.tint(chip.loveLanguage), modifier = Modifier.size(14.dp))
                                Spacer(Modifier.width(Spacing.xs))
                                BText(chip.title, BondType.caption, maxLines = 1)
                            }
                        }
                    }
                }
                GroupSection {
                    GroupRow(onClick = { sheets.presentTemplates() }, tag = "editor.templates") {
                        Icon(Icons.Rounded.GridView, null, tint = colors.accent, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(Spacing.m))
                        BText("Browse reminder templates", BondType.body, colors.accent)
                    }
                }
            }
        }
    }
}

@Composable
private fun Hint(text: String, color: Color) {
    BText(text, BondType.footnote, color, modifier = Modifier.padding(horizontal = Spacing.base, vertical = 10.dp))
}

/** Label on its own line, then one scrollable row of chips under it. */
@Composable
private fun LoveLanguagePicker(selected: LoveLanguage, onSelect: (LoveLanguage) -> Unit) {
    val colors = Bond.colors
    Column(Modifier.fillMaxWidth().padding(vertical = Spacing.m), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        BText("Love language", BondType.body, modifier = Modifier.padding(horizontal = Spacing.base))
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.base),
            horizontalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            LoveLanguage.entries.forEach { lang ->
                val on = lang == selected
                val tint = colors.tint(lang)
                Row(
                    Modifier.clip(CircleShape).background(if (on) tint else tint.copy(alpha = 0.12f)).clickable { onSelect(lang) }
                        .padding(horizontal = Spacing.m, vertical = Spacing.s).testTag("editor.lang.${lang.raw}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(lang.icon, null, tint = if (on) Color.White else tint, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(Spacing.xs))
                    BText(lang.title, if (on) BondType.footnote.semibold else BondType.footnote, if (on) Color.White else tint, maxLines = 1)
                }
            }
        }
    }
}
