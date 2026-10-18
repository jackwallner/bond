package com.jackwallner.bond

import com.jackwallner.bond.model.DailyQuestionDto
import com.jackwallner.bond.model.FocusArea
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.ProfileDto
import com.jackwallner.bond.model.QuestionResponseDto
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * `BondScreenshotSeed.swift`: local-only paired data for literal product
 * screenshots and UI tests. Nothing is written to Supabase, and the seed is
 * not compiled into release builds.
 */
object ScreenshotSeed {
    val me: UUID = UUID.fromString("11111111-1111-4111-8111-111111111111")
    val partner: UUID = UUID.fromString("22222222-2222-4222-8222-222222222222")
    val couple: UUID = UUID.fromString("33333333-3333-4333-8333-333333333333")
    private val question: UUID = UUID.fromString("44444444-4444-4444-8444-444444444444")

    fun apply(graph: AppGraph, now: Instant = Instant.now()) {
        graph.seed.enabled = true
        graph.auth.adoptForSeed(me)
        graph.pairing.coupleId = couple
        graph.pairing.partnerProfile = ProfileDto(partner, displayName = "Sam", loveLanguage = "time", createdAt = now)
        graph.pairing.solo = false
        graph.pairing.justPaired = false

        val prefs = graph.prefs
        prefs.updatePartnerName("Sam")
        prefs.updateLoveLanguages(listOf(LoveLanguage.TIME, LoveLanguage.WORDS))
        prefs.updateFocusAreas(setOf(FocusArea.GESTURES, FocusArea.DATES))
        prefs.markCommitted(now)
        graph.flags.hasShownNotificationPrimer = true
        graph.subscriptions.forcePremiumForDebug()
        graph.review.isAutomationRun = true

        val day = 86_400L
        val tomorrow = now.plusSeconds(day)
        val nextWeek = now.plusSeconds(7 * day)
        val rows = listOf(
            ReminderDto(
                UUID.fromString("55555555-5555-4555-8555-555555555551"), couple, me, partner,
                "Tell Sam one thing you appreciate", "A small note goes a long way.", LoveLanguage.WORDS,
                "recurring", tomorrow, "FREQ=DAILY", status = "active", createdAt = now,
            ),
            ReminderDto(
                UUID.fromString("55555555-5555-4555-8555-555555555552"), couple, me, partner,
                "Plan a ten-minute walk together", null, LoveLanguage.TIME,
                "recurring", tomorrow, "FREQ=WEEKLY", status = "active", createdAt = now,
            ),
            ReminderDto(
                UUID.fromString("55555555-5555-4555-8555-555555555553"), couple, partner, me,
                "Bring home their favorite snack", "The little details count.", LoveLanguage.GIFTS,
                "one_time", nextWeek, status = "active", createdAt = now,
            ),
        )
        graph.reminders.reminders = rows
        val today = LocalDate.now()
        graph.milestones.milestones = listOf(
            MilestoneDto(UUID.fromString("66666666-6666-4666-8666-666666666661"), couple, "anniversary", "Our anniversary", today.plusDays(7), true, now),
            MilestoneDto(UUID.fromString("66666666-6666-4666-8666-666666666662"), couple, "birthday", "Sam's birthday", today.plusDays(21), true, now),
            MilestoneDto(UUID.fromString("66666666-6666-4666-8666-666666666663"), couple, "custom", "Weekend away", today.plusDays(35), false, now),
        )
        graph.events.events = listOf(
            ReminderEventDto(UUID.fromString("77777777-7777-4777-8777-777777777771"), rows[0].id, couple, now, now, "heart"),
            ReminderEventDto(UUID.fromString("77777777-7777-4777-8777-777777777772"), rows[1].id, couple, now.minusSeconds(day), now.minusSeconds(day), ""),
        )
        graph.checkIn.todaysQuestion = DailyQuestionDto(question, "What would make today feel a little more connected?", "connection", LoveLanguage.TIME)
        graph.checkIn.myResponse = QuestionResponseDto(
            UUID.fromString("88888888-8888-4888-8888-888888888881"), question, couple, me, "A walk after dinner, just the two of us.", now,
        )
        graph.checkIn.partnerResponse = QuestionResponseDto(
            UUID.fromString("88888888-8888-4888-8888-888888888882"), question, couple, partner, "A quiet coffee and a little time together.", now,
        )
    }
}
