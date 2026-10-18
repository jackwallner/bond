package com.jackwallner.bond.model

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

// Per-occurrence completion (`ReminderCompletion.swift`). A one-shot reminder
// is completed forever by one acted event; a repeating one only for its period.

/** Start of the completion period containing [now], or null when completion is one-shot. */
fun ReminderDto.currentPeriodStart(
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
    locale: Locale = Locale.getDefault(),
): Instant? {
    val today = now.atZone(zone).toLocalDate()
    val start: LocalDate = when (val t = trigger) {
        is ReminderTrigger.Recurring -> when (RecurrencePreset.fromRrule(t.rrule) ?: RecurrencePreset.DAILY) {
            RecurrencePreset.DAILY -> today
            RecurrencePreset.WEEKLY -> {
                val first: DayOfWeek = WeekFields.of(locale).firstDayOfWeek
                today.with(TemporalAdjusters.previousOrSame(first))
            }
            RecurrencePreset.MONTHLY -> today.withDayOfMonth(1)
            RecurrencePreset.YEARLY -> today.withDayOfYear(1)
        }
        is ReminderTrigger.RandomRecurring -> today
        else -> return null
    }
    return start.atStartOfDay(zone).toInstant()
}

/** True when this reminder comes back on a schedule, so completion applies per period. */
fun ReminderDto.repeatsOnSchedule(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean =
    currentPeriodStart(now, zone) != null

fun ReminderDto.isCompleted(
    events: List<ReminderEventDto>,
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
): Boolean = currentCompletionEvent(events, now, zone) != null

/** The acted event covering the current period. For one-shot reminders, any acted event. */
fun ReminderDto.currentCompletionEvent(
    events: List<ReminderEventDto>,
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
): ReminderEventDto? {
    val acted = events.filter { it.reminderId == id && it.actedAt != null }
    val periodStart = currentPeriodStart(now, zone) ?: return acted.firstOrNull()
    return acted.firstOrNull { !(it.actedAt ?: it.firedAt).isBefore(periodStart) }
}

/**
 * `MilestoneDTO.nextOccurrence`: this year's anniversary of [MilestoneDto.date],
 * or next year's once it has passed. Feb 29 rolls to Mar 1 in other years.
 * The result is local midnight, compared against [reference] as an instant.
 */
fun MilestoneDto.nextOccurrence(
    reference: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
): LocalDate {
    if (!recur) return date
    val year = reference.atZone(zone).year
    fun onYear(y: Int): LocalDate =
        if (date.monthValue == 2 && date.dayOfMonth == 29 && !java.time.Year.isLeap(y.toLong())) {
            LocalDate.of(y, 3, 1)
        } else {
            LocalDate.of(y, date.monthValue, date.dayOfMonth)
        }
    val thisYear = onYear(year)
    // Foundation keeps the Mar 1 substitution when it advances the year, so a
    // Feb 29 that rolled forward stays Mar 1 next year too.
    val rolled = thisYear.monthValue == 3 && date.monthValue == 2
    return if (thisYear.atStartOfDay(zone).toInstant().isBefore(reference)) {
        if (rolled) LocalDate.of(year + 1, 3, 1) else onYear(year + 1)
    } else {
        thisYear
    }
}
