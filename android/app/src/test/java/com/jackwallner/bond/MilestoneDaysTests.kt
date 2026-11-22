package com.jackwallner.bond

import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.NotificationPlanner
import com.jackwallner.bond.model.daysUntilNextOccurrence
import com.jackwallner.bond.model.nextOccurrence
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

// iOS 9bf1e4f: a milestone's own day is still "today" from 00:01 on, and the countdown counts calendar days.
class MilestoneDaysTests {
    private fun milestone(date: LocalDate, recur: Boolean = true) =
        MilestoneDto(UUID.randomUUID(), UUID.randomUUID(), "anniversary", "Ours", date, recur)

    @Test fun theMilestoneDayItselfStaysToday_afterMidnight() {
        val m = milestone(LocalDate.of(2000, 7, 4))
        assertEquals(LocalDate.of(2026, 7, 4), m.nextOccurrence(at(2026, 7, 4, 0, 1), LA))
        assertEquals(LocalDate.of(2026, 7, 4), m.nextOccurrence(at(2026, 7, 4, 23, 59), LA))
    }

    @Test fun theDayAfterRollsToNextYear() {
        val m = milestone(LocalDate.of(2000, 7, 4))
        assertEquals(LocalDate.of(2027, 7, 4), m.nextOccurrence(at(2026, 7, 5, 0, 1), LA))
    }

    @Test fun aRescheduleOnTheMorningOfKeepsTheNinePingForToday() {
        val m = milestone(LocalDate.of(2000, 7, 4))
        val specs = NotificationPlanner.milestoneSpecs(listOf(m), at(2026, 7, 4, 0, 30), LA)
        assertEquals(listOf("milestone.${m.id}.0"), specs.map { it.id })
        assertEquals(at(2026, 7, 4, 9), specs.single().fireAt)
    }

    @Test fun aFeb29BirthdayStaysOnMar1OnTheDayItself() {
        val m = milestone(LocalDate.of(2020, 2, 29))
        assertEquals(LocalDate.of(2023, 3, 1), m.nextOccurrence(at(2023, 3, 1, 0, 1), LA))
    }

    @Test fun theCountdownIsWholeCalendarDays() {
        val m = milestone(LocalDate.of(2000, 7, 4))
        assertEquals(0L, m.daysUntilNextOccurrence(at(2026, 7, 4, 0, 1), LA))
        assertEquals(0L, m.daysUntilNextOccurrence(at(2026, 7, 4, 23, 59), LA))
        assertEquals(1L, m.daysUntilNextOccurrence(at(2026, 7, 3, 0, 1), LA))
        assertEquals(1L, m.daysUntilNextOccurrence(at(2026, 7, 3, 23, 59), LA))
        assertEquals(364L, m.daysUntilNextOccurrence(at(2026, 7, 5, 12), LA))
    }

    @Test fun theCountdownIgnoresTheSpringForwardHour() {
        // 2026-03-08 has 23 hours in Los Angeles: elapsed time from Mar 7 20:00 to Mar 9 is 28 hours.
        val m = milestone(LocalDate.of(2000, 3, 9))
        assertEquals(2L, m.daysUntilNextOccurrence(at(2026, 3, 7, 20), LA))
        assertEquals(1L, m.daysUntilNextOccurrence(at(2026, 3, 8, 23, 30), LA))
    }

    @Test fun theCountdownIgnoresTheFallBackHour() {
        // 2026-11-01 has 25 hours.
        val m = milestone(LocalDate.of(2000, 11, 2))
        assertEquals(1L, m.daysUntilNextOccurrence(at(2026, 11, 1, 0, 30), LA))
        assertEquals(2L, m.daysUntilNextOccurrence(at(2026, 10, 31, 0, 30), LA))
    }

    @Test fun aOneOffMilestoneInThePastCountsZero() {
        assertEquals(0L, milestone(LocalDate.of(2020, 1, 1), recur = false).daysUntilNextOccurrence(at(2026, 7, 4), LA))
    }
}
