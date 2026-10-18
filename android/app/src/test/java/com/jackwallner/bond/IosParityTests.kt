package com.jackwallner.bond

import com.jackwallner.bond.data.AppClock
import com.jackwallner.bond.data.Codec
import com.jackwallner.bond.data.ConversionDiagnostics
import com.jackwallner.bond.data.InMemoryStore
import com.jackwallner.bond.model.CoupleDto
import com.jackwallner.bond.model.Geofence
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.ProfileDto
import com.jackwallner.bond.model.RecurrencePreset
import com.jackwallner.bond.model.ReminderTarget
import com.jackwallner.bond.model.ReminderTrigger
import com.jackwallner.bond.model.TriggerKind
import com.jackwallner.bond.model.nextOccurrence
import com.jackwallner.bond.ui.components.icon
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// One class per iOS suite in BondTests/, test for test.

class CoupleDtoTests {
    private val partnerA = UUID.randomUUID()
    private val partnerB = UUID.randomUUID()
    private val stranger = UUID.randomUUID()

    @Test fun partnerId_selfIsA_returnsB() =
        assertEquals(partnerB, CoupleDto(UUID.randomUUID(), partnerA, partnerB, null, false).partnerId(partnerA))

    @Test fun partnerId_selfIsB_returnsA() =
        assertEquals(partnerA, CoupleDto(UUID.randomUUID(), partnerA, partnerB, null, false).partnerId(partnerB))

    @Test fun partnerId_stranger_returnsNil() =
        assertNull(CoupleDto(UUID.randomUUID(), partnerA, partnerB, null, false).partnerId(stranger))

    @Test fun partnerId_solo_sameUser() {
        val me = UUID.randomUUID()
        assertEquals(me, CoupleDto(UUID.randomUUID(), me, me, null, true).partnerId(me))
    }

    @Test fun codable_roundTrip() {
        val original = CoupleDto(UUID.randomUUID(), partnerA, partnerB, Instant.now(), false)
        assertEquals(original, Codec.couple(JSONObject(Codec.coupleJson(original).toString())))
    }
}

class LoveLanguageTests {
    @Test fun allCases_count() = assertEquals(5, LoveLanguage.entries.size)

    @Test fun titles_matchExpected() {
        assertEquals("Words of Affirmation", LoveLanguage.WORDS.title)
        assertEquals("Acts of Service", LoveLanguage.ACTS.title)
        assertEquals("Receiving Gifts", LoveLanguage.GIFTS.title)
        assertEquals("Quality Time", LoveLanguage.TIME.title)
        assertEquals("Physical Touch", LoveLanguage.TOUCH.title)
    }

    @Test fun symbolNames_areNonEmpty() {
        for (lang in LoveLanguage.entries) assertTrue(lang.icon.name.isNotEmpty())
    }

    @Test fun allCases_distinctRawValues() {
        val raws = LoveLanguage.entries.map { it.raw }
        assertEquals(raws.size, raws.toSet().size)
    }
}

class MilestoneDtoTests {
    private val coupleId = UUID.randomUUID()

    private fun milestone(date: LocalDate, recur: Boolean, kind: String = "anniversary", label: String? = null) =
        MilestoneDto(UUID.randomUUID(), coupleId, kind, label, date, recur)

    @Test fun nonRecurring_returnsDate() {
        val date = LocalDate.of(2030, 6, 15)
        assertEquals(date, milestone(date, false).nextOccurrence(Instant.now(), LA))
    }

    @Test fun recurring_beforeReference_advancesYear() =
        assertEquals(LocalDate.of(2027, 1, 1), milestone(LocalDate.of(2000, 1, 1), true).nextOccurrence(at(2026, 6, 1), LA))

    @Test fun recurring_afterReference_staysSameYear() =
        assertEquals(LocalDate.of(2026, 12, 25), milestone(LocalDate.of(2000, 12, 25), true).nextOccurrence(at(2026, 6, 1), LA))

    @Test fun recurring_sameDay_referenceIsThatDay() =
        assertEquals(LocalDate.of(2026, 7, 4), milestone(LocalDate.of(2000, 7, 4), true).nextOccurrence(at(2026, 7, 4), LA))

    @Test fun leapYear_Feb29_inNonLeapYear_rollsToMarch1() =
        assertEquals(LocalDate.of(2023, 3, 1), milestone(LocalDate.of(2020, 2, 29), true, "birthday").nextOccurrence(at(2023, 2, 1), LA))

    @Test fun leapYear_Feb29_inLeapYear_staysFeb29() =
        assertEquals(LocalDate.of(2024, 2, 29), milestone(LocalDate.of(2020, 2, 29), true, "birthday").nextOccurrence(at(2024, 1, 1), LA))

    @Test fun leapYear_Feb29_onLeapYearDay_returnsSameDay() =
        assertEquals(LocalDate.of(2024, 2, 29), milestone(LocalDate.of(2020, 2, 29), true, "birthday").nextOccurrence(at(2024, 2, 29), LA))

    @Test fun decode_bareDateString_parsesToLocalMidnight() {
        val json = JSONObject(
            """{"id":"${UUID.randomUUID()}","couple_id":"$coupleId","kind":"anniversary","label":"Us","date":"2026-03-05","recur":true,"created_at":null}""",
        )
        val m = Codec.milestone(json)
        assertEquals(LocalDate.of(2026, 3, 5), m.date)
        assertEquals("Us", m.label)
        assertTrue(m.recur)
    }

    @Test fun encode_emitsBareDateString() =
        assertEquals("2026-03-05", Codec.milestoneJson(milestone(LocalDate.of(2026, 3, 5), true)).getString("date"))

    @Test fun codable_roundTrip_preservesCalendarDay() {
        val m = milestone(LocalDate.of(2024, 2, 29), true, "birthday", "Leap")
        val decoded = Codec.milestone(JSONObject(Codec.milestoneJson(m).toString()))
        assertEquals(m.date, decoded.date)
        assertEquals(m, decoded)
    }

    @Test fun yearBoundary_dec31_advancesCorrectly() =
        assertEquals(LocalDate.of(2026, 12, 31), milestone(LocalDate.of(2000, 12, 31), true, "custom").nextOccurrence(at(2026, 12, 31), LA))
}

class ProfileDtoTests {
    @Test fun codable_roundTrip() {
        val original = ProfileDto(UUID.randomUUID(), "Alice", "https://example.com/avatar.png", "abc123token", createdAt = Instant.now())
        val decoded = Codec.profile(JSONObject(Codec.profileJson(original).toString()))
        assertEquals(original.id, decoded.id)
        assertEquals("Alice", decoded.displayName)
        assertEquals("https://example.com/avatar.png", decoded.avatarUrl)
        assertEquals("abc123token", decoded.apnsToken)
    }

    @Test fun codable_optionalFields_nil() {
        val original = ProfileDto(UUID.randomUUID())
        assertEquals(original, Codec.profile(JSONObject(Codec.profileJson(original).toString())))
    }
}

class RecurrencePresetTests {
    @Test fun daily_rrule() = assertEquals("FREQ=DAILY", RecurrencePreset.DAILY.rrule)
    @Test fun weekly_rrule() = assertEquals("FREQ=WEEKLY", RecurrencePreset.WEEKLY.rrule)
    @Test fun monthly_rrule() = assertEquals("FREQ=MONTHLY", RecurrencePreset.MONTHLY.rrule)
    @Test fun yearly_rrule() = assertEquals("FREQ=YEARLY", RecurrencePreset.YEARLY.rrule)

    @Test fun initFromExactMatch() {
        assertEquals(RecurrencePreset.DAILY, RecurrencePreset.fromRrule("FREQ=DAILY"))
        assertEquals(RecurrencePreset.WEEKLY, RecurrencePreset.fromRrule("FREQ=WEEKLY"))
        assertEquals(RecurrencePreset.MONTHLY, RecurrencePreset.fromRrule("FREQ=MONTHLY"))
        assertEquals(RecurrencePreset.YEARLY, RecurrencePreset.fromRrule("FREQ=YEARLY"))
    }

    @Test fun initFromCaseInsensitive() {
        assertEquals(RecurrencePreset.DAILY, RecurrencePreset.fromRrule("freq=daily"))
        assertEquals(RecurrencePreset.WEEKLY, RecurrencePreset.fromRrule("Freq=Weekly"))
    }

    @Test fun initFromExtendedRRULE() {
        assertEquals(RecurrencePreset.WEEKLY, RecurrencePreset.fromRrule("FREQ=WEEKLY;BYDAY=MO,WE,FR"))
        assertEquals(RecurrencePreset.MONTHLY, RecurrencePreset.fromRrule("FREQ=MONTHLY;BYMONTHDAY=15"))
    }

    @Test fun initFromUnrecognized_returnsNil() {
        assertNull(RecurrencePreset.fromRrule("FREQ=HOURLY"))
        assertNull(RecurrencePreset.fromRrule("BOGUS"))
        assertNull(RecurrencePreset.fromRrule(""))
    }

    @Test fun daily_nextOccurrence() = assertEquals(at(2026, 1, 2), RecurrencePreset.DAILY.nextOccurrence(at(2026, 1, 1), LA))

    @Test fun weekly_nextOccurrence() {
        val date = at(2026, 1, 1)
        assertTrue(RecurrencePreset.WEEKLY.nextOccurrence(date, LA).isAfter(date))
    }

    @Test fun monthly_nextOccurrence() = assertEquals(at(2026, 2, 15), RecurrencePreset.MONTHLY.nextOccurrence(at(2026, 1, 15), LA))

    @Test fun yearly_nextOccurrence_leapYear() =
        assertEquals(at(2025, 2, 28), RecurrencePreset.YEARLY.nextOccurrence(at(2024, 2, 29), LA))
}

class ReminderDtoTests {
    @Test fun trigger_oneTime() {
        val r = reminder("one_time", fireAt = Instant.now())
        assertEquals(ReminderTrigger.OneTime(r.fireAt!!), r.trigger)
    }

    @Test fun trigger_recurring() {
        val r = reminder("recurring", fireAt = Instant.now(), rrule = "FREQ=WEEKLY")
        assertEquals(ReminderTrigger.Recurring("FREQ=WEEKLY", r.fireAt!!), r.trigger)
    }

    @Test fun trigger_location() {
        val g = Geofence(0.0, 0.0, 200.0, "Home")
        assertEquals(ReminderTrigger.Location(g, true), reminder("location", geofence = g).trigger)
    }

    @Test fun trigger_randomWindow() {
        val s = Instant.now()
        val e = s.plusSeconds(3600)
        assertEquals(ReminderTrigger.RandomWindow(s, e), reminder("random_window", windowStart = s, windowEnd = e).trigger)
    }

    @Test fun trigger_unknownType_returnsNil() = assertNull(reminder("unknown").trigger)

    @Test fun trigger_missingFields_returnsNil() = assertNull(reminder("one_time", fireAt = null).trigger)

    @Test fun codable_roundTrip() {
        val r = reminder("recurring", fireAt = Instant.now(), rrule = "FREQ=DAILY")
        val decoded = Codec.reminder(JSONObject(Codec.reminderJson(r).toString()))
        assertEquals(r, decoded)
        assertEquals("recurring", decoded.trigger?.kindRaw)
    }
}

class ReminderTriggerTests {
    private val home = Geofence(0.0, 0.0, 200.0, "Home")

    @Test fun kindRaw_oneTime() = assertEquals("one_time", ReminderTrigger.OneTime(Instant.now()).kindRaw)
    @Test fun kindRaw_recurring() = assertEquals("recurring", ReminderTrigger.Recurring("FREQ=DAILY", Instant.now()).kindRaw)
    @Test fun kindRaw_location() = assertEquals("location", ReminderTrigger.Location(home, true).kindRaw)
    @Test fun kindRaw_randomWindow() =
        assertEquals("random_window", ReminderTrigger.RandomWindow(Instant.now(), Instant.now().plusSeconds(3600)).kindRaw)

    @Test fun nextFireDate_oneTime() = assertEquals(at(2026, 7, 4, 12), ReminderTrigger.OneTime(at(2026, 7, 4, 12)).nextFireDate)
    @Test fun nextFireDate_recurring() =
        assertEquals(at(2026, 7, 4, 12), ReminderTrigger.Recurring("FREQ=WEEKLY", at(2026, 7, 4, 12)).nextFireDate)
    @Test fun nextFireDate_location() = assertNull(ReminderTrigger.Location(home, true).nextFireDate)
    @Test fun nextFireDate_randomWindow() =
        assertEquals(at(2026, 7, 4, 17), ReminderTrigger.RandomWindow(at(2026, 7, 4, 9), at(2026, 7, 4, 17)).nextFireDate)

    @Test fun upcomingFireDate_oneTime_returnsFireAt() =
        assertEquals(at(2030, 1, 1, 9), ReminderTrigger.OneTime(at(2030, 1, 1, 9)).upcomingFireDate(Instant.now(), LA))

    @Test fun upcomingFireDate_recurring_pastAnchor_advancesToFuture() {
        val reference = at(2026, 5, 16, 12)
        val next = ReminderTrigger.Recurring("FREQ=DAILY", at(2020, 1, 1, 9)).upcomingFireDate(reference, LA)
        assertNotNull(next)
        assertTrue(next!!.isAfter(reference))
    }

    @Test fun upcomingFireDate_recurring_futureAnchor_staysPut() =
        assertEquals(at(2030, 6, 1, 9), ReminderTrigger.Recurring("FREQ=WEEKLY", at(2030, 6, 1, 9)).upcomingFireDate(at(2026, 5, 16), LA))

    @Test fun upcomingFireDate_location_returnsNil() = assertNull(ReminderTrigger.Location(home, true).upcomingFireDate(Instant.now(), LA))

    @Test fun upcomingFireDate_randomWindow_returnsEnd() =
        assertEquals(at(2026, 7, 4, 17), ReminderTrigger.RandomWindow(at(2026, 7, 4, 9), at(2026, 7, 4, 17)).upcomingFireDate(Instant.now(), LA))

    // iOS encodes the trigger enum itself; Android stores it as the reminder's
    // columns, so the round trip goes through the row codec.

    @Test fun codable_oneTime() {
        val decoded = roundTrip(reminder("one_time", fireAt = at(2026, 12, 25, 8)))
        assertEquals(ReminderTrigger.OneTime(at(2026, 12, 25, 8)), decoded)
        assertEquals("one_time", decoded?.kindRaw)
    }

    @Test fun codable_recurring() =
        assertEquals(ReminderTrigger.Recurring("FREQ=MONTHLY", at(2026, 1, 1)), roundTrip(reminder("recurring", at(2026, 1, 1), "FREQ=MONTHLY")))

    @Test fun codable_location() {
        val g = Geofence(37.7749, -122.4194, 200.0, "Home")
        assertEquals(ReminderTrigger.Location(g, true), roundTrip(reminder("location", geofence = g)))
    }

    @Test fun codable_randomWindow() =
        assertEquals(
            ReminderTrigger.RandomWindow(at(2026, 7, 4, 9), at(2026, 7, 4, 17)),
            roundTrip(reminder("random_window", windowStart = at(2026, 7, 4, 9), windowEnd = at(2026, 7, 4, 17))),
        )

    private fun roundTrip(r: com.jackwallner.bond.model.ReminderDto) = Codec.reminder(JSONObject(Codec.reminderJson(r).toString())).trigger
}

class GeofenceTests {
    @Test fun codable_roundTrip() {
        val decoded = Codec.geofence(JSONObject(Codec.geofenceJson(Geofence(37.7749, -122.4194, 200.0, "Home")).toString()))
        assertEquals(37.7749, decoded.latitude, 0.0)
        assertEquals(-122.4194, decoded.longitude, 0.0)
        assertEquals(200.0, decoded.radiusMeters, 0.0)
        assertEquals("Home", decoded.label)
    }
}

class ReminderTargetTests {
    @Test fun titles() {
        assertEquals("Me", ReminderTarget.ME.title)
        assertEquals("Partner", ReminderTarget.PARTNER.title)
    }

    @Test fun allCases() = assertEquals(2, ReminderTarget.entries.size)
}

class TriggerKindTests {
    @Test fun titles() {
        assertEquals("One time", TriggerKind.ONE_TIME.title)
        assertEquals("Recurring", TriggerKind.RECURRING.title)
        assertEquals("At a place", TriggerKind.LOCATION.title)
        assertEquals("Random surprise", TriggerKind.RANDOM_WINDOW.title)
    }

    @Test fun isPremium() {
        assertFalse(TriggerKind.ONE_TIME.isPremium)
        assertFalse(TriggerKind.RECURRING.isPremium)
        assertTrue(TriggerKind.LOCATION.isPremium)
        assertTrue(TriggerKind.RANDOM_WINDOW.isPremium)
    }

    @Test fun allCases() = assertEquals(4, TriggerKind.entries.size)
}

class PaywallFunnelTests {
    private val clock = AppClock(Clock.fixed(Instant.parse("2026-10-18T17:00:00Z"), LA))
    private val diagnostics = ConversionDiagnostics(InMemoryStore(), clock)

    @Test fun countsPitchesPerSurfaceAndInTotal() {
        diagnostics.recordPitchView("bond_post_onboarding")
        diagnostics.recordPitchView("bond_post_onboarding")
        diagnostics.recordPitchView("bond_feature_gate")
        val a = diagnostics.subscriberAttributes
        assertEquals("3", a["pitch_views_total"])
        assertEquals("2", a["pitch_views_post_onboarding"])
        assertEquals("feature_gate", a["pitch_last"])
    }

    @Test fun noAttributesBeforeAnyPitchIsSeen() {
        diagnostics.recordAppOpen()
        assertTrue(diagnostics.subscriberAttributes.isEmpty())
    }

    @Test fun recordsHowEarlyTheFirstPitchArrived() {
        diagnostics.recordAppOpen()
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("bond_post_onboarding")
        val a = diagnostics.subscriberAttributes
        assertEquals("2", a["opens_before_first_pitch"])
        assertEquals("0", a["days_since_install"])
    }

    @Test fun theEarlinessPairIsFrozenOnTheFirstPitchOnly() {
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("bond_post_onboarding")
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("bond_feature_gate")
        assertEquals("1", diagnostics.subscriberAttributes["opens_before_first_pitch"])
    }

    @Test fun anInstallThatPredatesThisCodeReportsNoAge() {
        diagnostics.recordPitchView("bond_post_onboarding")
        val a = diagnostics.subscriberAttributes
        assertNull(a["days_since_install"])
        assertEquals("1", a["pitch_views_total"])
    }

    @Test fun conversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        diagnostics.recordPitchView("bond_post_onboarding")
        diagnostics.recordPitchView("bond_feature_gate")
        diagnostics.recordConversion("yearly", startedTrial = true, offeringId = "default")
        diagnostics.recordPitchView("bond_post_onboarding")
        val a = diagnostics.subscriberAttributes
        assertEquals("feature_gate", a["converted_surface"])
        assertEquals("2", a["pitch_views_at_convert"])
        assertEquals("true", a["converted_with_trial"])
        assertEquals("default", a["converted_offering"])
    }

    @Test fun onlyTheFirstConversionIsRecorded() {
        diagnostics.recordPitchView("bond_post_onboarding")
        diagnostics.recordConversion("monthly", startedTrial = true)
        diagnostics.recordConversion("yearly", startedTrial = false)
        val a = diagnostics.subscriberAttributes
        assertEquals("monthly", a["converted_plan"])
        assertEquals("true", a["converted_with_trial"])
    }

    @Test fun attributeKeysStayInsideRevenueCatsLimit() {
        diagnostics.recordPitchView("bond_" + "a".repeat(80))
        for (key in diagnostics.subscriberAttributes.keys) assertTrue("attribute key too long: $key", key.length <= 40)
    }

    @Test fun noAttributeCarriesFreeTextOrHealthData() {
        diagnostics.recordAppOpen()
        diagnostics.recordPitchView("bond_post_onboarding")
        diagnostics.recordConversion("monthly", startedTrial = false)
        for ((key, value) in diagnostics.subscriberAttributes) {
            assertFalse("$key looks like free text: $value", value.contains(" "))
            assertTrue("$key is too long to be a label", value.length <= 64)
        }
    }
}
