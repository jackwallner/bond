package com.jackwallner.bond.model

import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** What the user wants to remember for their person (`IntentSetupView.swift`). */
enum class FocusArea(val raw: String, val title: String, val subtitle: String) {
    GESTURES("gestures", "Little gestures", "Day-to-day ways to show up."),
    DATES("dates", "Important dates", "Anniversaries, birthdays, plans."),
    LOVES("loves", "Things they love", "Favorites, hobbies, what they care about."),
    AVOID("avoid", "Things to avoid", "Topics, days, or things that hurt.");

    companion object {
        fun fromRaw(raw: String): FocusArea? = entries.firstOrNull { it.raw == raw }
    }
}

data class StarterChip(val title: String, val loveLanguage: LoveLanguage, val area: FocusArea = FocusArea.GESTURES)

object StarterChips {
    val pool: List<StarterChip> = listOf(
        StarterChip("Tell them they're beautiful", LoveLanguage.WORDS, FocusArea.GESTURES),
        StarterChip("Ten-minute walk together", LoveLanguage.TIME, FocusArea.GESTURES),
        StarterChip("Bring home flowers", LoveLanguage.GIFTS, FocusArea.GESTURES),
        StarterChip("A long hug at the door", LoveLanguage.TOUCH, FocusArea.GESTURES),
        StarterChip("Handle a chore they dread", LoveLanguage.ACTS, FocusArea.GESTURES),
        StarterChip("Note an upcoming date", LoveLanguage.TIME, FocusArea.DATES),
        StarterChip("Plan something for the weekend", LoveLanguage.TIME, FocusArea.DATES),
        StarterChip("Pick up their favorite snack", LoveLanguage.GIFTS, FocusArea.LOVES),
        StarterChip("Play a song they love", LoveLanguage.TIME, FocusArea.LOVES),
        StarterChip("Ask about something they care about", LoveLanguage.WORDS, FocusArea.LOVES),
        StarterChip("Note a topic to steer around", LoveLanguage.WORDS, FocusArea.AVOID),
        StarterChip("Phone away during dinner", LoveLanguage.TIME, FocusArea.AVOID),
    )

    /**
     * Only the selected focus areas (gestures when none), with the partner's
     * primary love language floated to the top, five at most.
     */
    fun forPreferences(focusAreas: Set<FocusArea>, primary: LoveLanguage): List<StarterChip> {
        val areas = focusAreas.ifEmpty { setOf(FocusArea.GESTURES) }
        return pool.filter { it.area in areas }
            .sortedBy { if (it.loveLanguage == primary) 0 else 1 }
            .take(5)
    }
}

data class TemplateReminder(
    val id: String,
    val title: String,
    val body: String?,
    val loveLanguage: LoveLanguage,
    val triggerRecurrence: RecurrencePreset?,
)

data class ReminderTemplateGroup(
    val id: String,
    val title: String,
    val subtitle: String,
    val reminders: List<TemplateReminder>,
)

/** `ReminderTemplate.swift`, word for word. */
object ReminderTemplateStore {
    private val daily = RecurrencePreset.DAILY
    private val weekly = RecurrencePreset.WEEKLY
    private val monthly = RecurrencePreset.MONTHLY

    val groups: List<ReminderTemplateGroup> = listOf(
        ReminderTemplateGroup(
            "daily_affirmations", "Daily Affirmations", "Send loving words every day",
            listOf(
                TemplateReminder("da_1", "Morning Affirmation", "Start the day with a loving message", LoveLanguage.WORDS, daily),
                TemplateReminder("da_2", "Goodnight Text", "A sweet goodnight message", LoveLanguage.WORDS, daily),
                TemplateReminder("da_3", "Weekend Love Note", "A heartfelt note for the weekend", LoveLanguage.WORDS, weekly),
            ),
        ),
        ReminderTemplateGroup(
            "date_night", "Date Night", "Keep the romance alive",
            listOf(
                TemplateReminder("dn_1", "Plan a Date Night", "Set aside quality time this week", LoveLanguage.TIME, weekly),
                TemplateReminder("dn_2", "Try Something New", "Explore a new activity together", LoveLanguage.TIME, monthly),
                TemplateReminder("dn_3", "Surprise Gesture", "A small surprise to show you care", LoveLanguage.GIFTS, monthly),
            ),
        ),
        ReminderTemplateGroup(
            "long_distance", "Long Distance", "Stay close from afar",
            listOf(
                TemplateReminder("ld_1", "Morning Check-In", "Say good morning even from far away", LoveLanguage.WORDS, daily),
                TemplateReminder("ld_2", "Video Call Reminder", "Time for a face-to-face chat", LoveLanguage.TIME, weekly),
                TemplateReminder("ld_3", "Send a Care Package", "Mail a little surprise", LoveLanguage.GIFTS, monthly),
                TemplateReminder("ld_4", "Virtual Movie Night", "Pick a movie and watch together", LoveLanguage.TIME, weekly),
            ),
        ),
        ReminderTemplateGroup(
            "new_parents", "New Parents", "Nurture your connection",
            listOf(
                TemplateReminder("np_1", "Check In with Each Other", "How are we both doing today?", LoveLanguage.WORDS, daily),
                TemplateReminder("np_2", "10 Minutes Just Us", "Find 10 minutes for just the two of you", LoveLanguage.TIME, daily),
                TemplateReminder("np_3", "Share the Load", "Take one task off your partner's plate today", LoveLanguage.ACTS, daily),
                TemplateReminder("np_4", "Hug and Breathe", "A long hug and a deep breath together", LoveLanguage.TOUCH, daily),
            ),
        ),
        ReminderTemplateGroup(
            "appreciation", "Daily Appreciation", "Never take each other for granted",
            listOf(
                TemplateReminder("ap_1", "Thank Your Partner", "Say thank you for something specific today", LoveLanguage.WORDS, daily),
                TemplateReminder("ap_2", "Notice the Little Things", "Compliment something small your partner did", LoveLanguage.WORDS, daily),
                TemplateReminder("ap_3", "Love Note", "Leave a note where your partner will find it", LoveLanguage.WORDS, weekly),
            ),
        ),
        ReminderTemplateGroup(
            "acts_of_service", "Acts of Service", "Show love through actions",
            listOf(
                TemplateReminder("as_1", "Make Them Breakfast", "Start their day with a made-with-love meal", LoveLanguage.ACTS, weekly),
                TemplateReminder("as_2", "Take Care of a Chore", "Handle something on their to-do list", LoveLanguage.ACTS, weekly),
                TemplateReminder("as_3", "Fill Up the Car", "A small act that saves them time", LoveLanguage.ACTS, weekly),
                TemplateReminder("as_4", "Run Their Errand", "Take care of one errand for them today", LoveLanguage.ACTS, weekly),
            ),
        ),
    )

    /**
     * When each reminder of an imported pack first fires. Each one gets its own
     * clock time, one no other reminder for the same person already uses, and
     * they start a day apart: a pack never rings together, with itself or with
     * anything imported before it (`TemplateSchedule` on iOS).
     */
    fun fireDates(
        templates: List<TemplateReminder>,
        target: UUID,
        existing: List<ReminderDto>,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<Instant> {
        val taken = existing.mapNotNull { reminder ->
            val fireAt = reminder.fireAt
            if (reminder.targetId != target || fireAt == null) return@mapNotNull null
            when (val trigger = reminder.trigger) {
                is ReminderTrigger.Recurring -> Unit
                is ReminderTrigger.OneTime -> if (!trigger.fireAt.isAfter(now)) return@mapNotNull null
                else -> return@mapNotNull null
            }
            val local = fireAt.atZone(zone)
            local.hour * 60 + local.minute
        }.toMutableSet()
        return templates.mapIndexed { index, template ->
            // Repeating reminders lead at 9:00, one-time nudges at 2:00 PM.
            val preferred = if (template.triggerRecurrence == null) 14 * 60 else 9 * 60
            val minute = (listOf(preferred) + SLOTS).firstOrNull { it !in taken }
                ?: (9 * 60 + 5 until 24 * 60 step 5).firstOrNull { it !in taken }
                ?: preferred
            taken += minute
            var base = now.atZone(zone).toLocalDate().atTime(minute / 60, minute % 60).atZone(zone)
            if (!base.toInstant().isAfter(now)) base = base.plusDays(1)
            base.plusDays(index.toLong()).toInstant()
        }
    }

    /** Friendly clock times as minutes after midnight, in the order they are handed out. */
    private val SLOTS = listOf(
        9 * 60, 12 * 60 + 30, 18 * 60, 20 * 60 + 30, 8 * 60, 10 * 60 + 30, 15 * 60,
        19 * 60 + 30, 7 * 60 + 30, 13 * 60 + 30, 17 * 60, 21 * 60, 11 * 60, 16 * 60, 14 * 60,
    )

    /** Reminders for a whole pack, first firing at [fireDates]. */
    fun drafts(
        group: ReminderTemplateGroup,
        coupleId: UUID,
        authorId: UUID,
        targetId: UUID,
        existing: List<ReminderDto> = emptyList(),
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        newId: () -> UUID = UUID::randomUUID,
    ): List<ReminderDto> = fireDates(group.reminders, targetId, existing, now, zone).let { dates ->
        group.reminders.mapIndexed { index, template -> draft(template, dates[index], coupleId, authorId, targetId, newId()) }
    }

    private fun draft(
        template: TemplateReminder,
        fireAt: Instant,
        coupleId: UUID,
        authorId: UUID,
        targetId: UUID,
        id: UUID,
    ): ReminderDto =
        ReminderDto(
            id = id,
            coupleId = coupleId,
            authorId = authorId,
            targetId = targetId,
            title = template.title,
            body = template.body,
            loveLanguage = template.loveLanguage,
            triggerType = if (template.triggerRecurrence != null) "recurring" else "one_time",
            fireAt = fireAt,
            rrule = template.triggerRecurrence?.rrule,
        )
}
