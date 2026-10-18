package com.jackwallner.bond

import android.content.Intent
import com.jackwallner.bond.data.Appearance

/**
 * Debug-only launch extras for tests and screenshots, the Android side of the
 * iOS launch arguments. None of this is compiled into a release build.
 *
 *     adb shell am start -n com.jackwallner.bond/.MainActivity \
 *         --ez uiTest true --ez screenshotSeed true --es appearance dark --es tab INSIGHTS
 *
 * Add `--ez seedFree true` for the seeded account on the free tier.
 */
object DebugLaunchOptions {
    fun apply(graph: AppGraph, intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getBoolean("uiTest")) graph.review.isAutomationRun = true
        if (extras.getBoolean("screenshotSeed")) ScreenshotSeed.apply(graph)
        if (extras.getBoolean("forcePro")) graph.subscriptions.forcePremiumForDebug()
        // The seed is a member's account; this shows the same data on the free tier.
        if (extras.getBoolean("seedFree")) graph.subscriptions.forcePremiumForDebug(false)
        extras.getString("appearance")?.let { raw ->
            Appearance.entries.firstOrNull { it.raw == raw }?.let(graph.theme::updateAppearance)
        }
        extras.getString("tab")?.let { graph.initialTab = it }
    }
}
