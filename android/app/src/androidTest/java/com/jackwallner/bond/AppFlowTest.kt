package com.jackwallner.bond

import android.content.Intent
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.bond.data.AuthService
import com.jackwallner.bond.data.InMemoryStore
import com.jackwallner.bond.data.OnboardingPreferences
import com.jackwallner.bond.data.PairingService
import com.jackwallner.bond.data.ReminderRepository
import com.jackwallner.bond.data.SeedMode
import com.jackwallner.bond.data.SupabaseClient
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.ReminderDto
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Onboarding, the core reminder loop, the paid boundary, and the live pairing contract, on a device. */
@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null
    private val graph: AppGraph get() = ApplicationProvider.getApplicationContext<BondApplication>().graph

    private fun launch(seed: Boolean, free: Boolean = false, tab: String? = null) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("uiTest", true)
            .putExtra("screenshotSeed", seed)
            .putExtra("seedFree", free)
            .putExtra("appearance", "light")
        tab?.let { intent.putExtra("tab", it) }
        scenario = ActivityScenario.launch(intent)
    }

    @After
    fun tearDown() {
        scenario?.close()
    }

    private fun waitForTag(tag: String, timeout: Long = 30_000) =
        compose.waitUntil(timeout) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun waitForText(text: String, timeout: Long = 30_000) =
        compose.waitUntil(timeout) { compose.onAllNodes(hasText(text, substring = true)).fetchSemanticsNodes().isNotEmpty() }

    /** Waits until exactly one node carries [tag] (transitions briefly show two), then taps it. */
    private fun tap(tag: String) {
        compose.waitUntil(20_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().size == 1 }
        runCatching { compose.onNodeWithTag(tag).performScrollTo() }
        compose.onNodeWithTag(tag).performClick()
        compose.waitForIdle()
    }

    private fun type(tag: String, text: String) {
        waitForTag(tag)
        compose.onNodeWithTag(tag).performTextInput(text)
        compose.waitForIdle()
    }

    @Test
    fun everyTabOpensItsScreen() {
        launch(seed = true)
        waitForTag("screen.reminders")
        waitForText("Tell Sam one thing you appreciate")
        tap("tab.checkIn")
        waitForTag("screen.checkIn")
        tap("tab.milestones")
        waitForTag("screen.milestones")
        waitForText("Our anniversary")
        tap("tab.insights")
        waitForTag("insights.balance")
        tap("tab.settings")
        waitForTag("screen.settings")
        tap("tab.reminders")
        waitForTag("screen.reminders")
    }

    @Test
    fun handlingAPartnerRequestLogsTheGesture() {
        launch(seed = true)
        val title = "Bring home their favorite snack"
        val id = UUID.fromString("55555555-5555-4555-8555-555555555553")
        waitForText("From Sam")
        tap("request.handled")
        compose.waitUntil(10_000) { graph.events.events.any { it.reminderId == id } }
        tap("reminders.handled")
        waitForTag("screen.handled")
        waitForText(title)
    }

    @Test
    fun togglingMyOwnReminderFlipsThisPeriod() {
        launch(seed = true)
        val title = "Plan a ten-minute walk together"
        val id = UUID.fromString("55555555-5555-4555-8555-555555555552")
        val before = graph.events.events.count { it.reminderId == id }
        tap("reminder.toggle.$title")
        // The seed logged it yesterday, so this either completes or un-completes the current week.
        compose.waitUntil(10_000) { graph.events.events.count { it.reminderId == id } != before }
        // A weekly reminder stays on the list either way.
        waitForTag("reminder.row.$title")
    }

    @Test
    fun editorAddsAReminder() {
        launch(seed = true)
        tap("reminders.add")
        waitForTag("editor")
        type("editor.title", "Leave a note in their bag")
        tap("editor.save")
        compose.waitUntil(10_000) { compose.onAllNodes(hasTestTag("editor")).fetchSemanticsNodes().isEmpty() }
        waitForTag("reminder.row.Leave a note in their bag")
        assertTrue(graph.reminders.reminders.any { it.title == "Leave a note in their bag" && it.triggerType == "one_time" })
    }

    @Test
    fun checkInShowsBothAnswers() {
        launch(seed = true, tab = "CHECK_IN")
        waitForTag("checkIn.question")
        waitForText("What would make today feel a little more connected?")
        waitForTag("checkIn.mine")
        waitForTag("checkIn.partner")
    }

    @Test
    fun milestoneEditorAddsAMilestone() {
        launch(seed = true, tab = "MILESTONES")
        tap("milestones.add")
        waitForTag("milestone.editor")
        type("milestone.label", "First date")
        tap("milestone.save")
        waitForTag("milestone.row.First date")
    }

    @Test
    fun freeMembersSeeTheTeasers() {
        launch(seed = true, free = true, tab = "INSIGHTS")
        waitForTag("insights.teaser")
        tap("tab.checkIn")
        waitForTag("checkIn.teaser")
    }

    @Test
    fun freeMembersReachThePaywallWithStorePrices() {
        launch(seed = true, free = true, tab = "SETTINGS")
        tap("settings.tryPlus")
        compose.waitUntil(30_000) {
            listOf("paywall.trial", "paywall.full").any { compose.onAllNodes(hasTestTag(it)).fetchSemanticsNodes().isNotEmpty() }
        }
        compose.waitUntil(30_000) { graph.subscriptions.plans.isNotEmpty() }
        assertEquals(setOf("monthly", "yearly", "lifetime"), graph.subscriptions.plans.map { it.productId.substringBefore(":") }.toSet())
        if (compose.onAllNodes(hasTestTag("paywall.trial")).fetchSemanticsNodes().isNotEmpty()) {
            waitForTag("paywall.trial.disclosure")
            tap("paywall.trial.allPlans")
        }
        // Every Test Store plan renders as a row with its store price.
        graph.subscriptions.plans.forEach { plan ->
            waitForTag("paywall.plan.${plan.kind.name.lowercase()}")
            waitForText(plan.priceLabel)
        }
        waitForText("Restore")
    }

    /** A real first run against Supabase: creates a solo couple, then Delete account returns to first run. */
    @Test
    fun firstRunCreatesASoloCoupleAndDeleteAccountResets() {
        launch(seed = false)
        try {
            waitForTag("intent.step0", 60_000)
            type("intent.name", "Alex")
            tap("intent.continue")
            waitForTag("intent.step1")
            tap("intent.continue")
            waitForTag("intent.step2")
            tap("intent.lang.time")
            tap("intent.continue")
            waitForTag("intent.step3")
            tap("intent.area.gestures")
            tap("intent.continue")
            waitForTag("intent.trial")
            assertTrue(graph.flags.hasShownPostOnboardingPaywall)
            tap("intent.continueFree")
            waitForTag("home", 60_000)
            val me = graph.auth.currentUserId
            assertNotNull(me)
            assertNotNull(graph.pairing.coupleId)
            assertTrue(graph.pairing.solo)
            // Without notification permission the primer shows. The trial page already
            // counted as the post-onboarding offer, so no second paywall follows it.
            waitForTag("primer")
            tap("primer.later")
            assertTrue(graph.primerResolved)
            Thread.sleep(3_000)
            assertTrue(compose.onAllNodes(hasTestTag("sheet.paywall")).fetchSemanticsNodes().isEmpty())
            tap("tab.settings")
            tap("settings.delete")
            tap("confirm.action")
            waitForTag("intent.step0", 60_000)
            assertNotNull(graph.auth.currentUserId)
            assertFalse(graph.auth.currentUserId == me)
            assertEquals(null, graph.pairing.coupleId)
        } finally {
            // Leave nothing behind: whichever identity is signed in now goes too.
            runBlocking {
                graph.auth.currentUserId?.let { id ->
                    runCatching { graph.client.rpc("delete_account", JSONObject().put("p_user", id.toString())) }
                }
                graph.client.clearSession()
            }
        }
    }

    /** Two installs pair through an invite code and share a reminder, on the live project. */
    @Test
    fun twoInstallsPairAndShareAReminder() = runBlocking {
        val seed = SeedMode()
        fun install(): Triple<SupabaseClient, AuthService, PairingService> {
            val client = SupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY, InMemoryStore())
            val auth = AuthService(client)
            return Triple(client, auth, PairingService(client, auth, OnboardingPreferences(InMemoryStore()), seed))
        }
        val (clientA, authA, pairingA) = install()
        val (clientB, authB, pairingB) = install()
        try {
            authA.bootstrap()
            authB.bootstrap()
            val a = requireNotNull(authA.currentUserId)
            val b = requireNotNull(authB.currentUserId)
            pairingA.createSoloCouple()
            assertTrue(pairingA.solo)
            val url = requireNotNull(pairingA.generateInviteCode())
            val code = requireNotNull(PairingService.parseInviteCode(url))
            pairingB.consumeInviteCode(code)
            assertEquals(null, pairingB.lastError)
            assertTrue(pairingB.justPaired)
            assertTrue(pairingA.loadCouple())
            assertEquals(pairingA.coupleId, pairingB.coupleId)
            assertFalse(pairingA.solo)
            assertEquals(b, pairingA.partnerProfile?.id)
            assertEquals(a, pairingB.partnerProfile?.id)

            val couple = requireNotNull(pairingA.coupleId)
            val reminder = ReminderDto(
                UUID.randomUUID(), couple, a, b, "Pick up flowers", null, LoveLanguage.GIFTS,
                "one_time", Instant.now().plusSeconds(86_400), status = "active", createdAt = Instant.now(),
            )
            ReminderRepository(clientA, pairingA, seed).upsert(reminder)
            val inbox = ReminderRepository(clientB, pairingB, seed)
            inbox.refresh()
            assertTrue(inbox.reminders.any { it.id == reminder.id && it.targetId == b })
        } finally {
            listOf(clientA to authA, clientB to authB).forEach { (client, auth) ->
                auth.currentUserId?.let { id ->
                    runCatching { client.rpc("delete_account", JSONObject().put("p_user", id.toString())) }
                    client.clearSession()
                }
            }
        }
    }
}
