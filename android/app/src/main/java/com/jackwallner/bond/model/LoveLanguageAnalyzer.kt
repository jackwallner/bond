package com.jackwallner.bond.model

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.pow

/** `LoveLanguageAnalyzer.swift`: plain statistics over reminders and completion events. */
class LoveLanguageAnalyzer(
    private val reminders: List<ReminderDto>,
    private val events: List<ReminderEventDto>,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val locale: Locale = Locale.getDefault(),
) {
    data class FollowThrough(val reminder: ReminderDto, val expected: Int, val completed: Int) {
        val id: UUID get() = reminder.id
    }

    data class LanguageCompletion(val language: LoveLanguage, val expected: Int, val completed: Int)

    data class WeeklyTrend(val weekStart: LocalDate, val counts: List<Pair<LoveLanguage, Int>>)

    private val reminderMap: Map<UUID, ReminderDto> by lazy { reminders.associateBy { it.id } }

    fun reminderCounts(): List<Pair<LoveLanguage, Int>> {
        val tally = reminders.groupingBy { it.loveLanguage }.eachCount()
        return LoveLanguage.entries.map { it to (tally[it] ?: 0) }
    }

    fun completionCounts(): List<Pair<LoveLanguage, Int>> {
        val tally = events.filter { it.actedAt != null }
            .mapNotNull { reminderMap[it.reminderId]?.loveLanguage }
            .groupingBy { it }.eachCount()
        return LoveLanguage.entries.map { it to (tally[it] ?: 0) }
    }

    fun eventCounts(): List<Pair<LoveLanguage, Int>> {
        val tally = events.mapNotNull { reminderMap[it.reminderId]?.loveLanguage }.groupingBy { it }.eachCount()
        return LoveLanguage.entries.map { it to (tally[it] ?: 0) }
    }

    /** 0 to 100, where 100 is an even spread across all five languages. */
    fun balanceScore(): Double {
        val counts = reminderCounts()
        val total = counts.sumOf { it.second }
        if (total <= 0) return 0.0
        val ideal = total / 5.0
        val variance = counts.sumOf { (it.second - ideal).pow(2) } / 5.0
        val maxVariance = total.toDouble().pow(2) / 5.0
        val normalized = if (maxVariance > 0) 1.0 - variance / maxVariance else 1.0
        return max(0.0, normalized * 100)
    }

    fun mostNeglected(): Pair<LoveLanguage, Double>? {
        val counts = reminderCounts()
        val total = counts.sumOf { it.second }
        if (total <= 0) return null
        val ideal = total / 5.0
        return counts.minByOrNull { it.second }?.let { it.first to (ideal - it.second) }
    }

    fun mostUsed(): Pair<LoveLanguage, Int>? = reminderCounts().maxByOrNull { it.second }

    private fun startOfDay(instant: Instant): LocalDate = instant.atZone(zone).toLocalDate()

    private fun Instant.atDayStart(): Instant = atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()

    /** Per-reminder follow-through for repeating reminders over the trailing [days] days. */
    fun followThrough(days: Int = 7, now: Instant = Instant.now()): List<FollowThrough> {
        val windowStart = startOfDay(now).minusDays((days - 1).toLong()).atStartOfDay(zone).toInstant()
        return reminders.mapNotNull { reminder ->
            val starts = periodStarts(reminder, windowStart, now)
            val preset = recurrencePreset(reminder)
            if (starts.isEmpty() || preset == null) return@mapNotNull null
            val actedDates = events.filter { it.reminderId == reminder.id }.mapNotNull { it.actedAt }
            val completed = starts.count { start ->
                val end = preset.nextOccurrence(start, zone)
                actedDates.any { !it.isBefore(start) && it.isBefore(end) }
            }
            FollowThrough(reminder, starts.size, completed)
        }.sortedByDescending { it.expected }
    }

    fun completionByLanguage(days: Int = 7, now: Instant = Instant.now()): List<LanguageCompletion> {
        val windowStart = startOfDay(now).minusDays((days - 1).toLong()).atStartOfDay(zone).toInstant()
        val expected = mutableMapOf<LoveLanguage, Int>()
        val completed = mutableMapOf<LoveLanguage, Int>()
        for (item in followThrough(days, now)) {
            val lang = item.reminder.loveLanguage
            expected[lang] = (expected[lang] ?: 0) + item.expected
            completed[lang] = (completed[lang] ?: 0) + item.completed
        }
        for (reminder in reminders) {
            if (recurrencePreset(reminder) != null) continue
            val due = reminder.fireAt ?: continue
            if (due.isBefore(windowStart) || due.isAfter(now)) continue
            val done = events.any { it.reminderId == reminder.id && it.actedAt != null }
            val lang = reminder.loveLanguage
            expected[lang] = (expected[lang] ?: 0) + 1
            completed[lang] = (completed[lang] ?: 0) + if (done) 1 else 0
        }
        return LoveLanguage.entries.map { LanguageCompletion(it, expected[it] ?: 0, completed[it] ?: 0) }
    }

    /** Overall follow-through (0 to 100), or null when nothing was expected yet. */
    fun completionRate(days: Int = 7, now: Instant = Instant.now()): Double? {
        val perLanguage = completionByLanguage(days, now)
        val expected = perLanguage.sumOf { it.expected }
        if (expected <= 0) return null
        return perLanguage.sumOf { it.completed }.toDouble() / expected * 100
    }

    private fun recurrencePreset(reminder: ReminderDto): RecurrencePreset? = when (val t = reminder.trigger) {
        is ReminderTrigger.Recurring -> RecurrencePreset.fromRrule(t.rrule) ?: RecurrencePreset.DAILY
        is ReminderTrigger.RandomRecurring -> RecurrencePreset.DAILY
        else -> null
    }

    private fun periodStarts(reminder: ReminderDto, windowStart: Instant, now: Instant): List<Instant> {
        val preset = recurrencePreset(reminder) ?: return emptyList()
        var start = reminder.currentPeriodStart(now, zone, locale) ?: return emptyList()
        val born = reminder.createdAt ?: Instant.MIN
        val starts = mutableListOf<Instant>()
        repeat(60) {
            val end = preset.nextOccurrence(start, zone)
            // A period counts if it overlaps both the window and the reminder's lifetime.
            if (!end.isAfter(windowStart) || !end.isAfter(born)) return starts.reversed()
            starts.add(start)
            val local = start.atZone(zone)
            start = when (preset) {
                RecurrencePreset.DAILY -> local.minusDays(1)
                RecurrencePreset.WEEKLY -> local.minusWeeks(1)
                RecurrencePreset.MONTHLY -> local.minusMonths(1)
                RecurrencePreset.YEARLY -> local.minusYears(1)
            }.toInstant()
        }
        return starts.reversed()
    }

    fun weeklyTrends(): List<WeeklyTrend> {
        val firstDay: DayOfWeek = WeekFields.of(locale).firstDayOfWeek
        val weeks = sortedMapOf<LocalDate, MutableMap<LoveLanguage, Int>>()
        for (event in events) {
            val reminder = reminderMap[event.reminderId] ?: continue
            val weekStart = startOfDay(event.firedAt).with(TemporalAdjusters.previousOrSame(firstDay))
            val bucket = weeks.getOrPut(weekStart) { mutableMapOf() }
            bucket[reminder.loveLanguage] = (bucket[reminder.loveLanguage] ?: 0) + 1
        }
        return weeks.map { (week, tally) ->
            WeeklyTrend(week, LoveLanguage.entries.map { it to (tally[it] ?: 0) })
        }
    }

    fun insights(now: Instant = Instant.now()): List<String> {
        if (reminders.isEmpty()) return emptyList()
        val result = mutableListOf<String>()
        val balance = balanceScore()
        result += when {
            balance < 30 -> "Your love language expression is heavily imbalanced. Try adding reminders in your neglected areas."
            balance < 60 -> "You have a moderate spread of love languages. A few more in your lowest area could bring balance."
            else -> "Great balance! You're expressing love across all five languages."
        }
        mostNeglected()?.let { (lang, _) ->
            result += "${lang.title} is your least expressed love language. Consider adding more ${lang.title.lowercase()} reminders."
        }
        completionRate(now = now)?.let { rate ->
            val pct = rate.toInt()
            result += when {
                rate > 75 -> "Excellent follow-through! You completed $pct% of what was due this week."
                rate > 50 -> "Good progress: $pct% of this week's reminders done. Try to act on more when they fire."
                else -> "You completed $pct% of this week's reminders. Small consistent actions build strong habits."
            }
        }
        return result
    }

    private fun actedDays(): Set<LocalDate> =
        events.filter { it.actedAt != null }.map { startOfDay(it.actedAt ?: it.firedAt) }.toSet()

    /** Consecutive days with at least one completion. Today without one yet does not break it. */
    fun currentStreak(now: Instant = Instant.now()): Int {
        val days = actedDays()
        if (days.isEmpty()) return 0
        var check = startOfDay(now)
        if (check !in days) check = check.minusDays(1)
        var streak = 0
        while (check in days) {
            streak += 1
            check = check.minusDays(1)
        }
        return streak
    }

    fun longestStreak(): Int {
        val days = actedDays().sorted()
        if (days.isEmpty()) return 0
        var longest = 1
        var current = 1
        for (i in 1 until days.size) {
            if (ChronoUnit.DAYS.between(days[i - 1], days[i]) == 1L) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}
