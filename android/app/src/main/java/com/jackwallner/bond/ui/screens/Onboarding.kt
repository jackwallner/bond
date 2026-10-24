package com.jackwallner.bond.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Drafts
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.data.Membership
import com.jackwallner.bond.data.PaywallCopy
import com.jackwallner.bond.data.PlanKind
import com.jackwallner.bond.data.PurchaseException
import com.jackwallner.bond.data.PurchaseOutcome
import com.jackwallner.bond.data.StoreLinks
import com.jackwallner.bond.data.resolveOnboardingPurchase
import com.jackwallner.bond.model.FocusArea
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.ChoiceCard
import com.jackwallner.bond.ui.components.Detent
import com.jackwallner.bond.ui.components.InlineError
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.ScreenHeader
import com.jackwallner.bond.ui.components.TextLink
import com.jackwallner.bond.ui.components.VSpace
import com.jackwallner.bond.ui.components.icon
import com.jackwallner.bond.ui.currentActivity
import com.jackwallner.bond.ui.openLink
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Radius
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import com.jackwallner.bond.ui.theme.semibold
import com.jackwallner.bond.ui.theme.weight
import java.time.Instant
import kotlinx.coroutines.launch

val FocusArea.icon: ImageVector
    get() = when (this) {
        FocusArea.GESTURES -> Icons.Rounded.Favorite
        FocusArea.DATES -> Icons.Rounded.CalendarMonth
        FocusArea.LOVES -> Icons.Rounded.AutoAwesome
        FocusArea.AVOID -> Icons.Rounded.Warning
    }

enum class IntentMode { SOLO, INVITEE }

private const val TRIAL_STEP = 4

/**
 * `IntentSetupView.swift`: their name, a commitment, their love languages and
 * what to remember, then the one-tap trial page. The invitee intake starts at
 * the love-language step and finishes after focus areas.
 */
@Composable
fun IntentSetupScreen(mode: IntentMode) {
    val graph = LocalGraph.current
    val prefs = graph.prefs
    val pairing = graph.pairing
    val store = graph.subscriptions
    val sheets = LocalSheets.current
    val haptics = LocalHapticFeedback.current
    val focusManager = LocalFocusManager.current
    val context = LocalContext.current
    val activity = currentActivity()
    val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(if (mode == IntentMode.INVITEE) 2 else 0) }
    var name by remember { mutableStateOf(prefs.partnerName) }
    var isFinishing by remember { mutableStateOf(false) }
    var isPurchasing by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var isPendingPurchase by remember { mutableStateOf(false) }
    var purchaseError by remember { mutableStateOf<String?>(null) }

    val trimmed = name.trim()
    val displayName = trimmed.ifEmpty { "them" }
    val trialPlan = store.plans.firstOrNull { it.kind == PlanKind.YEARLY } ?: store.plans.firstOrNull()
    val introEligible = trialPlan?.let { store.isEligibleForIntroOffer(it) } ?: false
    val isTrialStep = step == TRIAL_STEP

    LaunchedEffect(Unit) {
        pairing.lastError = null
        if (store.plans.isEmpty()) store.fetchProducts()
    }

    suspend fun finish() {
        if (isFinishing) return
        when (mode) {
            IntentMode.SOLO -> {
                isFinishing = true
                if (pairing.coupleId == null) pairing.createSoloCouple()
                isFinishing = false
            }
            IntentMode.INVITEE -> prefs.markCommitted(Instant.now())
        }
    }

    LaunchedEffect(store.isPremium, isPendingPurchase, isPurchasing, isRestoring) {
        if (isTrialStep && isPendingPurchase && store.isPremium && !isPurchasing && !isRestoring) finish()
    }

    fun openFallbackPaywall() {
        sheets.present("paywall", Detent.LARGE, onDismiss = { scope.launch { finish() } }) { dismiss ->
            PaywallFlow("onboarding_trial_fallback", onClose = dismiss)
        }
    }

    fun advance() {
        when (step) {
            0 -> {
                prefs.updatePartnerName(trimmed)
                focusManager.clearFocus()
                step = 1
            }
            1 -> {
                prefs.markCommitted(Instant.now())
                haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                step = 2
            }
            2 -> step = 3
            3 -> if (mode == IntentMode.INVITEE) {
                scope.launch { finish() }
            } else {
                // Seeing this page counts as the post-onboarding offer, bought or not.
                graph.flags.hasShownPostOnboardingPaywall = true
                store.trackPaywallImpression("onboarding_personalized_plan", oncePerSession = true)
                purchaseError = null
                step = TRIAL_STEP
            }
            else -> {
                val plan = trialPlan
                if (plan == null || activity == null) {
                    openFallbackPaywall()
                } else {
                    purchaseError = null
                    isPurchasing = true
                    scope.launch {
                        try {
                            val result = store.purchase(activity, plan)
                            if (result == PurchaseOutcome.PENDING) {
                                isPendingPurchase = true
                                purchaseError = "Finalizing your purchase…"
                            }
                            if (resolveOnboardingPurchase(result, { store.isPremium }, { store.restore() })) {
                                finish()
                            } else if (isPendingPurchase) {
                                purchaseError = "Your payment went through but we're still syncing it. Tap Restore Purchases to finish unlocking."
                            }
                        } catch (e: PurchaseException) {
                            purchaseError = store.lastError ?: e.message ?: "Couldn't complete the purchase. Please try again."
                        } finally {
                            isPurchasing = false
                        }
                    }
                }
            }
        }
    }

    val canContinue = when (step) {
        0 -> trimmed.isNotEmpty()
        3 -> prefs.focusAreas.isNotEmpty()
        else -> true
    }
    val continueTitle = when (step) {
        0, 2 -> "Continue"
        1 -> "I commit to showing up for $displayName"
        3 -> "Start using Little Gestures"
        else -> when {
            isPendingPurchase -> "Purchase pending"
            introEligible -> "Try ${Membership.PLUS} Free"
            else -> "Get ${Membership.PLUS}"
        }
    }

    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding().testTag("intent.step$step")) {
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(top = Spacing.xxxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            AnimatedContent(step, transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(250)) }, label = "step") { current ->
                when (current) {
                    0 -> NameStep(name, onChange = { name = it }, onSubmit = { if (trimmed.isNotEmpty()) advance() }, onInvite = {
                        focusManager.clearFocus()
                        sheets.present("pairing") { dismiss -> PairingSheet(PairMode.RECEIVE, onClose = dismiss) }
                    })
                    1 -> CommitStep(displayName)
                    2 -> LoveLanguageStep(displayName)
                    3 -> FocusAreasStep(displayName)
                    else -> TrialStepContent(displayName, introEligible && trialPlan?.trialDays != null)
                }
            }
            pairing.lastError?.let { InlineError(it) }
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.base).padding(bottom = Spacing.l, top = Spacing.s),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            if (isTrialStep) {
                val disclosure = trialPlan?.let { plan ->
                    val days = plan.trialDays
                    if (introEligible && days != null) {
                        "No payment today. Free for ${if (days == 1) "1 day" else "$days days"}, then ${plan.priceLabel}. Cancel anytime in Google Play."
                    } else {
                        "${plan.priceLabel}. Renews automatically until you cancel in Google Play."
                    }
                }
                disclosure?.let { BText(it, BondType.caption2, Bond.colors.inkTertiary, align = TextAlign.Center, modifier = Modifier.testTag("intent.trial.disclosure")) }
                purchaseError?.let { BText(it, BondType.caption2, if (isPendingPurchase) Bond.colors.inkSecondary else Bond.colors.danger, align = TextAlign.Center) }
            }
            PrimaryButton(
                continueTitle, enabled = canContinue && !isPurchasing && !isRestoring && !isFinishing && !isPendingPurchase, isLoading = isFinishing || isPurchasing, tag = "intent.continue",
                onClick = ::advance,
            )
            if (isTrialStep) {
                TextLink(
                    "Continue for free", color = Bond.colors.inkSecondary, enabled = !isPurchasing && !isRestoring && !isFinishing,
                    modifier = Modifier.fillMaxWidth(), tag = "intent.continueFree",
                ) { scope.launch { finish() } }
            }
            Box(Modifier.heightIn(min = 44.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (isTrialStep) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        if (isRestoring) {
                            CircularProgressIndicator(color = Bond.colors.accent, modifier = Modifier.size(20.dp))
                        } else {
                            TextLink("Restore Purchases", style = BondType.caption, color = Bond.colors.inkSecondary, enabled = !isPurchasing && !isFinishing) {
                                isRestoring = true
                                scope.launch {
                                    try {
                                        store.restore()
                                        if (store.isPremium) finish()
                                        else purchaseError = store.lastError ?: "No active ${Membership.PLUS} purchase found for this Google account."
                                    } finally {
                                        isRestoring = false
                                    }
                                }
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TextLink("Terms", style = BondType.caption2, color = Bond.colors.inkTertiary) { openLink(context, StoreLinks.TERMS_URL) }
                            BText("·", BondType.caption2, Bond.colors.inkTertiary)
                            TextLink("Privacy", style = BondType.caption2, color = Bond.colors.inkTertiary) { openLink(context, StoreLinks.PRIVACY_URL) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NameStep(name: String, onChange: (String) -> Unit, onSubmit: () -> Unit, onInvite: () -> Unit) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val colors = Bond.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        ScreenHeader(
            "Who do you want to show up for?",
            "Your partner. Little Gestures is built to help you keep showing up for them.",
            Modifier.padding(horizontal = Spacing.base),
        )
        OutlinedTextField(
            value = name,
            onValueChange = onChange,
            placeholder = { Text("Their name", style = BondType.title3, color = colors.inkTertiary) },
            textStyle = BondType.title3.copy(color = colors.ink),
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { onSubmit() }),
            shape = RoundedCornerShape(Radius.inline),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = colors.cardFill, unfocusedContainerColor = colors.cardFill,
                focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent, cursorColor = colors.accent,
            ),
            modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.base).focusRequester(focus).testTag("intent.name"),
        )
        Row(
            Modifier.padding(horizontal = Spacing.base).clip(RoundedCornerShape(8.dp)).clickable(onClick = onInvite).padding(vertical = Spacing.xs)
                .testTag("intent.haveInvite"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Drafts, null, tint = colors.accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(Spacing.s))
            BText("Have an invite from your partner?", BondType.subheadline.weight(FontWeight.Medium), colors.accent)
        }
    }
}

@Composable
private fun CommitStep(displayName: String) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        ScreenHeader(
            "Make it real.",
            "Showing up for $displayName isn't a feature, it's a choice. Make it now, and Little Gestures will help you keep it.",
            Modifier.padding(horizontal = Spacing.base),
        )
        Box(Modifier.fillMaxWidth().padding(vertical = Spacing.l), contentAlignment = Alignment.Center) {
            Box(Modifier.size(96.dp).clip(CircleShape).background(Bond.colors.accent), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Favorite, null, tint = Color.White, modifier = Modifier.size(52.dp))
            }
        }
    }
}

@Composable
private fun LoveLanguageStep(displayName: String) {
    val prefs = LocalGraph.current.prefs
    val colors = Bond.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        ScreenHeader(
            "What lands best with $displayName?",
            "Pick any that fit. Your first choice is their primary, we'll lean toward it.",
            Modifier.padding(horizontal = Spacing.base),
        )
        Column(Modifier.padding(horizontal = Spacing.base), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            LoveLanguage.entries.forEach { lang ->
                val selected = lang in prefs.partnerLoveLanguages
                val primary = prefs.partnerLoveLanguages.firstOrNull() == lang
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.inline)).background(colors.cardFill)
                        .clickable { prefs.toggleLoveLanguage(lang) }.padding(Spacing.base).heightIn(min = 28.dp)
                        .testTag("intent.lang.${lang.raw}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(lang.icon, null, tint = colors.tint(lang), modifier = Modifier.width(28.dp))
                    Spacer(Modifier.width(Spacing.m))
                    BText(lang.title, BondType.headline, modifier = Modifier.weight(1f, fill = false))
                    if (primary) {
                        Spacer(Modifier.width(Spacing.s))
                        Box(Modifier.clip(CircleShape).background(colors.accent.copy(alpha = 0.15f)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                            BText("Primary", BondType.caption2.semibold, colors.accent)
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    if (selected && !primary) {
                        TextLink("Make primary", style = BondType.caption.weight(FontWeight.Medium)) {
                            prefs.setPrimaryLoveLanguage(lang)
                        }
                    }
                    if (selected) Icon(Icons.Rounded.CheckCircle, null, tint = colors.accent)
                }
            }
        }
    }
}

@Composable
private fun FocusAreasStep(displayName: String) {
    val prefs = LocalGraph.current.prefs
    val colors = Bond.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        ScreenHeader(
            "What do you want to remember about $displayName?",
            "Pick what matters. You can change any of this later.",
            Modifier.padding(horizontal = Spacing.base),
        )
        Column(Modifier.padding(horizontal = Spacing.base), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            FocusArea.entries.forEach { area ->
                val on = area in prefs.focusAreas
                ChoiceCard(
                    area.icon, area.title, area.subtitle,
                    tint = if (on) colors.accent else colors.inkSecondary,
                    tag = "intent.area.${area.raw}",
                    trailing = { if (on) Icon(Icons.Rounded.CheckCircle, null, tint = colors.accent) },
                ) { prefs.toggleFocusArea(area) }
            }
        }
    }
}

@Composable
private fun TrialStepContent(displayName: String, offersTrial: Boolean) {
    val colors = Bond.colors
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xl), modifier = Modifier.testTag("intent.trial")) {
        ScreenHeader(
            "Your Little Gestures plan for $displayName.",
            // Google Play gives one trial per account, so the promise follows eligibility.
            if (offersTrial) {
                "Start your free trial to unlock every idea and turn the little things into a habit."
            } else {
                "Unlock every idea and turn the little things into a habit."
            },
            Modifier.padding(horizontal = Spacing.base),
        )
        Column(Modifier.padding(horizontal = Spacing.base), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Verified, null, tint = colors.accent, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(Spacing.xs))
                BText("Chosen for your setup", BondType.subheadline.semibold, colors.accent)
            }
            PlusBenefits.benefits(isSolo = true).take(3).forEach { benefit ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.inline)).background(colors.cardFill).padding(Spacing.base),
                    verticalAlignment = Alignment.Top,
                ) {
                    Box(Modifier.size(32.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                        Icon(benefit.icon, null, tint = colors.accent, modifier = Modifier.size(16.dp))
                    }
                    Spacer(Modifier.width(Spacing.m))
                    Column(Modifier.weight(1f)) {
                        BText(benefit.title, BondType.subheadline.semibold)
                        BText(benefit.detail, BondType.caption, colors.inkSecondary)
                    }
                }
            }
        }
    }
}

/**
 * `InviteWelcomeView.swift`: opened from a partner's invite with no couple yet.
 * Android accepts on the anonymous identity, so there is no Apple sign-in step.
 */
@Composable
fun InviteWelcomeScreen() {
    val pairing = LocalGraph.current.pairing
    val scope = rememberCoroutineScope()
    val colors = Bond.colors
    LaunchedEffect(Unit) { pairing.lastError = null }
    Column(
        Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(vertical = Spacing.xxxl).testTag("inviteWelcome"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            Box(Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)).background(colors.accentGradient), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Favorite, null, tint = Color.White, modifier = Modifier.size(40.dp))
            }
            BText("Your partner invited you", BondType.title.bold, align = TextAlign.Center)
            BText(
                "Little Gestures is a small app for the two of you, little reminders, shared milestones, and a daily check-in.",
                BondType.body, colors.inkSecondary, align = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.xl),
            )
        }
        pairing.deferredInviteCode?.let { CodeCard(it, size = 28) }
        Spacer(Modifier.weight(1f))
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            if (pairing.isPairing) {
                Box(Modifier.height(52.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = colors.accent) }
            } else {
                PrimaryButton("Accept invite", modifier = Modifier.padding(horizontal = Spacing.base), tag = "invite.accept") {
                    scope.launch { pairing.consumeDeferredInviteIfNeeded() }
                }
            }
            pairing.lastError?.let { InlineError(it) }
            TextLink("Set up on my own instead", style = BondType.subheadline.weight(FontWeight.Medium), color = colors.inkSecondary, tag = "invite.solo") {
                pairing.deferredInviteCode = null
                pairing.lastError = null
            }
        }
    }
}

/** `PairingSuccessView.swift`: one beat of weight, then an explicit Continue. */
@Composable
fun PairingSuccessScreen(partnerName: String?, onDone: () -> Unit) {
    val colors = Bond.colors
    var started by remember { mutableStateOf(false) }
    val progress by animateFloatAsState(if (started) 1f else 0f, tween(1200), label = "hearts")
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(Unit) {
        started = true
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
    }
    Column(
        Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().clickable(onClick = onDone).testTag("pairingSuccess"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.height(80.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Favorite, null, tint = colors.gradientEnd, modifier = Modifier.size(52.dp).alpha(progress).scale(0.6f + 0.4f * progress))
            Icon(Icons.Rounded.Favorite, null, tint = colors.accent, modifier = Modifier.size(42.dp).offset(x = (-40 * (1 - progress) - 8).dp))
            Icon(Icons.Rounded.Favorite, null, tint = colors.accent.copy(alpha = 0.7f), modifier = Modifier.size(42.dp).offset(x = (40 * (1 - progress) + 8).dp))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            BText("You're paired.", BondType.largeTitle.bold)
            BText(
                if (!partnerName.isNullOrEmpty()) "You & $partnerName" else "You're paired with someone.",
                BondType.title3, colors.inkSecondary,
            )
        }
        Spacer(Modifier.weight(1f))
        PrimaryButton("Continue", modifier = Modifier.padding(horizontal = Spacing.base), tag = "pairingSuccess.continue", onClick = onDone)
        VSpace(Spacing.xxxl)
    }
}

/** The launch spinner, or "Couldn't connect" once bootstrap settled without a session. */
@Composable
fun LoadingScreen(failed: Boolean, onRetry: () -> Unit) {
    val colors = Bond.colors
    Box(Modifier.fillMaxSize().background(colors.surface), contentAlignment = Alignment.Center) {
        if (!failed) {
            CircularProgressIndicator(color = colors.accent, modifier = Modifier.size(44.dp))
        } else {
            Column(
                Modifier.padding(horizontal = Spacing.xl).testTag("loading.failed"),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.m),
            ) {
                Icon(Icons.Rounded.WifiOff, null, tint = colors.inkSecondary, modifier = Modifier.size(40.dp))
                BText("Couldn't connect", BondType.headline)
                BText(
                    "Little Gestures needs a connection the first time you open it. Check your network and try again.",
                    BondType.subheadline, colors.inkSecondary, align = TextAlign.Center,
                )
                TextLink("Try again", tag = "loading.retry", onClick = onRetry)
            }
        }
    }
}
