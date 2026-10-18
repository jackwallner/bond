package com.jackwallner.bond.model

import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/** The five love languages, with the same raw values the `reminders` table checks. */
enum class LoveLanguage(val raw: String, val title: String) {
    WORDS("words", "Words of Affirmation"),
    ACTS("acts", "Acts of Service"),
    GIFTS("gifts", "Receiving Gifts"),
    TIME("time", "Quality Time"),
    TOUCH("touch", "Physical Touch");

    companion object {
        fun fromRaw(raw: String?): LoveLanguage? = entries.firstOrNull { it.raw == raw }
    }
}

/** Who a reminder is for, from the editor's point of view. */
enum class ReminderTarget(val raw: String, val title: String) {
    ME("me", "Me"),
    PARTNER("partner", "Partner"),
}

/** The editor's schedule choices. Location and random windows are Little Gestures+. */
enum class TriggerKind(val title: String, val subtitle: String, val isPremium: Boolean) {
    ONE_TIME("One time", "Fires once at a chosen moment.", false),
    RECURRING("Recurring", "Daily, weekly, monthly. Your call.", false),
    LOCATION("At a place", "Triggers when you arrive somewhere.", true),
    RANDOM_WINDOW("Random surprise", "A random moment: once, or at a random time every day.", true);

    /**
     * Geofenced reminders need Android background location, which this port
     * does not request (see `.claude/rules/android.md`). The editor never offers
     * the kind for a new reminder; an existing one created on iPhone keeps it.
     */
    val availableOnAndroid: Boolean get() = this != LOCATION
}

data class Geofence(
    val latitude: Double,
    val longitude: Double,
    val radiusMeters: Double,
    val label: String,
)

data class CoupleDto(
    val id: UUID,
    val partnerA: UUID,
    val partnerB: UUID,
    val pairedAt: Instant?,
    val solo: Boolean,
) {
    fun partnerId(forSelf: UUID): UUID? = when (forSelf) {
        partnerA -> partnerB
        partnerB -> partnerA
        else -> null
    }
}

data class ProfileDto(
    val id: UUID,
    val displayName: String? = null,
    val avatarUrl: String? = null,
    val apnsToken: String? = null,
    val loveLanguage: String? = null,
    val createdAt: Instant? = null,
)

data class ReminderEventDto(
    val id: UUID,
    val reminderId: UUID,
    val coupleId: UUID,
    val firedAt: Instant,
    val actedAt: Instant? = null,
    val reaction: String? = null,
)

data class DailyQuestionDto(
    val id: UUID,
    val question: String,
    val category: String,
    val loveLanguage: LoveLanguage?,
)

data class QuestionResponseDto(
    val id: UUID,
    val questionId: UUID,
    val coupleId: UUID,
    val userId: UUID,
    val response: String,
    val createdAt: Instant,
)

/** A row of `public.reminders`. Field names follow the table, not iOS's Swift casing. */
data class ReminderDto(
    val id: UUID,
    val coupleId: UUID,
    val authorId: UUID,
    val targetId: UUID,
    val title: String,
    val body: String? = null,
    val loveLanguage: LoveLanguage,
    val triggerType: String,
    val fireAt: Instant? = null,
    val rrule: String? = null,
    val geofence: Geofence? = null,
    val windowStart: Instant? = null,
    val windowEnd: Instant? = null,
    val status: String = "scheduled",
    val surpriseHiddenFromPartner: Boolean = false,
    val createdAt: Instant? = null,
) {
    /** `ReminderDTO.trigger` on iOS: nil when the row's columns don't make a whole trigger. */
    val trigger: ReminderTrigger?
        get() = when (triggerType) {
            "one_time" -> fireAt?.let { ReminderTrigger.OneTime(it) }
            "recurring" -> if (rrule != null && fireAt != null) ReminderTrigger.Recurring(rrule, fireAt) else null
            "location" -> geofence?.let { ReminderTrigger.Location(it, onEntry = true) }
            "random_window" -> if (windowStart != null && windowEnd != null) {
                // A repeating rule turns the absolute window into a daily window.
                if (rrule != null) ReminderTrigger.RandomRecurring(windowStart, windowEnd)
                else ReminderTrigger.RandomWindow(windowStart, windowEnd)
            } else {
                null
            }
            else -> null
        }
}

/** A row of `public.milestones`. `date` is a Postgres `date`, a calendar day with no zone. */
data class MilestoneDto(
    val id: UUID,
    val coupleId: UUID,
    val kind: String,
    val label: String? = null,
    val date: LocalDate,
    val recur: Boolean,
    val createdAt: Instant? = null,
)

/** The iOS `String.capitalized` for the one-word kinds and labels this app shows. */
fun String.capitalizedWords(): String =
    split(" ").joinToString(" ") { word -> word.lowercase().replaceFirstChar { it.titlecase() } }
