package com.jackwallner.bond.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.bond.model.FocusArea
import com.jackwallner.bond.model.LoveLanguage
import java.time.Instant

/**
 * `OnboardingPreferences` on iOS: on-device notes about the partner, captured
 * before pairing exists. Same keys; lists are stored comma-joined to keep order.
 */
class OnboardingPreferences(private val defaults: KeyValueStore) {
    var partnerName by mutableStateOf(defaults.getString(PARTNER_NAME) ?: "")
        private set
    var partnerLoveLanguages by mutableStateOf(readLanguages())
        private set
    var focusAreas by mutableStateOf(readAreas())
        private set
    var committedAt by mutableStateOf(
        if (defaults.contains(COMMITTED_AT)) Instant.ofEpochMilli(defaults.getLong(COMMITTED_AT)) else null,
    )
        private set

    /** The primary love language; words when none was picked. */
    val partnerLoveLanguage: LoveLanguage get() = partnerLoveLanguages.firstOrNull() ?: LoveLanguage.WORDS

    fun updatePartnerName(value: String) {
        partnerName = value
        defaults.putString(PARTNER_NAME, value)
    }

    fun updateLoveLanguages(value: List<LoveLanguage>) {
        partnerLoveLanguages = value
        defaults.putString(LOVE_LANGUAGES, value.joinToString(",") { it.raw })
    }

    fun toggleLoveLanguage(lang: LoveLanguage) {
        val list = partnerLoveLanguages.toMutableList()
        if (!list.remove(lang)) list.add(lang)
        updateLoveLanguages(list)
    }

    fun setPrimaryLoveLanguage(lang: LoveLanguage) {
        updateLoveLanguages(listOf(lang) + partnerLoveLanguages.filter { it != lang })
    }

    fun updateFocusAreas(value: Set<FocusArea>) {
        focusAreas = value
        defaults.putString(FOCUS_AREAS, FocusArea.entries.filter { it in value }.joinToString(",") { it.raw })
    }

    fun toggleFocusArea(area: FocusArea) {
        updateFocusAreas(if (area in focusAreas) focusAreas - area else focusAreas + area)
    }

    fun markCommitted(at: Instant) {
        committedAt = at
        defaults.putLong(COMMITTED_AT, at.toEpochMilli())
    }

    fun reset() {
        listOf(PARTNER_NAME, LOVE_LANGUAGES, FOCUS_AREAS, COMMITTED_AT).forEach(defaults::remove)
        partnerName = ""
        partnerLoveLanguages = emptyList()
        focusAreas = emptySet()
        committedAt = null
    }

    private fun readLanguages(): List<LoveLanguage> =
        defaults.getString(LOVE_LANGUAGES).orEmpty().split(",").mapNotNull { LoveLanguage.fromRaw(it) }

    private fun readAreas(): Set<FocusArea> =
        defaults.getString(FOCUS_AREAS).orEmpty().split(",").mapNotNull { FocusArea.fromRaw(it) }.toSet()

    private companion object {
        const val PARTNER_NAME = "onboarding.partnerName"
        const val LOVE_LANGUAGES = "onboarding.partnerLoveLanguages"
        const val FOCUS_AREAS = "onboarding.focusAreas"
        const val COMMITTED_AT = "onboarding.committedAt"
    }
}

enum class Accent(val raw: String, val title: String) {
    TERRACOTTA("terracotta", "Terracotta"),
    PINK("pink", "Pink"),
}

enum class Appearance(val raw: String, val title: String) {
    SYSTEM("system", "System"),
    LIGHT("light", "Light"),
    DARK("dark", "Dark"),
}

/** `BondTheme`: the Settings accent and light/dark override. */
class ThemeSettings(private val defaults: KeyValueStore) {
    var accent by mutableStateOf(Accent.entries.firstOrNull { it.raw == defaults.getString(ACCENT) } ?: Accent.TERRACOTTA)
        private set
    var appearance by mutableStateOf(
        Appearance.entries.firstOrNull { it.raw == defaults.getString(APPEARANCE) } ?: Appearance.SYSTEM,
    )
        private set

    fun updateAccent(value: Accent) {
        accent = value
        defaults.putString(ACCENT, value.raw)
    }

    fun updateAppearance(value: Appearance) {
        appearance = value
        defaults.putString(APPEARANCE, value.raw)
    }

    private companion object {
        const val ACCENT = "theme.accent"
        const val APPEARANCE = "theme.appearance"
    }
}

/** One-time flags the iOS app keeps in `UserDefaults.standard`. */
class AppFlags(private val defaults: KeyValueStore) {
    var hasShownPostPairPaywall: Boolean
        get() = defaults.getBoolean("hasShownPostPairPaywall")
        set(value) = defaults.putBoolean("hasShownPostPairPaywall", value)
    var hasShownPostOnboardingPaywall: Boolean
        get() = defaults.getBoolean("hasShownPostOnboardingPaywall")
        set(value) = defaults.putBoolean("hasShownPostOnboardingPaywall", value)
    var hasShownNotificationPrimer: Boolean
        get() = defaults.getBoolean("hasShownNotificationPrimer")
        set(value) = defaults.putBoolean("hasShownNotificationPrimer", value)
    var pairingNudgeDismissed: Boolean
        get() = defaults.getBoolean("pairingNudgeDismissed")
        set(value) = defaults.putBoolean("pairingNudgeDismissed", value)

    fun revealShown(day: String): Boolean = defaults.getBoolean("reveal-shown-$day")
    fun markRevealShown(day: String) = defaults.putBoolean("reveal-shown-$day", true)
}
