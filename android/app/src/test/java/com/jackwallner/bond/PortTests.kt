package com.jackwallner.bond

import com.jackwallner.bond.data.AlarmNotificationScheduler
import com.jackwallner.bond.data.AlarmPlatform
import com.jackwallner.bond.data.AppClock
import com.jackwallner.bond.data.DAY_MS
import com.jackwallner.bond.data.DailyCheckInService
import com.jackwallner.bond.data.InMemoryStore
import com.jackwallner.bond.data.PairingService
import com.jackwallner.bond.data.PaywallCopy
import com.jackwallner.bond.data.PeriodUnit
import com.jackwallner.bond.data.PlanInfo
import com.jackwallner.bond.data.PlanKind
import com.jackwallner.bond.data.PurchaseOutcome
import com.jackwallner.bond.data.resolveOnboardingPurchase
import com.jackwallner.bond.data.ReviewAccess
import com.jackwallner.bond.data.ReviewPromptTracker
import com.jackwallner.bond.model.FocusArea
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.LoveLanguageAnalyzer
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.NotificationPlanner
import com.jackwallner.bond.model.NotificationSpec
import com.jackwallner.bond.model.RecurrencePreset
import com.jackwallner.bond.model.ReminderTemplateStore
import com.jackwallner.bond.model.StarterChips
import com.jackwallner.bond.model.TriggerKind
import com.jackwallner.bond.model.currentCompletionEvent
import com.jackwallner.bond.model.currentPeriodStart
import com.jackwallner.bond.model.isCompleted
import com.jackwallner.bond.model.repeatsOnSchedule
import java.math.BigDecimal
import java.security.MessageDigest
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import kotlinx.coroutines.test.runTest
import org.junit.Test

/** The daily question must resolve to the same row on both platforms, so these numbers come from Swift. */
class CheckInMathTests {
    @Test fun dayOrdinal_matchesFoundationEraOrdinal() {
        assertEquals(719_163L, DailyCheckInService.dayOrdinal(LocalDate.of(1970, 1, 1)))
        assertEquals(739_907L, DailyCheckInService.dayOrdinal(LocalDate.of(2026, 10, 18)))
        assertEquals(730_180L, DailyCheckInService.dayOrdinal(LocalDate.of(2000, 3, 1)))
    }

    @Test fun stableSeed_matchesSwiftFold() {
        assertEquals(4_924_926_182_700_526_240L, DailyCheckInService.stableSeed(UUID.fromString("33333333-3333-4333-8333-333333333333")))
        assertEquals(5_998_929_909_607_312_578L, DailyCheckInService.stableSeed(UUID.fromString("E621E1F8-C36C-495A-93FC-0C247A3E6E5F")))
        assertEquals(6_171_105_530_667_000_304L, DailyCheckInService.stableSeed(UUID.fromString("FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")))
    }

    @Test fun questionIndex_matchesSwift() {
        val day = LocalDate.ofEpochDay(739_000L - 719_163L)
        assertEquals(20, DailyCheckInService.questionIndex(day, UUID.fromString("33333333-3333-4333-8333-333333333333"), 30))
        assertEquals(28, DailyCheckInService.questionIndex(day, UUID.fromString("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"), 30))
        assertEquals(14, DailyCheckInService.questionIndex(day, UUID.fromString("FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF"), 30))
    }

    @Test fun questionIndex_emptyTableStillAnIndex() =
        assertEquals(0, DailyCheckInService.questionIndex(LocalDate.of(2026, 10, 18), UUID.randomUUID(), 0))

    @Test fun questionIndex_sameForBothPartnersOfACouple() {
        val couple = UUID.randomUUID()
        val day = LocalDate.of(2026, 10, 18)
        assertEquals(DailyCheckInService.questionIndex(day, couple, 30), DailyCheckInService.questionIndex(day, couple, 30))
    }
}

class StablePickTests {
    private val id = UUID.fromString("E621E1F8-C36C-495A-93FC-0C247A3E6E5F")

    private fun pick(day: LocalDate): Instant {
        val dayStart = day.atStartOfDay(LA).toInstant()
        return NotificationPlanner.stablePick(day.atTime(18, 0).atZone(LA).toInstant(), day.atTime(21, 0).atZone(LA).toInstant(), id, dayStart)
    }

    @Test fun matchesSwiftForTheSameDay() {
        assertEquals(1_792_381_752_950.0, pick(LocalDate.of(2026, 10, 18)).toEpochMilli().toDouble(), 1.0)
        assertEquals(1_792_464_137_629.0, pick(LocalDate.of(2026, 10, 19)).toEpochMilli().toDouble(), 1.0)
    }

    @Test fun staysInsideTheWindow() {
        var day = LocalDate.of(2026, 1, 1)
        repeat(60) {
            val p = pick(day)
            assertFalse(p.isBefore(day.atTime(18, 0).atZone(LA).toInstant()))
            assertTrue(p.isBefore(day.atTime(21, 0).atZone(LA).toInstant()))
            day = day.plusDays(1)
        }
    }
}

class NotificationPlannerTests {
    private val me = UUID.randomUUID()
    private val partner = UUID.randomUUID()
    private val now = at(2026, 10, 18, 12)

    @Test fun onlyRemindersTargetingMeArePlanned() {
        val mine = reminder("one_time", fireAt = at(2026, 10, 19, 9), authorId = partner, targetId = me)
        val theirs = reminder("one_time", fireAt = at(2026, 10, 19, 9), authorId = me, targetId = partner)
        val specs = NotificationPlanner.reminderSpecs(me, listOf(mine, theirs), emptyList(), now, LA)
        assertEquals(listOf(mine.id.toString()), specs.map { it.id })
    }

    @Test fun pastAndHandledOneShotsAreSkipped() {
        val past = reminder("one_time", fireAt = at(2026, 10, 17, 9), authorId = me)
        val handled = reminder("one_time", fireAt = at(2026, 10, 20, 9), authorId = me)
        val specs = NotificationPlanner.reminderSpecs(me, listOf(past, handled), listOf(acted(handled, now)), now, LA)
        assertTrue(specs.isEmpty())
    }

    @Test fun oneTimeIsTruncatedToTheMinute() {
        val r = reminder("one_time", fireAt = at(2026, 10, 19, 9, 30).plusSeconds(42), authorId = me)
        assertEquals(at(2026, 10, 19, 9, 30), NotificationPlanner.reminderSpecs(me, listOf(r), emptyList(), now, LA).single().fireAt)
    }

    @Test fun recurringFiresAtTheNextCalendarMatchAndRepeats() {
        val r = reminder("recurring", fireAt = at(2026, 1, 5, 8, 15), rrule = "FREQ=WEEKLY", authorId = me)
        val spec = NotificationPlanner.reminderSpecs(me, listOf(r), emptyList(), now, LA).single()
        // Jan 5 2026 is a Monday; the next Monday 8:15 after Sunday Oct 18 is Oct 19.
        assertEquals(at(2026, 10, 19, 8, 15), spec.fireAt)
        assertEquals(RecurrencePreset.WEEKLY, spec.repeat)
    }

    @Test fun randomRecurringLaysDownAFiveDayRunway() {
        val r = reminder("random_window", rrule = "FREQ=DAILY", windowStart = at(2026, 10, 1, 18), windowEnd = at(2026, 10, 1, 21), authorId = me)
        val specs = NotificationPlanner.reminderSpecs(me, listOf(r), emptyList(), now, LA)
        assertEquals((0 until 5).map { "${r.id}.day$it" }, specs.map { it.id })
        specs.forEachIndexed { offset, spec ->
            val day = LocalDate.of(2026, 10, 18).plusDays(offset.toLong())
            assertFalse(spec.fireAt.isBefore(day.atTime(18, 0).atZone(LA).toInstant()))
            assertTrue(spec.fireAt.isBefore(day.atTime(21, 0).atZone(LA).toInstant()))
        }
    }

    @Test fun randomRecurringDoneTodaySkipsToday() {
        val r = reminder("random_window", rrule = "FREQ=DAILY", windowStart = at(2026, 10, 1, 18), windowEnd = at(2026, 10, 1, 21), authorId = me)
        val specs = NotificationPlanner.reminderSpecs(me, listOf(r), listOf(acted(r, now)), now, LA)
        assertEquals((1 until 5).map { "${r.id}.day$it" }, specs.map { it.id })
    }

    @Test fun locationRemindersAreNotPlannedOnAndroid() {
        val r = reminder("location", geofence = com.jackwallner.bond.model.Geofence(1.0, 2.0, 200.0, "Home"), authorId = me)
        assertTrue(NotificationPlanner.reminderSpecs(me, listOf(r), emptyList(), now, LA).isEmpty())
    }

    @Test fun monthlySkipsMonthsWithoutTheDay() {
        val next = NotificationPlanner.nextCalendarMatch(at(2026, 1, 31, 9), RecurrencePreset.MONTHLY, at(2026, 2, 1), LA)
        assertEquals(at(2026, 3, 31, 9), next)
    }

    @Test fun yearlyFeb29OnlyInLeapYears() {
        val next = NotificationPlanner.nextCalendarMatch(at(2024, 2, 29, 9), RecurrencePreset.YEARLY, at(2024, 3, 1), LA)
        assertEquals(at(2028, 2, 29, 9), next)
    }

    @Test fun dailyLaterTodayWhenTheTimeIsStillAhead() =
        assertEquals(at(2026, 10, 18, 20), NotificationPlanner.nextCalendarMatch(at(2026, 1, 1, 20), RecurrencePreset.DAILY, now, LA))

    @Test fun milestonePingsAWeekBeforeTheDayBeforeAndTheDay() {
        val m = MilestoneDto(UUID.randomUUID(), UUID.randomUUID(), "anniversary", "Our anniversary", LocalDate.of(2000, 12, 1), true)
        val specs = NotificationPlanner.milestoneSpecs(listOf(m), now, LA)
        assertEquals(listOf("milestone.${m.id}.-7", "milestone.${m.id}.-1", "milestone.${m.id}.0"), specs.map { it.id })
        assertEquals(listOf(at(2026, 11, 24, 9), at(2026, 11, 30, 9), at(2026, 12, 1, 9)), specs.map { it.fireAt })
        assertEquals(
            listOf("Our anniversary is in 1 week.", "Our anniversary is tomorrow.", "Our anniversary is today."),
            specs.map { it.body },
        )
    }

    @Test fun milestoneOnTheDstChangeKeepsIosElapsedHourMath() {
        // iOS adds 9 elapsed hours to the start of the day, so Nov 1 (fall back) lands at 8:00.
        val m = MilestoneDto(UUID.randomUUID(), UUID.randomUUID(), "anniversary", "Ours", LocalDate.of(2000, 11, 1), true)
        assertEquals(at(2026, 11, 1, 8), NotificationPlanner.milestoneSpecs(listOf(m), now, LA).last().fireAt)
    }

    @Test fun milestoneWithoutLabelUsesItsKind() {
        val m = MilestoneDto(UUID.randomUUID(), UUID.randomUUID(), "birthday", null, LocalDate.of(2026, 10, 18), false)
        val specs = NotificationPlanner.milestoneSpecs(listOf(m), at(2026, 10, 18, 6), LA)
        assertEquals("Birthday", specs.single().title)
    }
}

class CompletionTests {
    private val now = at(2026, 10, 18, 12) // a Sunday

    @Test fun oneShotIsDoneForeverByOneEvent() {
        val r = reminder("one_time", fireAt = at(2026, 10, 1, 9))
        assertFalse(r.repeatsOnSchedule(now, LA))
        assertTrue(r.isCompleted(listOf(acted(r, at(2026, 10, 2))), now, LA))
    }

    @Test fun dailyIsDoneOnlyForToday() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=DAILY")
        assertTrue(r.isCompleted(listOf(acted(r, at(2026, 10, 18, 8))), now, LA))
        assertFalse(r.isCompleted(listOf(acted(r, at(2026, 10, 17, 23))), now, LA))
    }

    @Test fun weeklyPeriodStartsOnTheLocalesFirstDay() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=WEEKLY")
        assertEquals(at(2026, 10, 18), r.currentPeriodStart(now, LA, Locale.US))
        assertEquals(at(2026, 10, 12), r.currentPeriodStart(now, LA, Locale.UK))
    }

    @Test fun monthlyAndYearlyPeriods() {
        assertEquals(at(2026, 10, 1), reminder("recurring", at(2026, 1, 1), "FREQ=MONTHLY").currentPeriodStart(now, LA))
        assertEquals(at(2026, 1, 1), reminder("recurring", at(2026, 1, 1), "FREQ=YEARLY").currentPeriodStart(now, LA))
    }

    @Test fun dailySurpriseCompletesPerDay() {
        val r = reminder("random_window", rrule = "FREQ=DAILY", windowStart = at(2026, 10, 1, 18), windowEnd = at(2026, 10, 1, 21))
        assertTrue(r.repeatsOnSchedule(now, LA))
        assertEquals(at(2026, 10, 18), r.currentPeriodStart(now, LA))
    }

    @Test fun currentCompletionEventIsTheOneInThisPeriod() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=DAILY")
        val today = acted(r, at(2026, 10, 18, 7))
        assertEquals(today, r.currentCompletionEvent(listOf(acted(r, at(2026, 10, 17, 7)), today), now, LA))
    }
}

class AnalyzerTests {
    private val now = at(2026, 10, 18, 12)

    @Test fun evenSpreadScoresOneHundred() {
        val reminders = LoveLanguage.entries.map { reminder("one_time", fireAt = now, language = it) }
        assertEquals(100.0, LoveLanguageAnalyzer(reminders, emptyList(), LA, Locale.US).balanceScore(), 0.001)
    }

    @Test fun oneLanguageScoresLowAndNamesTheNeglected() {
        val reminders = List(4) { reminder("one_time", fireAt = now, language = LoveLanguage.TIME) }
        val a = LoveLanguageAnalyzer(reminders, emptyList(), LA, Locale.US)
        // iOS formula: 1 - variance / maxVariance, so a single language floors at 20.
        assertEquals(20.0, a.balanceScore(), 0.001)
        assertEquals(LoveLanguage.TIME, a.mostUsed()?.first)
        assertEquals(LoveLanguage.WORDS, a.mostNeglected()?.first)
    }

    @Test fun noRemindersMeansNoScore() {
        val a = LoveLanguageAnalyzer(emptyList(), emptyList(), LA, Locale.US)
        assertEquals(0.0, a.balanceScore(), 0.0)
        assertNull(a.mostNeglected())
        assertTrue(a.insights(now).isEmpty())
    }

    @Test fun streaksCountConsecutiveDays() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=DAILY")
        val events = listOf(at(2026, 10, 10, 9), at(2026, 10, 11, 9), at(2026, 10, 12, 9), at(2026, 10, 16, 9), at(2026, 10, 17, 9))
            .map { acted(r, it) }
        val a = LoveLanguageAnalyzer(listOf(r), events, LA, Locale.US)
        // Today has nothing yet, which doesn't break yesterday's run.
        assertEquals(2, a.currentStreak(now))
        assertEquals(3, a.longestStreak())
    }

    @Test fun followThroughCountsDuePeriodsInTheLastWeek() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=DAILY", createdAt = at(2026, 10, 1))
        val events = listOf(acted(r, at(2026, 10, 18, 9)), acted(r, at(2026, 10, 16, 9)))
        val item = LoveLanguageAnalyzer(listOf(r), events, LA, Locale.US).followThrough(7, now).single()
        assertEquals(7, item.expected)
        assertEquals(2, item.completed)
    }

    @Test fun completionRateIncludesDueOneShots() {
        val due = reminder("one_time", fireAt = at(2026, 10, 15, 9))
        val done = reminder("one_time", fireAt = at(2026, 10, 16, 9))
        val rate = LoveLanguageAnalyzer(listOf(due, done), listOf(acted(done, at(2026, 10, 16, 10))), LA, Locale.US).completionRate(7, now)
        assertEquals(50.0, rate!!, 0.001)
    }

    @Test fun weeklyTrendsBucketByWeek() {
        val r = reminder("recurring", fireAt = at(2026, 10, 1, 9), rrule = "FREQ=DAILY", language = LoveLanguage.GIFTS)
        val events = listOf(acted(r, at(2026, 10, 5, 9)), acted(r, at(2026, 10, 6, 9)), acted(r, at(2026, 10, 13, 9)))
        val trends = LoveLanguageAnalyzer(listOf(r), events, LA, Locale.US).weeklyTrends()
        assertEquals(listOf(LocalDate.of(2026, 10, 4), LocalDate.of(2026, 10, 11)), trends.map { it.weekStart })
        assertEquals(2, trends[0].counts.first { it.first == LoveLanguage.GIFTS }.second)
    }
}

class ContentTests {
    @Test fun starterChipsFollowFocusAreasAndFloatThePrimary() {
        val chips = StarterChips.forPreferences(setOf(FocusArea.LOVES, FocusArea.AVOID), LoveLanguage.TIME)
        assertTrue(chips.all { it.area == FocusArea.LOVES || it.area == FocusArea.AVOID })
        assertEquals(5, chips.size)
        assertEquals(LoveLanguage.TIME, chips.first().loveLanguage)
    }

    @Test fun starterChipsFallBackToGestures() {
        val chips = StarterChips.forPreferences(emptySet(), LoveLanguage.WORDS)
        assertTrue(chips.all { it.area == FocusArea.GESTURES })
        assertEquals("Tell them they're beautiful", chips.first().title)
    }

    @Test fun templatePacksMatchIos() {
        assertEquals(
            listOf("daily_affirmations", "date_night", "long_distance", "new_parents", "appreciation", "acts_of_service"),
            ReminderTemplateStore.groups.map { it.id },
        )
        assertTrue(ReminderTemplateStore.groups.all { it.reminders.isNotEmpty() })
    }

    @Test fun templateDraftsAreStaggeredAtFriendlyHours() {
        val group = ReminderTemplateStore.groups.first { it.id == "daily_affirmations" }
        val me = UUID.randomUUID()
        val drafts = ReminderTemplateStore.drafts(group, UUID.randomUUID(), me, me, at(2026, 10, 18, 12), LA)
        // Recurring packs anchor at 9am; noon has passed it, so the first is tomorrow.
        assertEquals(listOf(at(2026, 10, 19, 9), at(2026, 10, 20, 9), at(2026, 10, 21, 9)), drafts.map { it.fireAt })
        assertEquals(listOf("FREQ=DAILY", "FREQ=DAILY", "FREQ=WEEKLY"), drafts.map { it.rrule })
        assertTrue(drafts.all { it.triggerType == "recurring" })
    }

    @Test fun locationIsNotOfferedForNewRemindersOnAndroid() {
        assertFalse(TriggerKind.LOCATION.availableOnAndroid)
        assertTrue(TriggerKind.entries.filter { it != TriggerKind.LOCATION }.all { it.availableOnAndroid })
    }
}

class PaywallCopyTests {
    private fun plan(kind: PlanKind, price: String, unit: PeriodUnit?, trial: Int = 0) = PlanInfo(
        id = kind.name, productId = kind.name.lowercase(), kind = kind, storeTitle = kind.name,
        price = BigDecimal(price), formattedPrice = "$$price", currencyCode = "USD",
        periodUnit = unit, trialUnit = if (trial > 0) PeriodUnit.DAY else null, trialValue = trial,
    )

    private val yearly = plan(PlanKind.YEARLY, "39.99", PeriodUnit.YEAR, trial = 7)
    private val monthly = plan(PlanKind.MONTHLY, "7.99", PeriodUnit.MONTH)
    private val lifetime = plan(PlanKind.LIFETIME, "79.99", null)

    @Test fun labels() {
        assertEquals("$39.99 / year", yearly.priceLabel)
        assertEquals("$79.99", lifetime.priceLabel)
        assertEquals("7-day free trial", yearly.introOfferLabel)
        assertEquals(7, yearly.trialDays)
        assertNull(monthly.introOfferLabel)
    }

    @Test fun ctaFollowsPlanAndEligibility() {
        assertEquals("Try Little Gestures+ Free", PaywallCopy.ctaTitle(yearly, true))
        assertEquals("Get Little Gestures+", PaywallCopy.ctaTitle(monthly, false))
        assertEquals("Unlock Lifetime", PaywallCopy.ctaTitle(lifetime, false))
        assertEquals("Continue", PaywallCopy.ctaTitle(null, false))
    }

    @Test fun disclosuresNameGooglePlay() {
        assertEquals("No payment today. Then $39.99 / year. Cancel anytime in Google Play.", PaywallCopy.ctaSubline(yearly, true))
        assertNull(PaywallCopy.ctaSubline(lifetime, false))
        assertNull(PaywallCopy.autoRenewDisclosure(lifetime))
        assertTrue(PaywallCopy.autoRenewDisclosure(monthly)!!.contains("Google Play"))
        assertEquals(
            "No payment today. Free for 7 days, then $39.99 / year. Cancel anytime in Google Play.",
            PaywallCopy.trialBillingDisclosure(yearly.introOfferLabel, yearly.priceLabel),
        )
    }

    @Test fun nonTrialDisclosureDoesNotImplyDeferredBilling() {
        val disclosure = PaywallCopy.trialBillingDisclosure(null, yearly.priceLabel)!!
        assertFalse(disclosure.contains("Then"))
        assertFalse(disclosure.contains("No payment today"))
        assertTrue(disclosure.contains("Payment is charged"))
    }

    @Test fun yearlyBadgeShowsTheSavingAgainstMonthly() {
        assertEquals("SAVE 58%", PaywallCopy.badge(yearly, monthly))
        assertEquals("BEST VALUE", PaywallCopy.badge(yearly, null))
        assertNull(PaywallCopy.badge(monthly, monthly))
    }

    @Test fun trialCopy() {
        assertEquals("1 day", PaywallCopy.trialPeriodPhrase("1-day free trial"))
        assertEquals("Turn intentions into actions.", PaywallCopy.trialHeadline("7-day free trial"))
        assertEquals("Unlock Little Gestures+", PaywallCopy.trialCtaTitle(null))
        assertEquals("7-Day Free Trial", PaywallCopy.capitalized("7-day free trial"))
    }

    @Test fun planKindsSortLifetimeYearlyMonthly() {
        assertEquals(PlanKind.YEARLY, PlanInfo.kindFor("CUSTOM", "\$rc_annual", "yearly:yearly"))
        assertEquals(PlanKind.LIFETIME, PlanInfo.kindFor("LIFETIME", "x", "y"))
        assertEquals(listOf(PlanKind.LIFETIME, PlanKind.YEARLY, PlanKind.MONTHLY), PlanInfo.sorted(listOf(monthly, yearly, lifetime)).map { it.kind })
    }
}

class ReviewTrackerTests {
    private val start = Instant.parse("2026-10-01T17:00:00Z")
    private val clock = AppClock(Clock.fixed(start, ZoneOffset.UTC))
    private val store = InMemoryStore()
    private val tracker = ReviewPromptTracker(store, clock, debug = false)

    private fun qualify() {
        repeat(5) { tracker.recordAppLaunch() }
        repeat(3) { tracker.recordPositiveMoment() }
        clock.clock = Clock.fixed(start.plusMillis(7 * DAY_MS), ZoneOffset.UTC)
    }

    @Test fun asksOnlyAfterLaunchesDaysAndMoments() {
        repeat(5) { tracker.recordAppLaunch() }
        repeat(3) { tracker.recordPositiveMoment() }
        assertFalse(tracker.shouldShowAfterPositiveMoment(true))
        clock.clock = Clock.fixed(start.plusMillis(7 * DAY_MS), ZoneOffset.UTC)
        assertTrue(tracker.shouldShowAfterPositiveMoment(true))
        assertFalse(tracker.shouldShowAfterPositiveMoment(false))
    }

    @Test fun cooldownAfterShowing() {
        qualify()
        tracker.markShown()
        tracker.recordPositiveMoment()
        assertFalse(tracker.shouldShowAfterPositiveMoment(true))
        clock.clock = Clock.fixed(start.plusMillis((7 + 120) * DAY_MS), ZoneOffset.UTC)
        assertTrue(tracker.shouldShowAfterPositiveMoment(true))
    }

    @Test fun feedbackOrRatingEndsTheAsks() {
        qualify()
        tracker.markFeedbackSubmitted()
        tracker.recordPositiveMoment()
        clock.clock = Clock.fixed(start.plusMillis(400 * DAY_MS), ZoneOffset.UTC)
        assertFalse(tracker.shouldShowAfterPositiveMoment(true))
    }

    @Test fun automationRunsNeverAsk() {
        qualify()
        tracker.isAutomationRun = true
        assertFalse(tracker.shouldShowAfterPositiveMoment(true))
    }

    @Test fun reviewerCodeUnlocksOnlyWithTheRightCode() {
        val digest = MessageDigest.getInstance("SHA-256").digest("open-sesame".toByteArray()).joinToString("") { "%02x".format(it) }
        val access = ReviewAccess(store, digest)
        assertFalse(access.activate("wrong"))
        assertFalse(access.isGranted)
        assertTrue(access.activate(" open-sesame "))
        assertTrue(access.isGranted)
        assertFalse(ReviewAccess(InMemoryStore(), "").activate("open-sesame"))
    }
}

class PairingLinkTests {
    @Test fun parsesBothLinkForms() {
        assertEquals("ABC234", PairingService.parseInviteCode("https://jackwallner.com/pair/abc234"))
        assertEquals("ABC234", PairingService.parseInviteCode("bond://pair/ABC234"))
        assertNull(PairingService.parseInviteCode("https://example.com/pair/ABC234"))
        assertNull(PairingService.parseInviteCode("https://jackwallner.com/pair"))
    }

    @Test fun newCodesUseTheUnambiguousAlphabet() {
        repeat(50) {
            val code = PairingService.newInviteCode()
            assertEquals(6, code.length)
            assertTrue(code.all { it in PairingService.INVITE_ALPHABET })
        }
        assertEquals("https://jackwallner.com/pair/ABC234", PairingService.inviteUrl("ABC234"))
    }

    @Test fun rpcErrorsBecomeActionableCopy() {
        assertTrue(PairingService.friendlyPairingError("invalid or expired code").startsWith("That code didn't work"))
        assertTrue(PairingService.friendlyPairingError("cannot pair with yourself").startsWith("That's your own code"))
        assertEquals("Pairing didn't work. Check the code and try again.", PairingService.friendlyPairingError(null))
    }
}

class SchedulerTests {
    private class FakePlatform : AlarmPlatform {
        val armed = mutableMapOf<String, NotificationSpec>()
        override fun canNotify() = true
        override fun arm(spec: NotificationSpec) { armed[spec.id] = spec }
        override fun cancel(id: String) { armed.remove(id) }
    }

    private val platform = FakePlatform()
    private var now = at(2026, 10, 18, 12)
    private val scheduler = AlarmNotificationScheduler(platform, InMemoryStore(), { now }, { LA })
    private val me = UUID.randomUUID()

    @Test fun reminderChurnLeavesMilestonesAlone() {
        val m = MilestoneDto(UUID.randomUUID(), UUID.randomUUID(), "birthday", "Sam", LocalDate.of(2000, 12, 1), true)
        scheduler.rescheduleMilestones(listOf(m))
        scheduler.reschedule(me, listOf(reminder("one_time", fireAt = at(2026, 10, 19, 9), authorId = me)), emptyList())
        scheduler.reschedule(me, emptyList(), emptyList())
        assertEquals(3, platform.armed.size)
        assertTrue(platform.armed.keys.all { it.startsWith("milestone.") })
    }

    @Test fun deliveredRecurringRearmsForItsNextMatch() {
        val r = reminder("recurring", fireAt = at(2026, 1, 1, 9), rrule = "FREQ=DAILY", authorId = me)
        scheduler.reschedule(me, listOf(r), emptyList())
        assertEquals(at(2026, 10, 19, 9), platform.armed[r.id.toString()]?.fireAt)
        now = at(2026, 10, 19, 9)
        scheduler.markDelivered(r.id.toString())
        assertEquals(at(2026, 10, 20, 9), scheduler.spec(r.id.toString())?.fireAt)
    }

    @Test fun deliveredOneShotIsSpentAndRearmDropsThePast() {
        val r = reminder("one_time", fireAt = at(2026, 10, 19, 9), authorId = me)
        val later = reminder("one_time", fireAt = at(2026, 10, 25, 9), authorId = me)
        scheduler.reschedule(me, listOf(r, later), emptyList())
        scheduler.markDelivered(r.id.toString())
        assertNull(scheduler.spec(r.id.toString()))
        now = at(2026, 10, 26)
        scheduler.rearmAll()
        assertTrue(scheduler.pendingSpecs().isEmpty())
    }

    @Test fun specsSurviveTheirJsonForm() {
        val spec = NotificationSpec("x", "Title", null, at(2026, 10, 19, 9), UUID.randomUUID(), RecurrencePreset.MONTHLY, at(2026, 1, 19, 9))
        assertEquals(spec, AlarmNotificationScheduler.parse(AlarmNotificationScheduler.json(spec)))
        assertNotNull(AlarmNotificationScheduler.parse(AlarmNotificationScheduler.json(spec.copy(reminderId = null, repeat = null, anchor = null))))
    }
}

class OnboardingPurchaseTests {
    @Test fun pendingPurchaseStaysInOnboardingWithoutPremium() = runTest {
        var restored = false
        val completed = resolveOnboardingPurchase(PurchaseOutcome.PENDING, { false }, { restored = true })
        assertTrue(restored)
        assertFalse(completed)
    }

    @Test fun pendingPurchaseCompletesOnlyAfterRestoreUnlocksPremium() = runTest {
        var premium = false
        assertTrue(resolveOnboardingPurchase(PurchaseOutcome.PENDING, { premium }, { premium = true }))
    }

    @Test fun cancellationDoesNotFinishOrRestore() = runTest {
        var restored = false
        assertFalse(resolveOnboardingPurchase(PurchaseOutcome.CANCELLED, { true }, { restored = true }))
        assertFalse(restored)
    }

    @Test fun purchasedStillRequiresPremium() = runTest {
        assertFalse(resolveOnboardingPurchase(PurchaseOutcome.PURCHASED, { false }, {}))
        assertTrue(resolveOnboardingPurchase(PurchaseOutcome.PURCHASED, { true }, {}))
    }
}
