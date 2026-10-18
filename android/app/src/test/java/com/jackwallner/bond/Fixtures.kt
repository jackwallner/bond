package com.jackwallner.bond

import com.jackwallner.bond.model.Geofence
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/** Every fixture runs in one fixed zone, like the iOS tests on a Pacific simulator. */
val LA: ZoneId = ZoneId.of("America/Los_Angeles")

fun at(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Instant =
    LocalDateTime.of(year, month, day, hour, minute).atZone(LA).toInstant()

fun reminder(
    triggerType: String,
    fireAt: Instant? = null,
    rrule: String? = null,
    geofence: Geofence? = null,
    windowStart: Instant? = null,
    windowEnd: Instant? = null,
    language: LoveLanguage = LoveLanguage.WORDS,
    authorId: UUID = UUID.randomUUID(),
    targetId: UUID = authorId,
    createdAt: Instant? = null,
    title: String = "Test reminder",
    id: UUID = UUID.randomUUID(),
): ReminderDto = ReminderDto(
    id = id,
    coupleId = UUID(0, 1),
    authorId = authorId,
    targetId = targetId,
    title = title,
    body = null,
    loveLanguage = language,
    triggerType = triggerType,
    fireAt = fireAt,
    rrule = rrule,
    geofence = geofence,
    windowStart = windowStart,
    windowEnd = windowEnd,
    createdAt = createdAt,
)

fun acted(reminder: ReminderDto, at: Instant): ReminderEventDto =
    ReminderEventDto(UUID.randomUUID(), reminder.id, reminder.coupleId, at, at)
