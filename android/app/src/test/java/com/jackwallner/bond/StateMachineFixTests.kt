package com.jackwallner.bond

import com.jackwallner.bond.data.AlarmNotificationScheduler
import com.jackwallner.bond.data.AlarmPlatform
import com.jackwallner.bond.data.AuthService
import com.jackwallner.bond.data.Codec
import com.jackwallner.bond.data.DailyCheckInService
import com.jackwallner.bond.data.HttpResponse
import com.jackwallner.bond.data.HttpTransport
import com.jackwallner.bond.data.InMemoryStore
import com.jackwallner.bond.data.Membership
import com.jackwallner.bond.data.OnboardingPreferences
import com.jackwallner.bond.data.PairingService
import com.jackwallner.bond.data.ReminderEventRepository
import com.jackwallner.bond.data.ReminderRepository
import com.jackwallner.bond.data.ReminderScheduling
import com.jackwallner.bond.data.SeedMode
import com.jackwallner.bond.data.SupabaseClient
import com.jackwallner.bond.data.rebuildSchedule
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.LoveLanguageAnalyzer
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.NotificationPlanner
import com.jackwallner.bond.model.NotificationSpec
import com.jackwallner.bond.model.QuestionResponseDto
import com.jackwallner.bond.model.RecurrencePreset
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import com.jackwallner.bond.model.ReminderTemplateStore
import com.jackwallner.bond.model.ReminderTrigger
import com.jackwallner.bond.model.isCompleted
import com.jackwallner.bond.model.visibleTo
import com.jackwallner.bond.ui.screens.reminderToOpen
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// State machine audit 2026-11-06, reviewed by project-docs/audits/state-machines-2026-11-06-review.md.
// Each class is the Android side of the iOS fix for the bug ids it names.

private val NEW_YORK: ZoneId = ZoneId.of("America/New_York")
private val TOKYO: ZoneId = ZoneId.of("Asia/Tokyo")

private fun inZone(zone: ZoneId, year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Instant =
    LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant()

/** A Supabase client over a recording fake transport, signed in as a stored session. */
private class Backend {
    data class Call(val method: String, val url: String, val body: String?)

    val calls = mutableListOf<Call>()
    var route: (Call) -> HttpResponse = { HttpResponse(200, "[]") }
    val store = InMemoryStore().also {
        it.putString(
            "supabase.session",
            JSONObject().put("access_token", "t").put("refresh_token", "r").put("expires_at", 2_000_000L)
                .put("user_id", UUID(0, 9).toString()).put("is_anonymous", true).toString(),
        )
    }
    val client = SupabaseClient("https://x.supabase.co", "anon", store, HttpTransport { method, url, _, body ->
        val call = Call(method, url, body)
        calls += call
        route(call)
    }) { 1_000_000L }

    val me: UUID = UUID.randomUUID()
    val partner: UUID = UUID.randomUUID()
    val coupleId = UUID(0, 1)
    val seed = SeedMode()
    val auth = AuthService(client).also { it.adoptForSeed(me) }
    val prefs = OnboardingPreferences(InMemoryStore())
    val pairing = PairingService(client, auth, prefs, seed)

    fun table(call: Call, name: String) = "/rest/v1/$name?" in call.url || call.url.endsWith("/rest/v1/$name")

    companion object {
        fun ok(body: String = "[]") = HttpResponse(200, body)
        fun down() = HttpResponse(500, "{\"message\":\"down\"}")
        fun rows(vararg rows: JSONObject) = ok(JSONArray(rows.toList()).toString())
    }
}

class DailyQuestionRuleTests {
    private val me = UUID.randomUUID()
    private val partner = UUID.randomUUID()
    private val couple = UUID.randomUUID()

    private fun answer(question: UUID, by: UUID, time: Instant) =
        QuestionResponseDto(UUID.randomUUID(), question, couple, by, "x", time)

    private fun current(day: UUID, answers: List<QuestionResponseDto>, who: UUID, now: Instant, zone: ZoneId) =
        DailyCheckInService.currentQuestionId(day, answers, who, now, zone)

    @Test fun n1_theQuestionDoesNotChangeAtMidnightUtc() {
        // 4 PM in Los Angeles is midnight UTC.
        val before = DailyCheckInService.dayNumber(inZone(LA, 2026, 11, 6, 15), LA)
        val after = DailyCheckInService.dayNumber(inZone(LA, 2026, 11, 6, 17), LA)
        val nextMorning = DailyCheckInService.dayNumber(inZone(LA, 2026, 11, 7, 0, 30), LA)
        assertEquals(before, after)
        assertEquals(before + 1, nextMorning)
    }

    @Test fun n1_whileTheDatesMatchTheDayIsTheOneTheStoreVersionUses() {
        val morning = inZone(LA, 2026, 11, 6, 10)
        assertEquals(
            DailyCheckInService.dayNumber(morning, LA),
            DailyCheckInService.dayNumber(morning, ZoneId.of("UTC")),
        )
        // The numbering is Foundation's era ordinal of the date, as iOS counts it.
        assertEquals(739_926L, DailyCheckInService.dayNumber(morning, LA))
    }

    @Test fun n1_theIndexIsTheSameAsIosForTheSameDateAndCouple() {
        val couple = UUID.fromString("33333333-3333-4333-8333-333333333333")
        val day = DailyCheckInService.dayNumber(inZone(LA, 2026, 11, 6, 10), LA)
        assertEquals(
            DailyCheckInService.questionIndex(day, DailyCheckInService.stableSeed(couple), 30),
            DailyCheckInService.questionIndex(java.time.LocalDate.of(2026, 11, 6), couple, 30),
        )
    }

    @Test fun n1_answersEitherSideOfMidnightStayOnOneQuestionAndBothSeeTheReveal() {
        val yesterdays = UUID.randomUUID()
        val todays = UUID.randomUUID()
        val answers = mutableListOf(answer(yesterdays, partner, inZone(LA, 2026, 11, 6, 23, 50)))

        val tenPast = inZone(LA, 2026, 11, 7, 0, 10)
        assertEquals(yesterdays, current(todays, answers, me, tenPast, LA))
        assertEquals(yesterdays, current(todays, answers, partner, tenPast, LA))

        answers += answer(yesterdays, me, tenPast)
        val later = inZone(LA, 2026, 11, 7, 8)
        assertEquals(yesterdays, current(todays, answers, me, later, LA))
        assertEquals(yesterdays, current(todays, answers, partner, later, LA))

        val tomorrows = UUID.randomUUID()
        assertEquals(tomorrows, current(tomorrows, answers, me, inZone(LA, 2026, 11, 8, 9), LA))
    }

    @Test fun n1_partnersInDifferentZonesAnswerTheSameQuestion() {
        val tokyoQuestion = UUID.randomUUID()
        val newYorkQuestion = UUID.randomUUID()
        // 10 AM on the 7th in Tokyo is 8 PM on the 6th in New York.
        val tokyoMorning = inZone(TOKYO, 2026, 11, 7, 10)
        val answers = mutableListOf(answer(tokyoQuestion, partner, tokyoMorning))
        val soon = tokyoMorning.plusSeconds(1_800)
        assertEquals(tokyoQuestion, current(newYorkQuestion, answers, me, soon, NEW_YORK))

        answers += answer(tokyoQuestion, me, soon)
        val after = soon.plusSeconds(600)
        assertEquals(tokyoQuestion, current(newYorkQuestion, answers, me, after, NEW_YORK))
        assertEquals(tokyoQuestion, current(tokyoQuestion, answers, partner, after, TOKYO))
    }

    @Test fun n1_aPartnerOnTheStoreVersionStillGetsAnAnswerToTheirQuestion() {
        val storeQuestion = UUID.randomUUID()
        val answers = listOf(answer(storeQuestion, partner, inZone(LA, 2026, 11, 6, 16, 30)))
        assertEquals(storeQuestion, current(UUID.randomUUID(), answers, me, inZone(LA, 2026, 11, 6, 19), LA))
    }

    @Test fun n1_priorityIsWaitingOnMeThenRevealedTodayThenWaitingOnPartner() {
        val now = inZone(LA, 2026, 11, 7, 12)
        val waitingOnMe = UUID.randomUUID()
        val revealed = UUID.randomUUID()
        val waitingOnPartner = UUID.randomUUID()
        val answers = listOf(
            answer(waitingOnPartner, me, now.minusSeconds(3_600)),
            answer(revealed, me, now.minusSeconds(7_200)), answer(revealed, partner, now.minusSeconds(5_400)),
            answer(waitingOnMe, partner, now.minusSeconds(10_800)),
        )
        val day = UUID.randomUUID()
        assertEquals(waitingOnMe, current(day, answers, me, now, LA))
        assertEquals(revealed, current(day, answers.filter { it.questionId != waitingOnMe }, me, now, LA))
        assertEquals(waitingOnPartner, current(day, answers.filter { it.questionId == waitingOnPartner }, me, now, LA))
    }

    @Test fun n1_control_aQuestionNobodyAnsweredIsTheDaysQuestion_andAnUnansweredOneExpiresAfterADay() {
        val day = UUID.randomUUID()
        val now = inZone(LA, 2026, 11, 7, 12)
        assertEquals(day, current(day, emptyList(), me, now, LA))
        val old = listOf(answer(UUID.randomUUID(), partner, now.minusSeconds(25 * 3_600)))
        assertEquals(day, current(day, old, me, now, LA))
    }

    private fun questionJson(id: UUID, text: String) =
        JSONObject().put("id", id.toString()).put("question", text).put("category", "c").put("love_language", "words")

    @Test fun n1_loadingFollowsThePartnersOpenQuestionAndReadsTwoDaysOfResponses() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val dayQuestion = UUID.randomUUID()
        val partnersQuestion = UUID.randomUUID()
        val now = inZone(LA, 2026, 11, 7, 0, 10)
        val partnerAnswer = JSONObject().put("id", UUID.randomUUID().toString()).put("question_id", partnersQuestion.toString())
            .put("couple_id", b.coupleId.toString()).put("user_id", b.partner.toString()).put("response", "hi")
            .put("created_at", inZone(LA, 2026, 11, 6, 23, 50).toString())
        b.route = { call ->
            when {
                call.method == "HEAD" -> HttpResponse(200, "", mapOf("content-range" to "0-0/30"))
                "/daily_questions?select=*&id=eq.$partnersQuestion" in call.url -> Backend.rows(questionJson(partnersQuestion, "theirs"))
                b.table(call, "daily_questions") -> Backend.rows(questionJson(dayQuestion, "today"))
                b.table(call, "question_responses") -> Backend.rows(partnerAnswer)
                else -> Backend.ok()
            }
        }
        val service = DailyCheckInService(b.client, b.auth, b.pairing, b.seed)
        service.loadTodaysQuestion(now, LA)

        assertEquals(partnersQuestion, service.todaysQuestion?.id)
        assertNull(service.myResponse)
        assertNotNull(service.partnerResponse)
        val since = SupabaseClient.encode(now.minusSeconds(48 * 3_600).toString())
        val read = b.calls.single { "/question_responses?" in it.url }
        assertTrue(read.url, "created_at=gte.$since" in read.url)
        assertFalse("question_id=" in read.url)
    }

    @Test fun n1_theResponseUpsertStampsCreatedAtWithNow() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val question = UUID.randomUUID()
        val now = inZone(LA, 2026, 11, 7, 9)
        b.route = { call ->
            when {
                call.method == "HEAD" -> HttpResponse(200, "", mapOf("content-range" to "0-0/30"))
                b.table(call, "daily_questions") -> Backend.rows(questionJson(question, "today"))
                else -> Backend.ok()
            }
        }
        val service = DailyCheckInService(b.client, b.auth, b.pairing, b.seed)
        service.loadTodaysQuestion(now, LA)
        service.submitResponse("my answer", now)

        val post = b.calls.single { it.method == "POST" && "/question_responses" in it.url }
        assertTrue(post.url, "on_conflict=question_id%2Ccouple_id%2Cuser_id" in post.url)
        val body = JSONObject(post.body!!)
        assertEquals(now.toString(), body.getString("created_at"))
        assertEquals("my answer", body.getString("response"))
    }
}

class VisibleInsightsTests {
    private val me = UUID.randomUUID()
    private val partner = UUID.randomUUID()
    private val now = at(2026, 11, 6, 12)

    private fun recurring(title: String, author: UUID, target: UUID, fireAt: Instant) = reminder(
        "recurring", fireAt = fireAt, rrule = "FREQ=DAILY", authorId = author, targetId = target,
        createdAt = now.minusSeconds(10 * 86_400), title = title,
    )

    @Test fun b4_insightsOnlyCountAndNameWhatTheUserCanSee() {
        val mine = recurring("Mine", me, me, now.plusSeconds(5 * 86_400))
        val forMe = recurring("For me", partner, me, now.plusSeconds(4 * 86_400))
        val theirs = recurring("Partner private", partner, partner, now.plusSeconds(86_400))
        val analyzer = LoveLanguageAnalyzer.visibleTo(
            me, listOf(mine, forMe, theirs), listOf(acted(mine, now), acted(theirs, now)), LA, Locale.US,
        )
        assertEquals(2, analyzer.reminderCounts().sumOf { it.second })
        assertEquals(2, analyzer.reminderCount)
        assertEquals(setOf("Mine", "For me"), analyzer.followThrough(now = now).map { it.reminder.title }.toSet())
        assertEquals(1, analyzer.eventCount)
        assertEquals(1, analyzer.actedEventCount)
        assertEquals(1, analyzer.partnerReminderCount)
    }

    @Test fun b4_signedOutSeesNothing() {
        val mine = recurring("Mine", me, me, now.plusSeconds(86_400))
        assertEquals(0, LoveLanguageAnalyzer.visibleTo(null, listOf(mine), emptyList(), LA, Locale.US).reminderCount)
        assertTrue(listOf(mine).visibleTo(null).isEmpty())
    }

    @Test fun b4_theListAndInsightsShareOneRule() {
        val mine = recurring("Mine", me, me, now)
        val forMe = recurring("For me", partner, me, now)
        val theirs = recurring("Theirs", partner, partner, now)
        assertEquals(listOf(mine, forMe), listOf(mine, forMe, theirs).visibleTo(me))
    }
}

class SchedulePlanFixTests {
    private val me = UUID.randomUUID()
    private val now = at(2026, 11, 6, 12)

    private fun specs(vararg reminders: ReminderDto, at: Instant = now, zone: ZoneId = LA, events: List<ReminderEventDto> = emptyList()) =
        NotificationPlanner.reminderSpecs(me, reminders.toList(), events, at, zone)

    // B9: a recurring reminder's "Starting" date.

    @Test fun b9_aDailyThatStartsIn40DaysDoesNotRingBeforeItsStart() {
        val anchor = now.plusSeconds(40 * 86_400)
        val spec = specs(reminder("recurring", fireAt = anchor, rrule = "FREQ=DAILY", authorId = me)).single()
        assertEquals(anchor.truncatedTo(java.time.temporal.ChronoUnit.MINUTES), spec.fireAt)
        assertEquals(RecurrencePreset.DAILY, spec.repeat)
    }

    @Test fun b9_aWeeklyThatStartsIn3WeeksDoesNotRingBeforeItsStart() {
        val anchor = now.plusSeconds(21 * 86_400)
        val spec = specs(reminder("recurring", fireAt = anchor, rrule = "FREQ=WEEKLY", authorId = me)).single()
        assertEquals(anchor, spec.fireAt)
    }

    @Test fun b9_control_aDailyThatAlreadyStartedRepeatsWithinADay() {
        val anchor = at(2026, 10, 27, 9)
        val spec = specs(reminder("recurring", fireAt = anchor, rrule = "FREQ=DAILY", authorId = me)).single()
        assertEquals(at(2026, 11, 7, 9), spec.fireAt)
        assertEquals(RecurrencePreset.DAILY, spec.repeat)
        assertTrue(spec.fireAt.epochSecond - now.epochSecond <= 86_400)
    }

    @Test fun b9_aDeliveredStartingReminderThenRepeatsFromItsStart() {
        val platform = object : AlarmPlatform {
            override fun canNotify() = true
            override fun arm(spec: NotificationSpec) = Unit
            override fun cancel(id: String) = Unit
        }
        var clock = now
        val scheduler = AlarmNotificationScheduler(platform, InMemoryStore(), { clock }, { LA })
        val r = reminder("recurring", fireAt = at(2026, 12, 17, 9), rrule = "FREQ=DAILY", authorId = me)
        scheduler.reschedule(me, listOf(r), emptyList())
        assertEquals(at(2026, 12, 17, 9), scheduler.spec(r.id.toString())?.fireAt)
        clock = at(2026, 12, 17, 9)
        scheduler.markDelivered(r.id.toString())
        assertEquals(at(2026, 12, 18, 9), scheduler.spec(r.id.toString())?.fireAt)
    }

    @Test fun b9_aMonthlyReminderOnThe31stRingsInEveryMonth() {
        val anchor = at(2025, 1, 31, 9)
        var after = now
        val rings = (0 until 6).map {
            NotificationPlanner.nextCalendarMatch(anchor, RecurrencePreset.MONTHLY, after, LA)!!.also { next -> after = next }
        }
        assertEquals(
            listOf(at(2026, 11, 30, 9), at(2026, 12, 31, 9), at(2027, 1, 31, 9), at(2027, 2, 28, 9), at(2027, 3, 31, 9), at(2027, 4, 30, 9)),
            rings,
        )
    }

    @Test fun b9_theListShowsTheClampedDayAndThenThe31stAgain() {
        val trigger = ReminderTrigger.Recurring("FREQ=MONTHLY", at(2026, 1, 31, 9))
        assertEquals(at(2026, 2, 28, 9), trigger.upcomingFireDate(at(2026, 2, 1), LA))
        assertEquals(at(2026, 3, 31, 9), trigger.upcomingFireDate(at(2026, 3, 1), LA))
        assertEquals(at(2026, 4, 30, 9), trigger.upcomingFireDate(at(2026, 4, 1), LA))
    }

    @Test fun b9_yearlyFeb29ClampsAndComesBack() {
        val trigger = ReminderTrigger.Recurring("FREQ=YEARLY", at(2024, 2, 29, 9))
        assertEquals(at(2027, 2, 28, 9), trigger.upcomingFireDate(at(2026, 6, 1), LA))
        assertEquals(at(2028, 2, 29, 9), trigger.upcomingFireDate(at(2027, 6, 1), LA))
    }

    // B10: a pending one-shot after a time zone change.

    @Test fun b10_control_oneShotsAreAbsoluteInstantsSoAZoneChangeCannotMoveThem() {
        val fireAt = now.plusSeconds(3 * 3_600)
        val oneTime = reminder("one_time", fireAt = fireAt, authorId = me)
        val surprise = reminder("random_window", fireAt = fireAt, windowStart = now, windowEnd = fireAt, authorId = me)
        for (zone in listOf(LA, NEW_YORK, TOKYO)) {
            assertEquals(fireAt.truncatedTo(java.time.temporal.ChronoUnit.MINUTES), specs(oneTime, zone = zone).single().fireAt)
            assertEquals(fireAt.truncatedTo(java.time.temporal.ChronoUnit.MINUTES), specs(surprise, zone = zone).single().fireAt)
        }
    }

    // B6: a daily random reminder when the app is not opened again.

    private fun dailyRandom() = reminder(
        "random_window", fireAt = at(2026, 11, 6, 21), rrule = "FREQ=DAILY",
        windowStart = at(2026, 11, 6, 18), windowEnd = at(2026, 11, 6, 21),
        authorId = me, createdAt = now.minusSeconds(30 * 86_400),
    )

    @Test fun b6_aDailyRandomReminderRingsEveryDayWithoutTheAppBeingOpened() {
        val plan = specs(dailyRandom())
        assertTrue(plan.all { it.repeat == RecurrencePreset.WEEKLY })
        assertEquals(7, plan.map { it.fireAt.atZone(LA).dayOfWeek }.toSet().size)
        for (spec in plan) {
            val minute = spec.anchor!!.atZone(LA).let { it.hour * 60 + it.minute }
            assertTrue("$minute", minute in (18 * 60)..(21 * 60))
        }
    }

    @Test fun b6_theReminderKeepsRingingAfterTenDaysWithoutAnOpen() {
        val platform = object : AlarmPlatform {
            override fun canNotify() = true
            override fun arm(spec: NotificationSpec) = Unit
            override fun cancel(id: String) = Unit
        }
        var clock = now
        val scheduler = AlarmNotificationScheduler(platform, InMemoryStore(), { clock }, { LA })
        scheduler.reschedule(me, listOf(dailyRandom()), emptyList())
        val end = at(2026, 11, 16, 12)
        var delivered = 0
        while (true) {
            val next = scheduler.pendingSpecs().firstOrNull() ?: break
            if (next.fireAt.isAfter(end)) break
            clock = next.fireAt
            scheduler.markDelivered(next.id)
            delivered += 1
        }
        clock = end
        assertTrue("rang $delivered times", delivered >= 9)
        val pending = scheduler.pendingSpecs()
        assertEquals(7, pending.size)
        assertEquals(7, pending.map { it.fireAt.atZone(LA).dayOfWeek }.toSet().size)
        assertTrue(pending.first().fireAt.isBefore(end.plusSeconds(86_400)))
    }

    @Test fun b6_doneTodaySkipsTodayAndStillCoversEveryWeekday() {
        val r = dailyRandom()
        val plan = specs(r, events = listOf(acted(r, now)))
        assertTrue("rings again today", plan.none { it.fireAt.isBefore(at(2026, 11, 7)) })
        assertEquals(7, plan.map { it.fireAt.atZone(LA).dayOfWeek }.toSet().size)
    }

    // B3: template packs arrive one at a time.

    @Test fun b3_dailyPacksImportedTogetherNeverRingAtTheSameTime() {
        val imported = mutableListOf<ReminderDto>()
        for (id in listOf("daily_affirmations", "new_parents", "appreciation")) {
            val group = ReminderTemplateStore.groups.first { it.id == id }
            val dates = ReminderTemplateStore.fireDates(group.reminders, me, imported, now, LA)
            assertEquals(group.reminders.size, dates.size)
            imported += group.reminders.zip(dates).map { (template, date) ->
                reminder(
                    if (template.triggerRecurrence == null) "one_time" else "recurring",
                    fireAt = date, rrule = template.triggerRecurrence?.rrule, authorId = me,
                )
            }
        }
        val clocks = imported.map { r -> r.fireAt!!.atZone(LA).let { it.hour * 60 + it.minute } }
        assertEquals("shared clock times: ${clocks.sorted()}", clocks.size, clocks.toSet().size)
        assertTrue(imported.all { it.fireAt!!.isAfter(now) })
    }

    @Test fun b3_aPackAvoidsTheTimesOfRemindersAlreadyThere() {
        val existing = listOf(reminder("recurring", fireAt = at(2026, 11, 1, 9), rrule = "FREQ=DAILY", authorId = me))
        val group = ReminderTemplateStore.groups.first { it.id == "new_parents" }
        val dates = ReminderTemplateStore.fireDates(group.reminders, me, existing, now, LA)
        assertTrue(dates.none { it.atZone(LA).hour == 9 && it.atZone(LA).minute == 0 })
    }

    @Test fun b3_aPartnersRemindersDoNotTakeMyTimes() {
        val partner = UUID.randomUUID()
        val theirs = listOf(reminder("recurring", fireAt = at(2026, 11, 1, 9), rrule = "FREQ=DAILY", authorId = partner, targetId = partner))
        val group = ReminderTemplateStore.groups.first { it.id == "new_parents" }
        val first = ReminderTemplateStore.fireDates(group.reminders, me, theirs, now, LA).first()
        assertEquals(at(2026, 11, 7, 9), first)
    }

    // The boundary of "done this period" must stay the iOS one.

    @Test fun doneThisPeriod_aWeeklyDoneOnSaturdayIsOpenAgainOnSundayInSundayFirstRegions() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=WEEKLY", authorId = me)
        val doneSaturday = listOf(acted(r, at(2026, 10, 17, 10)))
        val sunday = at(2026, 10, 18, 9)
        assertFalse(r.isCompleted(doneSaturday, sunday, LA))
        assertTrue(r.isCompleted(doneSaturday, at(2026, 10, 17, 22), LA))
    }
}

class SaveAndLoadFixTests {
    private fun reminderRow(r: ReminderDto) = Codec.reminderJson(r)

    private fun repo(b: Backend) = ReminderRepository(b.client, b.pairing, b.seed)
    private fun eventsRepo(b: Backend) = ReminderEventRepository(b.client, b.pairing, b.seed)
    private fun coupleRow(b: Backend) = JSONObject().put("id", b.coupleId.toString()).put("partner_a", b.me.toString())
        .put("partner_b", b.partner.toString()).put("solo", false)

    // B13

    @Test fun b13_aFailedPartnerProfileCommitsNothing() = runTest {
        val b = Backend()
        b.route = { call ->
            when {
                b.table(call, "couples") -> Backend.rows(coupleRow(b))
                else -> Backend.down()
            }
        }
        assertFalse(b.pairing.loadCouple())
        assertNull(b.pairing.coupleId)
        assertNull(b.pairing.partnerProfile)
        assertFalse(b.pairing.solo)
    }

    @Test fun b13_aFailedReloadKeepsTheCoupleThatWasThere() = runTest {
        val b = Backend()
        val profile = JSONObject().put("id", b.partner.toString()).put("display_name", "Sam")
        var profileUp = true
        b.route = { call ->
            when {
                b.table(call, "couples") -> Backend.rows(coupleRow(b))
                b.table(call, "profiles") -> if (profileUp) Backend.rows(profile) else Backend.down()
                else -> Backend.ok()
            }
        }
        assertTrue(b.pairing.loadCouple())
        assertEquals(b.partner, b.pairing.partnerProfile?.id)
        assertEquals("Sam", b.prefs.partnerName)
        profileUp = false
        assertFalse(b.pairing.loadCouple())
        assertEquals(b.coupleId, b.pairing.coupleId)
        assertEquals(b.partner, b.pairing.partnerProfile?.id)
    }

    // B12 and B8

    @Test fun b12_aDoneThatWasNotSavedIsNotAPositiveMoment() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        b.route = { call -> if (call.method == "POST") Backend.down() else Backend.ok() }
        val events = eventsRepo(b)
        val r = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me)
        assertFalse(events.markDone(r, b.coupleId))
        assertTrue(events.events.isEmpty())
    }

    @Test fun b12_aSavedDoneCounts() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val events = eventsRepo(b)
        val r = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me)
        assertTrue(events.markDone(r, b.coupleId))
        assertTrue(r.isCompleted(events.events))
    }

    @Test fun b8_aDoneWhoseReReadFailedStaysDoneSoASecondTapCannotRecordItTwice() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        b.route = { call -> if (call.method == "GET") Backend.down() else Backend.ok() }
        val events = eventsRepo(b)
        val r = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me)
        assertTrue(events.markDone(r, b.coupleId))
        assertTrue(r.isCompleted(events.events))
        val sent = JSONObject(b.calls.single { it.method == "POST" }.body!!)
        assertEquals(events.events.single().id.toString(), sent.getString("id"))
    }

    @Test fun b8_notDoneRemovesEveryCompletionCoveringThePeriod() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val events = eventsRepo(b)
        val r = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me, targetId = b.partner)
        val mine = acted(r, at(2026, 11, 6, 10))
        val theirs = acted(r, at(2026, 11, 6, 11))
        val other = acted(reminder("one_time", fireAt = at(2026, 11, 7, 9)), at(2026, 11, 6, 12))
        events.events = listOf(mine, theirs, other)
        events.undoCompletion(r, at(2026, 11, 6, 13))
        val delete = b.calls.single { it.method == "DELETE" }
        assertTrue(delete.url, mine.id.toString() in delete.url && theirs.id.toString() in delete.url)
        assertFalse(other.id.toString() in delete.url)
        assertEquals(listOf(other), events.events)
        assertFalse(r.isCompleted(events.events))
    }

    @Test fun b8_aDailyUndoKeepsYesterdaysCompletion() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val events = eventsRepo(b)
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=DAILY", authorId = b.me)
        val yesterday = acted(r, at(2026, 11, 5, 10))
        val today = acted(r, at(2026, 11, 6, 10))
        events.events = listOf(today, yesterday)
        events.undoCompletion(r, at(2026, 11, 6, 13))
        assertEquals(listOf(yesterday), events.events)
    }

    // B14

    @Test fun b14_aSaveWhoseReReadFailedIsListed() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val old = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me, id = UUID.randomUUID(), title = "Walk")
        val moved = old.copy(fireAt = at(2026, 11, 7, 18))
        var reads = 0
        b.route = { call ->
            when {
                call.method == "GET" -> if (reads++ == 0) Backend.rows(reminderRow(old)) else Backend.down()
                call.method == "POST" -> Backend.rows(reminderRow(moved))
                else -> Backend.ok()
            }
        }
        val repo = repo(b)
        repo.refresh()
        repo.upsert(moved)
        assertEquals(moved.fireAt, repo.reminders.single().fireAt)
        assertTrue(repo.hasLoaded)
    }

    @Test fun b14_aPartnersRescheduleWhoseReReadFailedIsListed() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val theirs = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.partner, targetId = b.me, title = "Call mom")
        val moved = theirs.copy(fireAt = at(2026, 11, 7, 18), title = "ignored by the server")
        var reads = 0
        b.route = { call ->
            when {
                call.method == "GET" -> if (reads++ == 0) Backend.rows(reminderRow(theirs)) else Backend.down()
                else -> Backend.ok()
            }
        }
        val repo = repo(b)
        repo.refresh()
        repo.reschedule(moved)
        val stored = repo.reminders.single()
        assertEquals(at(2026, 11, 7, 18), stored.fireAt)
        assertEquals("Call mom", stored.title)
    }

    @Test fun b14_aPackImportWhoseReReadFailedIsListed() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        var reads = 0
        b.route = { call -> if (call.method == "GET") (if (reads++ == 0) Backend.ok() else Backend.down()) else Backend.ok() }
        val repo = repo(b)
        repo.refresh()
        val drafts = listOf(
            reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me),
            reminder("one_time", fireAt = at(2026, 11, 8, 9), authorId = b.me),
        )
        repo.bulkInsert(drafts)
        assertEquals(drafts.map { it.id }.toSet(), repo.reminders.map { it.id }.toSet())
    }

    // B2

    private class RecordingScheduler : ReminderScheduling {
        var rebuilt: List<List<ReminderEventDto>> = emptyList()
        override fun reschedule(selfId: UUID, reminders: List<ReminderDto>, events: List<ReminderEventDto>) {
            rebuilt = rebuilt + listOf(events)
        }
        override fun rescheduleMilestones(milestones: List<MilestoneDto>) = Unit
        override fun clearAll() = Unit
    }

    @Test fun b2_aLaunchWhoseCompletionsFailedDoesNotRebuildTheSchedule() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val handled = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me)
        b.route = { call ->
            when {
                b.table(call, "reminders") -> Backend.rows(reminderRow(handled))
                b.table(call, "reminder_events") -> Backend.down()
                else -> Backend.ok()
            }
        }
        val repo = repo(b)
        val events = eventsRepo(b)
        val scheduler = RecordingScheduler()
        assertFalse("rebuilt before anything was fetched", rebuildSchedule(scheduler, b.me, repo, events))
        repo.refresh()
        events.refresh()
        assertNull(events.loadedEvents)
        assertFalse(rebuildSchedule(scheduler, b.me, repo, events))
        assertTrue(scheduler.rebuilt.isEmpty())
    }

    @Test fun b2_aLaunchWhoseRemindersFailedDoesNotCancelEveryArmedReminder() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        b.route = { call -> if (b.table(call, "reminders")) Backend.down() else Backend.ok() }
        val repo = repo(b)
        val events = eventsRepo(b)
        repo.refresh()
        events.refresh()
        assertFalse(repo.hasLoaded)
        assertFalse(rebuildSchedule(RecordingScheduler(), b.me, repo, events))
    }

    @Test fun b2_oncebothWereFetchedTheScheduleIsRebuiltFromThem_andAChangedCoupleWaitsAgain() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val handled = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.me)
        val done = acted(handled, at(2026, 11, 6, 10))
        b.route = { call ->
            when {
                b.table(call, "reminders") -> Backend.rows(reminderRow(handled))
                b.table(call, "reminder_events") -> Backend.rows(Codec.eventJson(done))
                else -> Backend.ok()
            }
        }
        val repo = repo(b)
        val events = eventsRepo(b)
        val scheduler = RecordingScheduler()
        repo.refresh()
        events.refresh()
        assertTrue(rebuildSchedule(scheduler, b.me, repo, events))
        assertEquals(listOf(done), scheduler.rebuilt.single())
        b.pairing.coupleId = UUID.randomUUID()
        assertFalse(repo.hasLoaded)
        assertFalse(events.hasLoaded)
        assertFalse(rebuildSchedule(scheduler, b.me, repo, events))
    }
}

class OpenFromNotificationTests {
    private fun r(title: String) = reminder("one_time", fireAt = at(2026, 11, 7, 9), title = title)

    @Test fun b5_aBannerTappedWhileASheetIsUpIsHeldUntilItCloses() {
        val a = r("A")
        val b = r("B")
        assertNull(reminderToOpen(b.id, listOf(a, b), whilePresenting = true))
        assertEquals(b, reminderToOpen(b.id, listOf(a, b), whilePresenting = false))
    }

    @Test fun b5_control_aTapForAReminderNotLoadedYetStaysPending() {
        assertNull(reminderToOpen(UUID.randomUUID(), listOf(r("A")), whilePresenting = false))
        assertNull(reminderToOpen(null, listOf(r("A")), whilePresenting = false))
    }
}

class MemberSinceTests {
    @Test fun b16_sinceIsTheOriginalPurchaseNotTheLatestRenewal() {
        val original = Instant.parse("2025-01-10T00:00:00Z")
        val renewal = Instant.parse("2026-10-10T00:00:00Z")
        assertEquals(original, Membership.since(original, renewal))
    }

    @Test fun b16_withoutAnOriginalDateTheLatestOneStands() {
        val renewal = Instant.parse("2026-10-10T00:00:00Z")
        assertEquals(renewal, Membership.since(null, renewal))
        assertNull(Membership.since(null, null))
    }
}

class LoveLanguageSanityTests {
    // The fixtures above rely on the analyzer reading language from the reminder.
    @Test fun fixturesUseWordsByDefault() {
        assertEquals(LoveLanguage.WORDS, reminder("one_time", fireAt = at(2026, 11, 7, 9)).loveLanguage)
    }
}
