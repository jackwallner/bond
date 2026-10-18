package com.jackwallner.bond

import android.Manifest
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.jackwallner.bond.data.AlarmNotificationScheduler
import com.jackwallner.bond.data.Appearance
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.RootScreen
import com.jackwallner.bond.ui.theme.BondTheme
import java.util.UUID
import kotlinx.coroutines.launch

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as BondApplication).graph

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        graph.permissions.complete(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            graph.review.recordAppLaunch()
            graph.diagnostics.recordAppOpen()
        }
        DebugLaunchOptions.apply(graph, intent)
        graph.permissions.launch = {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                graph.permissions.complete(true)
            }
        }
        AlarmNotificationScheduler.ensureChannel(this)
        if (savedInstanceState == null) handle(intent)
        setContent {
            val theme = graph.theme
            val dark = when (theme.appearance) {
                Appearance.SYSTEM -> isSystemInDarkTheme()
                Appearance.LIGHT -> false
                Appearance.DARK -> true
            }
            LaunchedEffect(dark) {
                val bars = if (dark) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = bars, navigationBarStyle = bars)
            }
            CompositionLocalProvider(LocalGraph provides graph) {
                BondTheme(dark, theme.accent) {
                    // Test tags double as resource ids so UI Automator and screenshot scripts can find controls.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) {
                        RootScreen(graph)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        graph.resumeTick += 1
        if (!graph.isAppBootstrapped || graph.seed.enabled) return
        // Play purchases can take a moment to reach RevenueCat, and a solo user may
        // have been paired while away (there is no realtime feed on Android).
        graph.scope.launch {
            graph.subscriptions.refresh()
            graph.pairing.loadCouple()
            graph.reminders.refresh()
            graph.events.refresh()
            graph.rescheduleNotifications()
        }
    }

    /** Invite links and tapped reminder notifications. */
    private fun handle(intent: Intent?) {
        intent ?: return
        intent.getStringExtra(AlarmNotificationScheduler.EXTRA_REMINDER_ID)?.let { raw ->
            runCatching { UUID.fromString(raw) }.getOrNull()?.let { graph.pendingReminderId = it }
        }
        val link = intent.dataString ?: return
        if (intent.action == Intent.ACTION_VIEW) graph.pendingLink = link
    }
}
