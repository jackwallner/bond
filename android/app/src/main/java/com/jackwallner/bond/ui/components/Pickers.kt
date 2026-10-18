package com.jackwallner.bond.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import android.text.format.DateFormat
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

private val zone: ZoneId get() = ZoneId.systemDefault()

/** A grey value chip like the compact iOS `DatePicker`. */
@Composable
fun ValueChip(text: String, tag: String? = null, onClick: () -> Unit) {
    Box(
        Modifier.clip(RoundedCornerShape(8.dp)).background(Bond.colors.hairline).clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp).then(if (tag != null) Modifier.testTag(tag) else Modifier),
    ) {
        BText(text, BondType.subheadline, maxLines = 1)
    }
}

/** A labelled row with a date chip and/or a time chip (`DatePicker` in a Form). */
@Composable
fun DateTimeRow(
    label: String,
    value: Instant,
    onChange: (Instant) -> Unit,
    showDate: Boolean = true,
    showTime: Boolean = true,
    tag: String = label,
) {
    var pickingDate by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    val local = value.atZone(zone)
    GroupRow {
        BText(label, BondType.body, modifier = Modifier.weight(1f))
        if (showDate) {
            ValueChip(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()).format(local), "$tag.date") { pickingDate = true }
        }
        if (showDate && showTime) Spacer(Modifier.width(6.dp))
        if (showTime) {
            ValueChip(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()).format(local), "$tag.time") { pickingTime = true }
        }
    }
    if (pickingDate) {
        DatePickerSheet(local.toLocalDate(), onDismiss = { pickingDate = false }) { date ->
            pickingDate = false
            onChange(date.atTime(local.toLocalTime()).atZone(zone).toInstant())
        }
    }
    if (pickingTime) {
        TimePickerSheet(local.toLocalTime(), onDismiss = { pickingTime = false }) { time ->
            pickingTime = false
            onChange(local.toLocalDate().atTime(time).atZone(zone).toInstant().truncatedTo(ChronoUnit.MINUTES))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DatePickerSheet(initial: LocalDate, onDismiss: () -> Unit, onPick: (LocalDate) -> Unit) {
    val colors = Bond.colors
    val state = rememberDatePickerState(initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val millis = state.selectedDateMillis
                if (millis == null) onDismiss() else onPick(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate())
            }, modifier = Modifier.testTag("picker.ok")) { BText("OK", BondType.body, colors.accent) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { BText("Cancel", BondType.body, colors.accent) } },
        colors = DatePickerDefaults.colors(containerColor = colors.surfaceElevated),
    ) {
        DatePicker(
            state = state,
            colors = DatePickerDefaults.colors(
                containerColor = colors.surfaceElevated,
                selectedDayContainerColor = colors.accent,
                todayDateBorderColor = colors.accent,
                todayContentColor = colors.accent,
            ),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimePickerSheet(initial: LocalTime, onDismiss: () -> Unit, onPick: (LocalTime) -> Unit) {
    val colors = Bond.colors
    val context = LocalContext.current
    val state = rememberTimePickerState(initial.hour, initial.minute, DateFormat.is24HourFormat(context))
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onPick(LocalTime.of(state.hour, state.minute)) }, modifier = Modifier.testTag("picker.ok")) {
                BText("OK", BondType.body, colors.accent)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { BText("Cancel", BondType.body, colors.accent) } },
        text = {
            TimePicker(
                state = state,
                colors = TimePickerDefaults.colors(
                    selectorColor = colors.accent,
                    timeSelectorSelectedContainerColor = colors.accent.copy(alpha = 0.2f),
                    periodSelectorSelectedContainerColor = colors.accent.copy(alpha = 0.2f),
                ),
            )
        },
        containerColor = colors.surfaceElevated,
    )
}

/** iOS `Toggle` in a Form row. */
@Composable
fun ToggleRow(label: String, checked: Boolean, tag: String? = null, onChange: (Boolean) -> Unit) {
    val colors = Bond.colors
    GroupRow(onClick = { onChange(!checked) }, tag = tag) {
        BText(label, BondType.body, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = colors.success, checkedThumbColor = Color.White, checkedBorderColor = colors.success),
        )
    }
}

/** iOS menu `Picker` in a Form row: the label, the current value, and a dropdown. */
@Composable
fun <T> MenuPickerRow(
    label: String,
    options: List<T>,
    selected: T,
    title: (T) -> String,
    tag: String? = null,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val colors = Bond.colors
    GroupRow(onClick = { expanded = true }, tag = tag) {
        BText(label, BondType.body, modifier = Modifier.weight(1f))
        Box {
            BText(title(selected), BondType.body, colors.inkSecondary)
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = colors.surfaceElevated) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { BText(title(option), BondType.body) },
                        onClick = { expanded = false; onSelect(option) },
                        modifier = Modifier.testTag("option.${title(option)}"),
                    )
                }
            }
        }
    }
}

/** iOS segmented `Picker`. */
@Composable
fun <T> Segmented(options: List<T>, selected: T, title: (T) -> String, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    val colors = Bond.colors
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(colors.hairline).padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        options.forEach { option ->
            val on = option == selected
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(7.dp))
                    .background(if (on) colors.surfaceElevated else Color.Transparent)
                    .clickable { onSelect(option) }.heightIn(min = 32.dp).padding(vertical = 6.dp)
                    .testTag("segment.${title(option)}"),
                contentAlignment = Alignment.Center,
            ) {
                BText(title(option), if (on) BondType.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold) else BondType.footnote)
            }
        }
    }
}

/** A multi-line text field styled as a Form row. */
@Composable
fun FormTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    tag: String,
    singleLine: Boolean = true,
    minLines: Int = 1,
) {
    val colors = Bond.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.base, vertical = 12.dp)) {
        androidx.compose.foundation.text.BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = singleLine,
            minLines = minLines,
            maxLines = if (singleLine) 1 else 6,
            textStyle = BondType.body.copy(color = colors.ink),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.accent),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences,
            ),
            modifier = Modifier.fillMaxWidth().testTag(tag),
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty()) BText(placeholder, BondType.body, colors.inkTertiary)
                    inner()
                }
            },
        )
    }
}
