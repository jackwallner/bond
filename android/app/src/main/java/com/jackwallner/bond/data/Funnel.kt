package com.jackwallner.bond.data

import java.time.Instant

object StoreLinks {
    const val PACKAGE = "com.jackwallner.bond"
    const val PLAY_LISTING_URL = "https://play.google.com/store/apps/details?id=$PACKAGE"
    const val PLAY_MARKET_URI = "market://details?id=$PACKAGE"
    const val FEEDBACK_EMAIL = "jackwallner+b@gmail.com"
    const val PRIVACY_URL = "https://jackwallner.github.io/bond/privacy"
    const val TERMS_URL = "https://jackwallner.github.io/bond/terms"
    const val REPORT_CONCERN_URI = "mailto:$FEEDBACK_EMAIL?subject=Report%20a%20concern%20about%20my%20Bond%20partner"
    const val SUPPORT_URI = "mailto:$FEEDBACK_EMAIL"

    fun manageSubscriptionURL(productId: String?): String =
        if (productId == null) "https://play.google.com/store/account/subscriptions"
        else "https://play.google.com/store/account/subscriptions?sku=$productId&package=$PACKAGE"

    /** `ReviewPromptSheet.feedbackMailURL`: a draft to the developer, subject fixed. */
    fun feedbackMailUri(body: String): String =
        "mailto:$FEEDBACK_EMAIL?subject=${encode("Little Gestures feedback")}&body=${encode(body)}"

    private fun encode(value: String): String =
        java.net.URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
}

/**
 * `ReviewPromptTracker.swift` with Bond's numbers: after a completed reminder,
 * Google Play's in-app review card may open once setup is done, from the fifth
 * launch (second in debug), seven days after first open, after three positive
 * moments, and at most every 120 days. Rating on the listing or sending
 * feedback ends the asks, as on iOS. No question comes before the card.
 */
class ReviewPromptTracker(
    private val defaults: KeyValueStore,
    private val clock: AppClock,
    private val debug: Boolean,
) {
    /** Tests and screenshot runs never trigger the store card. */
    var isAutomationRun = false

    val minimumLaunchCount: Int get() = if (debug) 2 else 5
    val launchCount: Int get() = maxOf(defaults.getInt(Keys.LAUNCH_COUNT), 0)
    val positiveMomentCount: Int get() = maxOf(defaults.getInt(Keys.POSITIVE_MOMENTS), 0)
    val outcome: String? get() = defaults.getString(Keys.OUTCOME)
    val hasPendingPositiveMoment: Boolean get() = defaults.getBoolean(Keys.PENDING)

    fun recordAppLaunch() {
        if (!defaults.contains(Keys.FIRST_OPEN)) defaults.putLong(Keys.FIRST_OPEN, clock.millis())
        defaults.putInt(Keys.LAUNCH_COUNT, launchCount + 1)
    }

    fun recordPositiveMoment() {
        defaults.putInt(Keys.POSITIVE_MOMENTS, positiveMomentCount + 1)
        defaults.putBoolean(Keys.PENDING, true)
    }

    fun passivePromptAllowed(): Boolean {
        if (outcome != null) return false
        if (!defaults.contains(Keys.LAST_SHOWN)) return true
        return clock.millis() - defaults.getLong(Keys.LAST_SHOWN) >= COOLDOWN_DAYS * DAY_MS
    }

    fun canPresentRatingPrompt(hasCompletedSetup: Boolean): Boolean {
        if (isAutomationRun || !hasCompletedSetup) return false
        if (!passivePromptAllowed()) return false
        if (launchCount < minimumLaunchCount) return false
        if (positiveMomentCount < MINIMUM_POSITIVE_MOMENTS) return false
        if (!defaults.contains(Keys.FIRST_OPEN)) return false
        return clock.millis() - defaults.getLong(Keys.FIRST_OPEN) >= MINIMUM_DAYS_SINCE_FIRST_OPEN * DAY_MS
    }

    fun shouldShowAfterPositiveMoment(hasCompletedSetup: Boolean): Boolean =
        hasPendingPositiveMoment && canPresentRatingPrompt(hasCompletedSetup)

    /** Spent when requested: Play may show nothing (quota) and there is no answer to wait for. */
    fun markShown() {
        defaults.putLong(Keys.LAST_SHOWN, clock.millis())
        defaults.putBoolean(Keys.PENDING, false)
    }

    fun markOpenedWriteReview() {
        defaults.putString(Keys.OUTCOME, "openedWriteReview")
        markShown()
    }

    fun markFeedbackSubmitted() {
        defaults.putString(Keys.OUTCOME, "submittedFeedback")
        markShown()
    }

    companion object {
        const val MINIMUM_DAYS_SINCE_FIRST_OPEN = 7L
        const val MINIMUM_POSITIVE_MOMENTS = 3
        const val COOLDOWN_DAYS = 120L
    }

    private object Keys {
        const val LAUNCH_COUNT = "reviewPrompt.appLaunchCount"
        const val FIRST_OPEN = "reviewPrompt.firstAppOpenDate"
        const val LAST_SHOWN = "reviewPrompt.lastShownDate"
        const val OUTCOME = "reviewPrompt.outcome"
        const val POSITIVE_MOMENTS = "reviewPrompt.positiveMomentCount"
        const val PENDING = "reviewPrompt.pendingPositiveMoment"
    }
}

/**
 * On-device record of how someone met Little Gestures+ before buying, mirrored
 * onto the RevenueCat customer as attributes (`ConversionDiagnostics.swift`).
 * Counts, dates and surface names only.
 */
class ConversionDiagnostics(private val defaults: KeyValueStore, private val clock: AppClock) {
    fun recordAppOpen() {
        if (!defaults.contains(INSTALLED_AT)) defaults.putLong(INSTALLED_AT, clock.millis())
        defaults.putInt(APP_OPENS, defaults.getInt(APP_OPENS) + 1)
    }

    fun recordPitchView(impressionId: String) {
        val surface = impressionId.removePrefix(PREFIX)
        defaults.putInt(TOTAL_VIEWS, defaults.getInt(TOTAL_VIEWS) + 1)
        defaults.putInt(views(surface), defaults.getInt(views(surface)) + 1)
        defaults.putString(LAST_SURFACE, surface)
        if (!defaults.contains(FIRST_SEEN)) {
            defaults.putLong(FIRST_SEEN, clock.millis())
            defaults.putInt(OPENS_BEFORE_FIRST_PITCH, defaults.getInt(APP_OPENS))
            if (defaults.contains(INSTALLED_AT)) defaults.putInt(DAYS_TO_FIRST_PITCH, daysSince(defaults.getLong(INSTALLED_AT)))
        }
    }

    /** Only the first conversion is recorded. */
    fun recordConversion(plan: String, startedTrial: Boolean, offeringId: String? = null) {
        if (defaults.contains(CONVERTED_ON)) return
        defaults.putString(CONVERTED_ON, defaults.getString(LAST_SURFACE) ?: "unknown")
        defaults.putInt(VIEWS_AT_CONVERT, defaults.getInt(TOTAL_VIEWS))
        defaults.putString(CONVERTED_PLAN, plan)
        defaults.putBoolean(CONVERTED_WITH_TRIAL, startedTrial)
        defaults.putLong(CONVERTED_AT, clock.millis())
        offeringId?.let { defaults.putString(CONVERTED_OFFERING, it) }
        if (defaults.contains(FIRST_SEEN)) defaults.putInt(DAYS_TO_CONVERT, daysSince(defaults.getLong(FIRST_SEEN)))
    }

    /** Empty until the first pitch. Keys stay under RevenueCat's 40-character limit. */
    val subscriberAttributes: Map<String, String>
        get() {
            val total = defaults.getInt(TOTAL_VIEWS)
            if (total <= 0) return emptyMap()
            val attributes = mutableMapOf("pitch_views_total" to total.toString())
            for (key in defaults.keys()) {
                if (!key.startsWith(VIEWS_PREFIX) || key == TOTAL_VIEWS) continue
                val count = defaults.getInt(key)
                if (count > 0) attributes["pitch_views_${key.removePrefix(VIEWS_PREFIX)}".take(40)] = count.toString()
            }
            defaults.getString(LAST_SURFACE)?.let { attributes["pitch_last"] = it }
            if (defaults.contains(FIRST_SEEN)) {
                val first = defaults.getLong(FIRST_SEEN)
                attributes["pitch_first_seen"] = Instant.ofEpochMilli(first).toString()
                attributes["days_since_first_pitch"] = daysSince(first).toString()
            }
            if (defaults.contains(DAYS_TO_FIRST_PITCH)) attributes["days_since_install"] = defaults.getInt(DAYS_TO_FIRST_PITCH).toString()
            if (defaults.contains(OPENS_BEFORE_FIRST_PITCH)) attributes["opens_before_first_pitch"] = defaults.getInt(OPENS_BEFORE_FIRST_PITCH).toString()
            defaults.getString(CONVERTED_ON)?.let { convertedOn ->
                attributes["converted_surface"] = convertedOn
                attributes["converted_at"] = Instant.ofEpochMilli(defaults.getLong(CONVERTED_AT)).toString()
                attributes["pitch_views_at_convert"] = defaults.getInt(VIEWS_AT_CONVERT).toString()
                attributes["days_to_convert"] = defaults.getInt(DAYS_TO_CONVERT).toString()
                attributes["converted_plan"] = defaults.getString(CONVERTED_PLAN) ?: "unknown"
                attributes["converted_with_trial"] = if (defaults.getBoolean(CONVERTED_WITH_TRIAL)) "true" else "false"
                defaults.getString(CONVERTED_OFFERING)?.let { attributes["converted_offering"] = it }
            }
            return attributes
        }

    private fun daysSince(millis: Long): Int = maxOf(0, ((clock.millis() - millis) / DAY_MS).toInt())

    private fun views(surface: String) = "$VIEWS_PREFIX$surface"

    private companion object {
        const val PREFIX = "bond_"
        const val VIEWS_PREFIX = "conv.pitchViews."
        const val TOTAL_VIEWS = "conv.pitchViews.total"
        const val FIRST_SEEN = "conv.pitchFirstSeen"
        const val LAST_SURFACE = "conv.pitchLastSurface"
        const val INSTALLED_AT = "conv.installedAt"
        const val APP_OPENS = "conv.appOpens"
        const val OPENS_BEFORE_FIRST_PITCH = "conv.opensBeforeFirstPitch"
        const val DAYS_TO_FIRST_PITCH = "conv.daysToFirstPitch"
        const val CONVERTED_ON = "conv.convertedOn"
        const val CONVERTED_AT = "conv.convertedAt"
        const val VIEWS_AT_CONVERT = "conv.viewsAtConvert"
        const val DAYS_TO_CONVERT = "conv.daysToConvert"
        const val CONVERTED_PLAN = "conv.convertedPlan"
        const val CONVERTED_WITH_TRIAL = "conv.convertedWithTrial"
        const val CONVERTED_OFFERING = "conv.convertedOffering"
    }
}
