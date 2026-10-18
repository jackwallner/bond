package com.jackwallner.bond.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.QuestionAnswer
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.bond.AppGraph
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.SheetController
import com.jackwallner.bond.ui.components.SheetHost
import com.jackwallner.bond.ui.screens.DailyCheckInScreen
import com.jackwallner.bond.ui.screens.InsightsScreen
import com.jackwallner.bond.ui.screens.IntentMode
import com.jackwallner.bond.ui.screens.IntentSetupScreen
import com.jackwallner.bond.ui.screens.InviteWelcomeScreen
import com.jackwallner.bond.ui.screens.LoadingScreen
import com.jackwallner.bond.ui.screens.MilestonesScreen
import com.jackwallner.bond.ui.screens.PairingSuccessScreen
import com.jackwallner.bond.ui.screens.ReminderListScreen
import com.jackwallner.bond.ui.screens.SettingsScreen
import com.jackwallner.bond.ui.screens.presentPaywall
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class Destination { LOADING, INTENT_SETUP, INVITE_WELCOME, INVITEE_INTAKE, PAIRING_SUCCESS, HOME }

/** `RootView.currentDestination`. */
fun AppGraph.destination(): Destination {
    if (!isAppBootstrapped || !auth.isAuthenticated || initialLoadFailed) return Destination.LOADING
    if (seed.enabled) return Destination.HOME
    if (pairing.coupleId == null) {
        return if (pairing.deferredInviteCode != null) Destination.INVITE_WELCOME else Destination.INTENT_SETUP
    }
    if (pairing.justPaired) return Destination.PAIRING_SUCCESS
    // Paired, but this device never captured onboarding preferences: the trimmed intake runs once.
    if (!pairing.solo && prefs.committedAt == null && prefs.focusAreas.isEmpty()) return Destination.INVITEE_INTAKE
    return Destination.HOME
}

/** `RootView`: routing, the two proactive paywalls, and the review card after a positive moment. */
@Composable
fun RootScreen(graph: AppGraph) {
    val sheets = remember { SheetController() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val destination = graph.destination()
    var previous by remember { mutableStateOf(destination) }
    var pendingPostOnboardingPaywall by remember { mutableStateOf(false) }
    var reviewShownThisSession by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { graph.bootstrap() }

    // A tapped invite link waits for the session, then pairs or drives invite-first onboarding.
    LaunchedEffect(graph.isAppBootstrapped, graph.pendingLink) {
        val link = graph.pendingLink ?: return@LaunchedEffect
        if (!graph.isAppBootstrapped) return@LaunchedEffect
        graph.pendingLink = null
        graph.pairing.handleIncomingLink(link)?.let { code -> graph.pairing.consumeInviteCode(code) }
    }

    // Finishing solo setup is the peak-intent moment; wait for the primer so the two don't race.
    LaunchedEffect(destination) {
        if (previous == Destination.INTENT_SETUP && destination == Destination.HOME &&
            !graph.subscriptions.isPremium && !graph.flags.hasShownPostOnboardingPaywall
        ) {
            graph.flags.hasShownPostOnboardingPaywall = true
            pendingPostOnboardingPaywall = true
        }
        previous = destination
    }
    LaunchedEffect(graph.primerResolved, pendingPostOnboardingPaywall) {
        if (!graph.primerResolved || !pendingPostOnboardingPaywall) return@LaunchedEffect
        pendingPostOnboardingPaywall = false
        delay(500)
        sheets.presentPaywall("post_onboarding")
    }

    LaunchedEffect(graph.positiveMoments) {
        if (graph.positiveMoments == 0) return@LaunchedEffect
        fun eligible() = graph.destination() == Destination.HOME && !graph.pairing.justPaired && !reviewShownThisSession &&
            !sheets.isPresented("paywall") &&
            graph.review.shouldShowAfterPositiveMoment(graph.isAppBootstrapped && graph.pairing.coupleId != null)
        if (!eligible()) return@LaunchedEffect
        delay(3_500)
        if (!eligible()) return@LaunchedEffect
        // Google Play's own card, asked of everyone who qualifies. No question first.
        reviewShownThisSession = true
        graph.review.markShown()
        val activity = context.findActivity() ?: return@LaunchedEffect
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
        }
    }

    CompositionLocalProvider(LocalSheets provides sheets) {
        Box(Modifier.fillMaxSize().background(Bond.colors.backgroundGradient)) {
            SheetHost(sheets) {
                AnimatedContent(destination, transitionSpec = { fadeIn(tween(350)) togetherWith fadeOut(tween(350)) }, label = "root") { target ->
                    when (target) {
                        Destination.LOADING -> LoadingScreen(
                            failed = graph.isAppBootstrapped && (!graph.auth.isAuthenticated || graph.initialLoadFailed),
                            onRetry = { scope.launch { graph.retryBootstrap() } },
                        )
                        Destination.INTENT_SETUP -> IntentSetupScreen(IntentMode.SOLO)
                        Destination.INVITE_WELCOME -> InviteWelcomeScreen()
                        Destination.INVITEE_INTAKE -> IntentSetupScreen(IntentMode.INVITEE)
                        Destination.PAIRING_SUCCESS -> PairingSuccessScreen(graph.pairing.partnerProfile?.displayName) {
                            // The headline benefit (Daily Check-In) just became usable: offer it once.
                            if (!graph.subscriptions.isPremium && !graph.flags.hasShownPostPairPaywall) {
                                graph.flags.hasShownPostPairPaywall = true
                                sheets.presentPaywall("post_pairing") { graph.pairing.justPaired = false }
                            } else {
                                graph.pairing.justPaired = false
                            }
                        }
                        Destination.HOME -> MainTabs(graph)
                    }
                }
            }
        }
    }
}

private enum class Tab(val title: String, val icon: ImageVector, val tag: String) {
    REMINDERS("Reminders", Icons.Rounded.Notifications, "tab.reminders"),
    CHECK_IN("Check-In", Icons.Rounded.QuestionAnswer, "tab.checkIn"),
    MILESTONES("Milestones", Icons.Rounded.CalendarMonth, "tab.milestones"),
    INSIGHTS("Insights", Icons.Rounded.BarChart, "tab.insights"),
    SETTINGS("Settings", Icons.Rounded.Settings, "tab.settings"),
}

/** `MainTabView`: every core area is a tab so nothing is buried. */
@Composable
private fun MainTabs(graph: AppGraph) {
    var selection by rememberSaveable { mutableStateOf(graph.initialTab?.let { name -> Tab.entries.firstOrNull { it.name == name } } ?: Tab.REMINDERS) }
    val colors = Bond.colors
    // A tapped reminder notification lands on Reminders, where the list opens its editor.
    LaunchedEffect(graph.pendingReminderId) { if (graph.pendingReminderId != null) selection = Tab.REMINDERS }
    Column(Modifier.fillMaxSize().testTag("home")) {
        Box(Modifier.weight(1f)) {
            when (selection) {
                Tab.REMINDERS -> ReminderListScreen()
                Tab.CHECK_IN -> DailyCheckInScreen()
                Tab.MILESTONES -> MilestonesScreen()
                Tab.INSIGHTS -> InsightsScreen()
                Tab.SETTINGS -> SettingsScreen()
            }
        }
        NavigationBar(containerColor = colors.surfaceElevated, tonalElevation = androidx.compose.ui.unit.Dp(0f)) {
            Tab.entries.forEach { tab ->
                NavigationBarItem(
                    selected = selection == tab,
                    onClick = { selection = tab },
                    icon = { Icon(tab.icon, null) },
                    label = { Text(tab.title, style = BondType.caption2, maxLines = 1) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = colors.accent,
                        selectedTextColor = colors.accent,
                        indicatorColor = colors.accent.copy(alpha = 0.14f),
                        unselectedIconColor = colors.inkSecondary,
                        unselectedTextColor = colors.inkSecondary,
                    ),
                    modifier = Modifier.testTag(tab.tag),
                )
            }
        }
    }
}
