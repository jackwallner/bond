package com.jackwallner.bond.data

import com.jackwallner.bond.model.CoupleDto
import com.jackwallner.bond.model.DailyQuestionDto
import com.jackwallner.bond.model.Geofence
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.ProfileDto
import com.jackwallner.bond.model.QuestionResponseDto
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * Row coding for the Supabase tables, with the column names the iOS DTOs use
 * (`CodingKeys`). Timestamps go out as ISO-8601 instants; the milestone `date`
 * column is a bare `yyyy-MM-dd` calendar day.
 */
object Codec {
    fun parseInstant(raw: String): Instant =
        runCatching { OffsetDateTime.parse(raw, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant() }
            .getOrElse { Instant.parse(raw) }

    private fun JSONObject.str(key: String): String? =
        if (!has(key) || isNull(key)) null else getString(key)

    private fun JSONObject.uuid(key: String): UUID = UUID.fromString(getString(key))
    private fun JSONObject.instant(key: String): Instant? = str(key)?.let(::parseInstant)

    private fun JSONObject.putNullable(key: String, value: Any?): JSONObject =
        put(key, value ?: JSONObject.NULL)

    fun objects(array: JSONArray): List<JSONObject> = (0 until array.length()).map { array.getJSONObject(it) }

    // Couples

    fun couple(o: JSONObject) = CoupleDto(
        id = o.uuid("id"),
        partnerA = o.uuid("partner_a"),
        partnerB = o.uuid("partner_b"),
        pairedAt = o.instant("paired_at"),
        solo = o.optBoolean("solo", false),
    )

    fun coupleJson(c: CoupleDto): JSONObject = JSONObject()
        .put("id", c.id.toString())
        .put("partner_a", c.partnerA.toString())
        .put("partner_b", c.partnerB.toString())
        .putNullable("paired_at", c.pairedAt?.toString())
        .put("solo", c.solo)

    // Profiles

    fun profile(o: JSONObject) = ProfileDto(
        id = o.uuid("id"),
        displayName = o.str("display_name"),
        avatarUrl = o.str("avatar_url"),
        apnsToken = o.str("apns_token"),
        loveLanguage = o.str("love_language"),
        createdAt = o.instant("created_at"),
    )

    fun profileJson(p: ProfileDto): JSONObject = JSONObject()
        .put("id", p.id.toString())
        .putNullable("display_name", p.displayName)
        .putNullable("avatar_url", p.avatarUrl)
        .putNullable("apns_token", p.apnsToken)
        .putNullable("love_language", p.loveLanguage)
        .putNullable("created_at", p.createdAt?.toString())

    // Reminders

    fun geofence(o: JSONObject) = Geofence(
        latitude = o.getDouble("latitude"),
        longitude = o.getDouble("longitude"),
        radiusMeters = o.getDouble("radiusMeters"),
        label = o.optString("label", ""),
    )

    fun geofenceJson(g: Geofence): JSONObject = JSONObject()
        .put("latitude", g.latitude)
        .put("longitude", g.longitude)
        .put("radiusMeters", g.radiusMeters)
        .put("label", g.label)

    fun reminder(o: JSONObject) = ReminderDto(
        id = o.uuid("id"),
        coupleId = o.uuid("couple_id"),
        authorId = o.uuid("author_id"),
        targetId = o.uuid("target_id"),
        title = o.getString("title"),
        body = o.str("body"),
        loveLanguage = LoveLanguage.fromRaw(o.str("love_language")) ?: LoveLanguage.WORDS,
        triggerType = o.getString("trigger_type"),
        fireAt = o.instant("fire_at"),
        rrule = o.str("rrule"),
        geofence = if (o.has("geofence") && !o.isNull("geofence")) geofence(o.getJSONObject("geofence")) else null,
        windowStart = o.instant("window_start"),
        windowEnd = o.instant("window_end"),
        status = o.str("status") ?: "scheduled",
        surpriseHiddenFromPartner = o.optBoolean("surprise_hidden_from_partner", false),
        createdAt = o.instant("created_at"),
    )

    /**
     * Cleared optional fields go out as explicit nulls so an upsert that turns a
     * recurring reminder into a one-time one actually clears `rrule`.
     * `created_at` is left to the database default when unknown.
     */
    fun reminderJson(r: ReminderDto): JSONObject = JSONObject()
        .put("id", r.id.toString())
        .put("couple_id", r.coupleId.toString())
        .put("author_id", r.authorId.toString())
        .put("target_id", r.targetId.toString())
        .put("title", r.title)
        .putNullable("body", r.body)
        .put("love_language", r.loveLanguage.raw)
        .put("trigger_type", r.triggerType)
        .putNullable("fire_at", r.fireAt?.toString())
        .putNullable("rrule", r.rrule)
        .putNullable("geofence", r.geofence?.let(::geofenceJson))
        .putNullable("window_start", r.windowStart?.toString())
        .putNullable("window_end", r.windowEnd?.toString())
        .put("status", r.status)
        .put("surprise_hidden_from_partner", r.surpriseHiddenFromPartner)
        .also { json -> r.createdAt?.let { json.put("created_at", it.toString()) } }

    // Events

    fun event(o: JSONObject) = ReminderEventDto(
        id = o.uuid("id"),
        reminderId = o.uuid("reminder_id"),
        coupleId = o.uuid("couple_id"),
        firedAt = o.instant("fired_at") ?: Instant.EPOCH,
        actedAt = o.instant("acted_at"),
        reaction = o.str("reaction"),
    )

    fun eventJson(e: ReminderEventDto): JSONObject = JSONObject()
        .put("id", e.id.toString())
        .put("reminder_id", e.reminderId.toString())
        .put("couple_id", e.coupleId.toString())
        .put("fired_at", e.firedAt.toString())
        .putNullable("acted_at", e.actedAt?.toString())
        .putNullable("reaction", e.reaction)

    // Milestones

    fun milestone(o: JSONObject): MilestoneDto {
        val raw = o.getString("date")
        val parts = raw.take(10).split("-").mapNotNull { it.toIntOrNull() }
        require(parts.size == 3) { "Invalid date: $raw" }
        return MilestoneDto(
            id = o.uuid("id"),
            coupleId = o.uuid("couple_id"),
            kind = o.getString("kind"),
            label = o.str("label"),
            date = LocalDate.of(parts[0], parts[1], parts[2]),
            recur = o.optBoolean("recur", false),
            createdAt = o.instant("created_at"),
        )
    }

    fun milestoneJson(m: MilestoneDto): JSONObject = JSONObject()
        .put("id", m.id.toString())
        .put("couple_id", m.coupleId.toString())
        .put("kind", m.kind)
        .putNullable("label", m.label)
        .put("date", "%04d-%02d-%02d".format(m.date.year, m.date.monthValue, m.date.dayOfMonth))
        .put("recur", m.recur)
        .also { json -> m.createdAt?.let { json.put("created_at", it.toString()) } }

    // Check-in

    fun question(o: JSONObject) = DailyQuestionDto(
        id = o.uuid("id"),
        question = o.getString("question"),
        category = o.optString("category", ""),
        loveLanguage = LoveLanguage.fromRaw(o.str("love_language")),
    )

    fun response(o: JSONObject) = QuestionResponseDto(
        id = o.uuid("id"),
        questionId = o.uuid("question_id"),
        coupleId = o.uuid("couple_id"),
        userId = o.uuid("user_id"),
        response = o.getString("response"),
        createdAt = o.instant("created_at") ?: Instant.EPOCH,
    )

    fun responseJson(r: QuestionResponseDto): JSONObject = JSONObject()
        .put("id", r.id.toString())
        .put("question_id", r.questionId.toString())
        .put("couple_id", r.coupleId.toString())
        .put("user_id", r.userId.toString())
        .put("response", r.response)
        .put("created_at", r.createdAt.toString())
}
