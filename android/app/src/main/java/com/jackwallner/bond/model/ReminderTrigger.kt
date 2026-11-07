package com.jackwallner.bond.model

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

/** `ReminderTrigger.swift`: how and when a reminder fires. */
sealed class ReminderTrigger {
    data class OneTime(val fireAt: Instant) : ReminderTrigger()
    data class Recurring(val rrule: String, val nextFire: Instant) : ReminderTrigger()
    data class Location(val geofence: Geofence, val onEntry: Boolean) : ReminderTrigger()
    data class RandomWindow(val start: Instant, val end: Instant) : ReminderTrigger()

    /**
     * Fires once per day at a random moment inside a time-of-day window. `start`
     * and `end` carry the window's time of day; their date is only the anchor.
     */
    data class RandomRecurring(val start: Instant, val end: Instant) : ReminderTrigger()

    val kindRaw: String
        get() = when (this) {
            is OneTime -> "one_time"
            is Recurring -> "recurring"
            is Location -> "location"
            is RandomWindow, is RandomRecurring -> "random_window"
        }

    val nextFireDate: Instant?
        get() = when (this) {
            is OneTime -> fireAt
            is Recurring -> nextFire
            is RandomWindow -> end
            is RandomRecurring -> end
            is Location -> null
        }

    /**
     * Future-aware next fire. Recurring triggers count whole steps from the
     * stored anchor to the first occurrence after [reference].
     */
    fun upcomingFireDate(reference: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant? =
        when (this) {
            is OneTime -> fireAt
            is Recurring -> {
                val preset = RecurrencePreset.fromRrule(rrule)
                if (preset == null) nextFire else preset.firstOccurrence(reference, nextFire, zone)
            }
            is RandomWindow -> end
            is RandomRecurring -> nextWindow(reference, zone)?.second
            is Location -> null
        }

    /**
     * For [RandomRecurring]: the next daily window whose end is still ahead of
     * [reference], today's if it has not closed yet, else tomorrow's.
     */
    fun nextWindow(reference: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Pair<Instant, Instant>? {
        if (this !is RandomRecurring) return null
        val startLocal = start.atZone(zone)
        val endLocal = end.atZone(zone)
        var day = reference.atZone(zone).toLocalDate()
        repeat(2) {
            val windowStart = day.atTime(startLocal.hour, startLocal.minute).atZone(zone).toInstant()
            val windowEnd = day.atTime(endLocal.hour, endLocal.minute).atZone(zone).toInstant()
            if (windowEnd.isAfter(reference)) return windowStart to windowEnd
            day = day.plusDays(1)
        }
        return null
    }
}

/** `RecurrencePreset.swift`: the four schedules, serialized as RFC 5545 rules. */
enum class RecurrencePreset(val title: String, val rrule: String) {
    DAILY("Every day", "FREQ=DAILY"),
    WEEKLY("Every week", "FREQ=WEEKLY"),
    MONTHLY("Every month", "FREQ=MONTHLY"),
    YEARLY("Every year", "FREQ=YEARLY");

    /** One calendar step later, clamping to the month's last day like Foundation. */
    fun nextOccurrence(after: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant {
        val local: ZonedDateTime = after.atZone(zone)
        val next = when (this) {
            DAILY -> local.plusDays(1)
            WEEKLY -> local.plusWeeks(1)
            MONTHLY -> local.plusMonths(1)
            YEARLY -> local.plusYears(1)
        }
        return next.toInstant()
    }

    private fun unit(): ChronoUnit = when (this) {
        DAILY -> ChronoUnit.DAYS
        WEEKLY -> ChronoUnit.WEEKS
        MONTHLY -> ChronoUnit.MONTHS
        YEARLY -> ChronoUnit.YEARS
    }

    /**
     * The [n]-th occurrence counted from the anchor in whole steps, so a monthly
     * reminder on the 31st lands on the last day of a short month and is back on
     * the 31st after it, as the server counts it (`reminder_next_push_at`).
     * Stepping from the previous occurrence drifted to the 28th for good.
     */
    fun occurrence(n: Long, anchor: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        anchor.atZone(zone).plus(n, unit()).toInstant()

    /** Index of the first occurrence strictly after [reference]. */
    fun firstIndex(reference: Instant, anchor: Instant, zone: ZoneId = ZoneId.systemDefault()): Long {
        if (anchor.isAfter(reference)) return 0
        val elapsed = unit().between(anchor.atZone(zone), reference.atZone(zone))
        var n = maxOf(0L, elapsed - 1)
        while (!occurrence(n, anchor, zone).isAfter(reference)) n += 1
        return n
    }

    /** The first occurrence strictly after [reference]. */
    fun firstOccurrence(reference: Instant, anchor: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        occurrence(firstIndex(reference, anchor, zone), anchor, zone)

    companion object {
        fun fromRrule(rrule: String): RecurrencePreset? {
            val normalized = rrule.uppercase()
            return entries.firstOrNull { normalized.contains(it.rrule) }
        }
    }
}

/** Truncate to the minute, the precision the iOS editor and notifications use. */
fun Instant.toMinute(): Instant = truncatedTo(ChronoUnit.MINUTES)
