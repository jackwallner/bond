package com.jackwallner.bond

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.bond.data.AlarmNotificationScheduler
import com.jackwallner.bond.data.AndroidAlarmPlatform
import com.jackwallner.bond.data.AppClock
import com.jackwallner.bond.data.AppFlags
import com.jackwallner.bond.data.AuthService
import com.jackwallner.bond.data.ConversionDiagnostics
import com.jackwallner.bond.data.DailyCheckInService
import com.jackwallner.bond.data.MilestonesService
import com.jackwallner.bond.data.OnboardingPreferences
import com.jackwallner.bond.data.PairingService
import com.jackwallner.bond.data.PermissionBridge
import com.jackwallner.bond.data.ReminderEventRepository
import com.jackwallner.bond.data.ReminderRepository
import com.jackwallner.bond.data.ReviewPromptTracker
import com.jackwallner.bond.data.SeedMode
import com.jackwallner.bond.data.SharedPreferencesStore
import com.jackwallner.bond.data.SubscriptionService
import com.jackwallner.bond.data.SupabaseClient
import com.jackwallner.bond.data.ThemeSettings
import java.util.UUID
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

class BondApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}

/** Every long-lived object the screens share, built once per process (the iOS `@State` services). */
class AppGraph(context: Context) {
    val appContext: Context = context.applicationContext
    val scope = MainScope()
    val clock = AppClock()
    val defaults = SharedPreferencesStore(appContext)
    val seed = SeedMode()
    val client = SupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY, defaults)
    val auth = AuthService(client)
    val prefs = OnboardingPreferences(defaults)
    val theme = ThemeSettings(defaults)
    val flags = AppFlags(defaults)
    val notifications = AlarmNotificationScheduler(AndroidAlarmPlatform(appContext), defaults)
    val permissions = PermissionBridge()
    val pairing = PairingService(client, auth, prefs, seed)
    val reminders = ReminderRepository(client, pairing, seed)
    val events = ReminderEventRepository(client, pairing, seed)
    val milestones = MilestonesService(client, pairing, notifications, seed)
    val checkIn = DailyCheckInService(client, auth, pairing, seed)
    val review = ReviewPromptTracker(defaults, clock, BuildConfig.DEBUG)
    val diagnostics = ConversionDiagnostics(defaults, clock)
    val subscriptions = SubscriptionService(appContext, defaults, diagnostics)

    /** Both auth and the first couple load have settled (`isAppBootstrapped`). */
    var isAppBootstrapped by mutableStateOf(false)
        private set
    /** The first couple read failed with no couple known: show "Couldn't connect", not first-run setup. */
    var initialLoadFailed by mutableStateOf(false)
        private set
    /** A tapped reminder notification, consumed by the Reminders tab (`NotificationRouter`). */
    var pendingReminderId by mutableStateOf<UUID?>(null)
    /** The notification primer question is settled for this launch (`bondNotificationPrimerResolved`). */
    var primerResolved by mutableStateOf(false)
    /** Bumped on each completed reminder or check-in answer (`bondPositiveMomentForReview`). */
    var positiveMoments by mutableIntStateOf(0)
    /** An invite link that arrived before the session was ready. */
    var pendingLink by mutableStateOf<String?>(null)
    /** Debug launch option: the tab MainTabs opens on. */
    var initialTab: String? = null
    /** Bumped on every activity resume, for screens that re-read system state. */
    var resumeTick by mutableIntStateOf(0)

    suspend fun bootstrap() {
        if (seed.enabled) {
            isAppBootstrapped = true
            return
        }
        auth.bootstrap()
        auth.currentUserId?.let { subscriptions.identify(it) }
        scope.launch { subscriptions.bootstrap() }
        val loaded = pairing.loadCouple()
        initialLoadFailed = !loaded && pairing.coupleId == null
        isAppBootstrapped = true
    }

    suspend fun retryBootstrap() {
        isAppBootstrapped = false
        auth.retryBootstrap()
        auth.currentUserId?.let { subscriptions.identify(it) }
        val loaded = pairing.loadCouple()
        initialLoadFailed = !loaded && pairing.coupleId == null
        isAppBootstrapped = true
    }

    fun rescheduleNotifications() {
        if (seed.enabled) return
        val me = auth.currentUserId ?: return
        notifications.reschedule(me, reminders.reminders, events.events)
    }

    /**
     * Settings' Delete account: the server deletes the user (a paired partner
     * keeps the shared couple), then the app returns to first run on a fresh
     * anonymous identity. On-device partner notes go too.
     */
    suspend fun deleteAccount() {
        auth.deleteAccount()
        subscriptions.signOut()
        clearLocalAccountState()
        auth.currentUserId?.let { subscriptions.identify(it) }
        isAppBootstrapped = false
        val loaded = pairing.loadCouple()
        initialLoadFailed = !loaded && pairing.coupleId == null
        isAppBootstrapped = true
    }

    private fun clearLocalAccountState() {
        pairing.reset()
        notifications.clearAll()
        reminders.reminders = emptyList()
        events.events = emptyList()
        milestones.milestones = emptyList()
        checkIn.reset()
        prefs.reset()
        listOf("hasShownPostPairPaywall", "hasShownPostOnboardingPaywall", "pairingNudgeDismissed").forEach(defaults::remove)
    }
}
