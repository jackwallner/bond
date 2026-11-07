package com.jackwallner.bond.model

import java.time.Instant
import java.time.LocalDate
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
    /** A daily random reminder gets one weekly repeating ping per weekday. */
    const val RANDOM_RECURRING_DAYS = 7

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
     * No "daily at a random time" trigger exists. Each weekday gets its own
     * weekly repeating ping at that day's stable pick inside the window, so the
     * reminder fires every day even if the app is never opened again (one-time
     * pings ran out after five days). Every rebuild (app open, save, completion)
     * picks new moments for the coming week.
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

        fun window(day: LocalDate): Triple<Instant, Instant, Instant>? {
            val windowStart = day.atTime(start.hour, start.minute).atZone(zone).toInstant()
            val windowEnd = day.atTime(end.hour, end.minute).atZone(zone).toInstant()
            if (!windowEnd.isAfter(windowStart)) return null
            return Triple(day.atStartOfDay(zone).toInstant(), windowStart, windowEnd)
        }

        fun weekly(id: String, at: Instant): NotificationSpec {
            val anchor = at.truncatedTo(ChronoUnit.MINUTES)
            val first = RecurrencePreset.WEEKLY.firstOccurrence(now, anchor, zone)
            return NotificationSpec(id, reminder.title, body, first, reminder.id, RecurrencePreset.WEEKLY, anchor)
        }

        val specs = mutableListOf<NotificationSpec>()
        for (offset in 0 until RANDOM_RECURRING_DAYS) {
            val day = today.plusDays(offset.toLong())
            val (dayStart, windowStart, windowEnd) = window(day) ?: continue
            val id = "${reminder.id}.day$offset"
            val pick = stablePick(windowStart, windowEnd, reminder.id, dayStart)

            if (offset > 0) {
                specs += weekly(id, pick)
                continue
            }
            if (pick.isAfter(now) && skipToday) {
                // Done today before today's moment: today's ping must not ring today.
                // A moment already behind us next fires in a week.
                val latest = now.minusSeconds(60)
                if (latest.isAfter(windowStart)) {
                    specs += weekly(id, stablePick(windowStart, latest, reminder.id, dayStart))
                } else {
                    val nextWeek = day.plusDays(7)
                    val (nextDayStart, nextStart, nextEnd) = window(nextWeek) ?: continue
                    val at = stablePick(nextStart, nextEnd, reminder.id, nextDayStart)
                    oneShot(reminder, at, body, now)?.let { specs += it.copy(id = id) }
                }
                continue
            }
            specs += weekly(id, pick)
            // Today's pick already passed. Picking again later in the window would ping
            // again on every rebuild (each app open runs this, including the open caused
            // by tapping today's notification). Only a reminder created today after its
            // pick, which therefore never rang, falls forward into what is left of the window.
            val created = reminder.createdAt ?: continue
            if (pick.isAfter(now) || skipToday || !windowEnd.isAfter(now) ||
                !created.isAfter(pick) || created.atZone(zone).toLocalDate() != today
            ) continue
            val span = windowEnd.toEpochMilli() - now.toEpochMilli()
            val fallForward = Instant.ofEpochMilli(now.toEpochMilli() + random.nextLong(0, span + 1))
            oneShot(reminder, fallForward, body, now)?.let { specs += it.copy(id = "${reminder.id}.today") }
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
     * The first occurrence of [preset] after [after], counted in whole steps from
     * [anchor] like the list and the server do: a recurring reminder that starts
     * later first fires at its start, and a monthly reminder on the 29th to the
     * 31st (or a yearly one on February 29) lands on the last day of a shorter
     * month instead of skipping it.
     */
    fun nextCalendarMatch(anchor: Instant, preset: RecurrencePreset, after: Instant, zone: ZoneId): Instant? =
        preset.firstOccurrence(after, anchor.truncatedTo(ChronoUnit.MINUTES), zone)

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
