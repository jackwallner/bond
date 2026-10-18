package com.jackwallner.bond.model

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.random.Random

/** One local notification, the Android stand-in for a `UNNotificationRequest`. */
data class NotificationSpec(
    val id: String,
    val title: String,
    val body: String?,
    val fireAt: Instant,
    val reminderId: UUID? = null,
    /** Recurring reminders re-arm themselves on delivery, like a repeating calendar trigger. */
    val repeat: RecurrencePreset? = null,
    /** The anchor whose clock fields the repeat matches (`recurrenceComponents` on iOS). */
    val anchor: Instant? = null,
)

/**
 * The scheduling rules of `NotificationScheduler.swift`, minus the platform:
 * which reminders ping, when, and with what text. Location reminders are left
 * out (no geofencing on Android, see `.claude/rules/android.md`).
 */
object NotificationPlanner {
    const val RANDOM_RECURRING_RUNWAY_DAYS = 5

    fun reminderSpecs(
        selfId: UUID,
        reminders: List<ReminderDto>,
        events: List<ReminderEventDto>,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        random: Random = Random.Default,
    ): List<NotificationSpec> {
        val specs = mutableListOf<NotificationSpec>()
        for (reminder in reminders) {
            if (reminder.targetId != selfId) continue
            val completed = reminder.isCompleted(events, now, zone)
            // A handled one-shot is done forever; never ping it again.
            if (completed && !reminder.repeatsOnSchedule(now, zone)) continue
            specs += specsFor(reminder, completed, now, zone, random)
        }
        return specs
    }

    private fun specsFor(
        reminder: ReminderDto,
        completedThisPeriod: Boolean,
        now: Instant,
        zone: ZoneId,
        random: Random,
    ): List<NotificationSpec> {
        val body = reminder.body?.takeIf { it.isNotEmpty() }
        return when (val trigger = reminder.trigger) {
            is ReminderTrigger.OneTime -> listOfNotNull(
                oneShot(reminder, trigger.fireAt, body, now),
            )
            is ReminderTrigger.Recurring -> {
                val preset = RecurrencePreset.fromRrule(trigger.rrule) ?: return emptyList()
                val next = nextCalendarMatch(trigger.nextFire, preset, now, zone) ?: return emptyList()
                listOf(
                    NotificationSpec(
                        reminder.id.toString(), reminder.title, body, next, reminder.id,
                        repeat = preset, anchor = trigger.nextFire,
                    ),
                )
            }
            // The fire time was randomized at save time; schedule it as a one-time ping.
            is ReminderTrigger.RandomWindow -> listOfNotNull(reminder.fireAt?.let { oneShot(reminder, it, body, now) })
            is ReminderTrigger.RandomRecurring -> randomRecurring(reminder, trigger, completedThisPeriod, body, now, zone, random)
            is ReminderTrigger.Location, null -> emptyList()
        }
    }

    private fun oneShot(reminder: ReminderDto, fireAt: Instant, body: String?, now: Instant): NotificationSpec? {
        val minute = fireAt.truncatedTo(ChronoUnit.MINUTES)
        if (!fireAt.isAfter(now)) return null
        return NotificationSpec(reminder.id.toString(), reminder.title, body, minute, reminder.id)
    }

    /**
     * No "daily at a random time" trigger exists, so the next five days go down
     * as separate one-time pings, each at a stable pick inside that day's window.
     */
    private fun randomRecurring(
        reminder: ReminderDto,
        trigger: ReminderTrigger.RandomRecurring,
        skipToday: Boolean,
        body: String?,
        now: Instant,
        zone: ZoneId,
        random: Random,
    ): List<NotificationSpec> {
        val start = trigger.start.atZone(zone)
        val end = trigger.end.atZone(zone)
        val today = now.atZone(zone).toLocalDate()
        val specs = mutableListOf<NotificationSpec>()
        for (offset in 0 until RANDOM_RECURRING_RUNWAY_DAYS) {
            if (offset == 0 && skipToday) continue
            val day = today.plusDays(offset.toLong())
            val dayStart = day.atStartOfDay(zone).toInstant()
            val windowStart = day.atTime(start.hour, start.minute).atZone(zone).toInstant()
            val windowEnd = day.atTime(end.hour, end.minute).atZone(zone).toInstant()
            if (!windowEnd.isAfter(windowStart)) continue
            var fireAt = stablePick(windowStart, windowEnd, reminder.id, dayStart)
            if (!fireAt.isAfter(now)) {
                // Today's pick already passed. Only a reminder created today after its
                // pick (so never scheduled) falls forward into what is left of the window.
                val created = reminder.createdAt ?: Instant.MIN
                val createdToday = reminder.createdAt?.atZone(zone)?.toLocalDate() == today
                if (!windowEnd.isAfter(now) || !created.isAfter(fireAt) || !createdToday) continue
                val span = windowEnd.toEpochMilli() - now.toEpochMilli()
                fireAt = Instant.ofEpochMilli(now.toEpochMilli() + random.nextLong(0, span + 1))
            }
            specs += NotificationSpec(
                "${reminder.id}.day$offset", reminder.title, body,
                fireAt.truncatedTo(ChronoUnit.MINUTES), reminder.id,
            )
        }
        return specs
    }

    /**
     * FNV-1a over the uppercase UUID string and the day ordinal, as iOS does, so
     * both platforms pick the same moment for the same reminder on the same day.
     */
    fun stablePick(start: Instant, end: Instant, reminderId: UUID, day: Instant): Instant {
        var hash = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        val dayOrdinal = (day.epochSecond.toDouble() / 86_400).toLong()
        val bytes = reminderId.toString().uppercase().toByteArray(Charsets.UTF_8) +
            dayOrdinal.toString().toByteArray(Charsets.UTF_8)
        for (byte in bytes) {
            hash = hash xor (byte.toLong() and 0xff)
            hash *= 0x100000001b3L
        }
        val unit = java.lang.Long.remainderUnsigned(hash, 1_000_000L).toDouble() / 1_000_000.0
        val interval = (end.toEpochMilli() - start.toEpochMilli()) / 1000.0
        val seconds = interval * unit
        return start.plusNanos((seconds * 1_000_000_000).toLong())
    }

    /**
     * The next moment after [after] that matches [anchor]'s clock fields for
     * [preset]: hour and minute daily, plus weekday weekly, day of month monthly
     * (months without that day are skipped), month and day yearly.
     */
    fun nextCalendarMatch(anchor: Instant, preset: RecurrencePreset, after: Instant, zone: ZoneId): Instant? {
        val a = anchor.atZone(zone)
        val from = after.atZone(zone).toLocalDate()
        fun candidate(date: LocalDate): Instant? {
            val local = LocalDateTime.of(date, java.time.LocalTime.of(a.hour, a.minute))
            val instant = local.atZone(zone).toInstant()
            return instant.takeIf { it.isAfter(after) }
        }
        when (preset) {
            RecurrencePreset.DAILY -> for (i in 0..2) candidate(from.plusDays(i.toLong()))?.let { return it }
            RecurrencePreset.WEEKLY -> for (i in 0..14) {
                val date = from.plusDays(i.toLong())
                if (date.dayOfWeek == a.dayOfWeek) candidate(date)?.let { return it }
            }
            RecurrencePreset.MONTHLY -> {
                var month = YearMonth.from(from)
                repeat(48) {
                    if (a.dayOfMonth <= month.lengthOfMonth()) candidate(month.atDay(a.dayOfMonth))?.let { return it }
                    month = month.plusMonths(1)
                }
            }
            RecurrencePreset.YEARLY -> for (y in from.year..from.year + 8) {
                val month = YearMonth.of(y, a.monthValue)
                if (a.dayOfMonth <= month.lengthOfMonth()) candidate(month.atDay(a.dayOfMonth))?.let { return it }
            }
        }
        return null
    }

    /** Up to three pings per milestone at 9am local: a week before, the day before, and the day of. */
    fun milestoneSpecs(
        milestones: List<MilestoneDto>,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<NotificationSpec> = milestones.flatMap { milestone ->
        val occurrence = milestone.nextOccurrence(now, zone)
        val fireOn = occurrence.atStartOfDay(zone).plusHours(9)
        val title = milestone.label?.takeIf { it.isNotEmpty() } ?: milestone.kind.capitalizedWords()
        listOf(-7 to "in 1 week", -1 to "tomorrow", 0 to "today").mapNotNull { (days, phrase) ->
            val fireAt = fireOn.plusDays(days.toLong()).toInstant()
            if (!fireAt.isAfter(now)) null
            else NotificationSpec("milestone.${milestone.id}.$days", title, "$title is $phrase.", fireAt)
        }
    }
}
