package com.jackwallner.bond.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.bond.data.Membership
import com.jackwallner.bond.data.PaywallCopy
import com.jackwallner.bond.data.PlanInfo
import com.jackwallner.bond.data.PlanKind
import com.jackwallner.bond.data.PurchaseException
import com.jackwallner.bond.data.PurchaseOutcome
import com.jackwallner.bond.data.StoreLinks
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.Detent
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.SheetController
import com.jackwallner.bond.ui.components.TextLink
import com.jackwallner.bond.ui.components.VSpace
import com.jackwallner.bond.ui.currentActivity
import com.jackwallner.bond.ui.openLink
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Radius
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import com.jackwallner.bond.ui.theme.semibold
import kotlinx.coroutines.launch

data class PlusBenefit(val icon: ImageVector, val title: String, val detail: String)

/** `BondPlusBenefits.swift`. */
object PlusBenefits {
    fun benefits(isSolo: Boolean): List<PlusBenefit> = if (isSolo) {
        listOf(
            PlusBenefit(Icons.Rounded.Layers, "Ideas matched to your partner", "Start with prompts based on what matters to them."),
            PlusBenefit(Icons.Rounded.NotificationsActive, "Remember at the right moment", "Schedule thoughtful nudges before the moment passes."),
            PlusBenefit(Icons.Rounded.AutoAwesome, "Learn what lands", "See which love languages you act on over time."),
        )
    } else {
        listOf(
            PlusBenefit(Icons.Rounded.Forum, "Daily Check-In", "One question, together, every day."),
            PlusBenefit(Icons.Rounded.AutoAwesome, "Love-language insights", "Trends from what you both share."),
            // iOS says "Nudge when you're near their spot."; Android has no place
            // reminders, so the surprise benefit names the random window instead.
            PlusBenefit(Icons.Rounded.NotificationsActive, "Surprise reminders", "Nudge at a random moment in a window you pick."),
        )
    }

    fun paywallSubheadline(isSolo: Boolean) =
        if (isSolo) "Turn what matters to your partner into actions you remember."
        else "Stay close on purpose with the full Little Gestures experience."

    fun trialSubheadline(isSolo: Boolean) =
        if (isSolo) "Your personalized plan is ready. No payment today, cancel anytime."
        else "Daily Check-In, insights, and thoughtful reminders. No payment today."
}

/** `.paywallSheet` / `PaywallFlowSheet`: the compact trial offer first, all plans on demand. */
fun SheetController.presentPaywall(impressionId: String = "feature_gate", onClosed: () -> Unit = {}) {
    present("paywall", Detent.LARGE, onDismiss = onClosed) { dismiss ->
        PaywallFlow(impressionId, onClose = dismiss)
    }
}

@Composable
fun PaywallFlow(impressionId: String, onClose: () -> Unit) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val activity = currentActivity()
    val scope = rememberCoroutineScope()
    var showFull by remember { mutableStateOf(false) }
    var isPurchasing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val isSolo = graph.pairing.solo || graph.pairing.coupleId == null
    val trialPlan = store.plans.firstOrNull { it.kind == PlanKind.YEARLY } ?: store.plans.firstOrNull()

    LaunchedEffect(Unit) {
        if (store.plans.isEmpty()) store.fetchProducts()
        store.trackPaywallImpression(impressionId)
        val plan = store.plans.firstOrNull { it.kind == PlanKind.YEARLY } ?: store.plans.firstOrNull()
        if (plan != null && !store.isEligibleForIntroOffer(plan)) showFull = true
        else if (plan == null && store.plans.isNotEmpty()) showFull = true
    }
    LaunchedEffect(store.isPremium) { if (store.isPremium) onClose() }

    if (showFull) {
        PaywallScreen(impressionId = "${impressionId}_plans", onClose = onClose)
        return
    }
    TrialOfferSheet(
        isSolo = isSolo,
        offerLabel = trialPlan?.introOfferLabel,
        priceLabel = trialPlan?.priceLabel,
        isPurchasing = isPurchasing,
        errorMessage = error,
        onStartTrial = {
            val plan = trialPlan
            if (plan == null || activity == null) {
                showFull = true
            } else {
                error = null
                isPurchasing = true
                scope.launch {
                    try {
                        when (store.purchase(activity, plan)) {
                            PurchaseOutcome.PURCHASED -> onClose()
                            PurchaseOutcome.PENDING -> {
                                store.restore()
                                if (store.isPremium) onClose() else {
                                    error = "Payment went through but we're still syncing. Tap Restore on the next screen."
                                    showFull = true
                                }
                            }
                            PurchaseOutcome.CANCELLED -> Unit
                        }
                    } catch (e: PurchaseException) {
                        error = e.message
                        if (e.suggestsRestore) showFull = true
                    } finally {
                        isPurchasing = false
                    }
                }
            }
        },
        onSeeAllPlans = { showFull = true },
        onDismiss = onClose,
    )
}

@Composable
private fun TrialOfferSheet(
    isSolo: Boolean,
    offerLabel: String?,
    priceLabel: String?,
    isPurchasing: Boolean,
    errorMessage: String?,
    onStartTrial: () -> Unit,
    onSeeAllPlans: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = Bond.colors
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().testTag("paywall.trial")) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Spacing.xl).padding(top = Spacing.m),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            Box(Modifier.size(56.dp).clip(CircleShape).background(colors.accentGradient), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
            BText(PaywallCopy.trialHeadline(offerLabel), BondType.title3.bold, colors.accent, align = TextAlign.Center)
            BText(if (offerLabel != null) PlusBenefits.trialSubheadline(isSolo) else PlusBenefits.paywallSubheadline(isSolo), BondType.footnote, colors.inkSecondary, align = TextAlign.Center)
            PlusBenefits.benefits(isSolo).take(2).forEach { benefit ->
                BenefitRow(benefit, Modifier.clip(RoundedCornerShape(Radius.card)).background(colors.cardFill).padding(horizontal = Spacing.s, vertical = Spacing.xs))
            }
            errorMessage?.let { BText(it, BondType.footnote, colors.danger, align = TextAlign.Center) }
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.xl).padding(bottom = Spacing.base),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            PaywallCopy.trialBillingDisclosure(offerLabel, priceLabel)?.let {
                BText(it, BondType.caption2, colors.inkTertiary, align = TextAlign.Center, modifier = Modifier.testTag("paywall.trial.disclosure"))
            }
            PrimaryButton(PaywallCopy.trialCtaTitle(offerLabel), isLoading = isPurchasing, tag = "paywall.trial.start", onClick = onStartTrial)
            TextLink("See all plans", enabled = !isPurchasing, tag = "paywall.trial.allPlans", onClick = onSeeAllPlans)
            TextLink("Not now", color = colors.inkSecondary, enabled = !isPurchasing, tag = "paywall.trial.notNow", onClick = onDismiss)
            LegalLinks(context)
        }
    }
}

@Composable
private fun LegalLinks(context: android.content.Context, restore: (@Composable () -> Unit)? = null) {
    val colors = Bond.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        restore?.let {
            it()
            BText("·", BondType.caption2, colors.inkTertiary)
        }
        TextLink("Terms", style = BondType.caption2, color = colors.inkTertiary) { openLink(context, StoreLinks.TERMS_URL) }
        BText("·", BondType.caption2, colors.inkTertiary)
        TextLink("Privacy", style = BondType.caption2, color = colors.inkTertiary) { openLink(context, StoreLinks.PRIVACY_URL) }
    }
}

@Composable
private fun BenefitRow(benefit: PlusBenefit, modifier: Modifier = Modifier, iconSize: Int = 28) {
    val colors = Bond.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(iconSize.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
            Icon(benefit.icon, null, tint = colors.accent, modifier = Modifier.size((iconSize / 2).dp))
        }
        Spacer(Modifier.width(Spacing.s))
        Column(Modifier.weight(1f)) {
            BText(benefit.title, BondType.subheadline.semibold)
            BText(benefit.detail, BondType.caption, colors.inkSecondary)
        }
    }
}

/** `PaywallView.swift`: header, benefits, plan cards, CTA with its subline, renewal terms and links. */
@Composable
fun PaywallScreen(impressionId: String = "bond_premium_sheet", displayCloseButton: Boolean = true, onClose: () -> Unit) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val colors = Bond.colors
    val context = LocalContext.current
    val activity = currentActivity()
    val scope = rememberCoroutineScope()
    var selectedId by remember { mutableStateOf<String?>(null) }
    var isPurchasing by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    var needsManualRestore by remember { mutableStateOf(false) }
    val isSolo = graph.pairing.solo || graph.pairing.coupleId == null
    val plans = store.plans

    LaunchedEffect(Unit) {
        store.trackPaywallImpression(impressionId)
        if (store.plans.isEmpty()) store.fetchProducts()
    }
    LaunchedEffect(plans.size) {
        if (selectedId == null && plans.isNotEmpty()) {
            selectedId = (plans.firstOrNull { it.kind == PlanKind.YEARLY } ?: plans.first()).id
        }
    }
    LaunchedEffect(store.isPremium) { if (store.isPremium) onClose() }

    val selected = plans.firstOrNull { it.id == selectedId }
    val monthly = plans.firstOrNull { it.kind == PlanKind.MONTHLY }

    fun restore() {
        errorMessage = null
        restoreMessage = null
        isRestoring = true
        scope.launch {
            store.restore()
            isRestoring = false
            if (store.isPremium) needsManualRestore = false
            else restoreMessage = store.lastError ?: "No active ${Membership.PLUS} purchase found for this Google account."
        }
    }

    Column(Modifier.fillMaxSize().background(colors.surface).testTag("paywall.full")) {
        if (displayCloseButton) {
            Box(Modifier.fillMaxWidth().padding(horizontal = Spacing.xs)) {
                IconButton(onClick = onClose, modifier = Modifier.align(Alignment.CenterEnd).semantics { contentDescription = "Close" }.testTag("paywall.close")) {
                    Icon(Icons.Rounded.Cancel, null, tint = colors.inkTertiary, modifier = Modifier.size(28.dp))
                }
            }
        }
        when {
            store.isLoadingProducts && plans.isEmpty() -> Column(
                Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator(color = colors.accent)
                VSpace(Spacing.m)
                BText("Loading plans…", BondType.subheadline, colors.inkSecondary)
            }
            plans.isEmpty() -> Column(
                Modifier.fillMaxSize().padding(horizontal = Spacing.xl), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Spacing.m, Alignment.CenterVertically),
            ) {
                Icon(Icons.Rounded.WifiOff, null, tint = colors.inkSecondary, modifier = Modifier.size(40.dp))
                BText("Couldn't Load Plans", BondType.headline)
                BText(store.lastError ?: "Check your connection and try again.", BondType.subheadline, colors.inkSecondary, align = TextAlign.Center)
                TextLink("Try Again") { scope.launch { store.fetchProducts() } }
            }
            else -> Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Spacing.xl).padding(bottom = Spacing.base),
                verticalArrangement = Arrangement.spacedBy(Spacing.m),
            ) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    BText(Membership.PLUS, BondType.title2.copy(fontWeight = FontWeight.ExtraBold), colors.accent)
                    BText(PlusBenefits.paywallSubheadline(isSolo), BondType.footnote, colors.inkSecondary, align = TextAlign.Center, maxLines = 2)
                }
                Column(Modifier.padding(horizontal = Spacing.m, vertical = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    PlusBenefits.benefits(isSolo).forEach { BenefitRow(it, iconSize = 24) }
                }
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    plans.forEach { plan ->
                        PlanCard(
                            plan = plan,
                            selected = plan.id == selectedId,
                            showsTrial = store.isEligibleForIntroOffer(plan),
                            badge = PaywallCopy.badge(plan, monthly),
                            perWeek = if (plan.kind == PlanKind.YEARLY) plan.pricePerWeekLabel else null,
                        ) { selectedId = plan.id }
                    }
                }
                VSpace(Spacing.xs)
                val eligible = selected?.let { store.isEligibleForIntroOffer(it) } ?: false
                PrimaryButton(
                    PaywallCopy.ctaTitle(selected, eligible),
                    enabled = selected != null && !isPurchasing,
                    isLoading = isPurchasing,
                    tag = "paywall.purchase",
                ) {
                    val plan = selected ?: return@PrimaryButton
                    val host = activity ?: return@PrimaryButton
                    errorMessage = null
                    statusMessage = null
                    restoreMessage = null
                    needsManualRestore = false
                    isPurchasing = true
                    scope.launch {
                        try {
                            when (store.purchase(host, plan)) {
                                PurchaseOutcome.PURCHASED -> onClose()
                                PurchaseOutcome.PENDING -> {
                                    statusMessage = "Finalizing your purchase…"
                                    store.restore()
                                    statusMessage = null
                                    if (store.isPremium) onClose() else {
                                        errorMessage = "Your payment went through but we're still syncing it. Tap below to finish unlocking."
                                        needsManualRestore = true
                                    }
                                }
                                PurchaseOutcome.CANCELLED -> Unit
                            }
                        } catch (e: PurchaseException) {
                            errorMessage = e.message
                            needsManualRestore = e.suggestsRestore
                        } finally {
                            isPurchasing = false
                        }
                    }
                }
                BText(
                    PaywallCopy.ctaSubline(selected, eligible) ?: " ",
                    BondType.footnote.semibold, colors.inkSecondary, align = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 36.dp).testTag("paywall.subline"),
                )
                statusMessage?.let { BText(it, BondType.footnote, colors.inkSecondary, align = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                errorMessage?.let { BText(it, BondType.footnote, colors.danger, align = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                if (needsManualRestore) {
                    PrimaryButton(if (isRestoring) "Restoring…" else "Restore Purchase", isLoading = isRestoring) { restore() }
                }
                restoreMessage?.let { BText(it, BondType.footnote, colors.inkSecondary, align = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    BText(
                        PaywallCopy.autoRenewDisclosure(selected) ?: " ", BondType.caption2, colors.inkTertiary,
                        align = TextAlign.Center, modifier = Modifier.heightIn(min = 32.dp),
                    )
                    LegalLinks(context) {
                        TextLink(if (isRestoring) "Restoring…" else "Restore", style = BondType.caption2.semibold, color = colors.inkTertiary, enabled = !isRestoring && !isPurchasing, tag = "paywall.restore") { restore() }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlanCard(plan: PlanInfo, selected: Boolean, showsTrial: Boolean, badge: String?, perWeek: String?, onTap: () -> Unit) {
    val colors = Bond.colors
    val shape = RoundedCornerShape(Radius.card)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.cardFill)
            .border(if (selected) BorderStroke(2.dp, colors.accent) else BorderStroke(0.5.dp, colors.hairline), shape)
            .clickable(role = Role.RadioButton, onClick = onTap)
            .padding(horizontal = Spacing.base, vertical = Spacing.s)
            .heightIn(min = 48.dp)
            .testTag("paywall.plan.${plan.kind.name.lowercase()}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (selected) colors.accent else colors.inkSecondary.copy(alpha = 0.35f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Box(Modifier.size(12.dp).clip(CircleShape).background(colors.accent))
        }
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                BText(plan.displayName, BondType.subheadline.bold)
                badge?.let {
                    Box(Modifier.clip(CircleShape).background(colors.accent).padding(horizontal = 6.dp, vertical = 2.dp)) {
                        Text(it, color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.ExtraBold)
                    }
                }
            }
            val trial = plan.introOfferLabel
            if (showsTrial && trial != null) {
                BText(PaywallCopy.capitalized(trial), BondType.caption2.semibold, colors.accent)
            } else if (perWeek != null) {
                BText("Just $perWeek", BondType.caption2.semibold, colors.inkSecondary)
            }
        }
        Spacer(Modifier.width(Spacing.s))
        Column(horizontalAlignment = Alignment.End) {
            BText(plan.priceLabel, BondType.subheadline.semibold, modifier = Modifier.testTag("paywall.price.${plan.kind.name.lowercase()}"))
            if (showsTrial && perWeek != null) BText(perWeek, BondType.caption2, colors.inkSecondary)
        }
    }
}

/** `BondUnlockCard`: the shared unlock prompt under a gated feature's free preview. */
@Composable
fun UnlockCard(icon: ImageVector, headline: String, subhead: String, onUnlock: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Bond.colors
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.hero)).background(colors.surfaceElevated.copy(alpha = 0.92f))
            .border(0.5.dp, colors.hairline, RoundedCornerShape(Radius.hero)).padding(Spacing.base),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.m),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            Icon(icon, null, tint = colors.accent, modifier = Modifier.size(28.dp))
            BText(headline, BondType.headline, align = TextAlign.Center)
            BText(subhead, BondType.subheadline, colors.inkSecondary, align = TextAlign.Center)
        }
        PrimaryButton("Explore ${Membership.PLUS}", tag = "unlock.cta", onClick = onUnlock)
        RestoreButton()
    }
}

/** `BondRestoreButton`: success lifts the gate, so only a miss needs saying. */
@Composable
fun RestoreButton() {
    val store = LocalGraph.current.subscriptions
    val scope = rememberCoroutineScope()
    var restoring by remember { mutableStateOf(false) }
    var showResult by remember { mutableStateOf(false) }
    if (restoring) {
        CircularProgressIndicator(Modifier.size(20.dp), color = Bond.colors.accent, strokeWidth = 2.dp)
    } else {
        TextLink("Restore purchases", style = BondType.footnote, color = Bond.colors.inkSecondary) {
            scope.launch {
                restoring = true
                store.restore()
                restoring = false
                if (!store.isPremium) showResult = true
            }
        }
    }
    if (showResult) {
        AlertDialog(
            onDismissRequest = { showResult = false },
            confirmButton = { TextButton(onClick = { showResult = false }) { Text("OK") } },
            title = { Text("Restore Purchases") },
            text = { Text(store.lastError ?: "No active ${Membership.PLUS} purchase found for this Google account.") },
        )
    }
}

enum class PremiumFeature(val gateHeadline: String, val gateSubhead: String) {
    CHECK_IN("One question, every day.", "Both of you answer the same prompt. You see each other's once you've both replied."),
    INSIGHTS("How you tend to each other.", "Track which love languages you're leaning on, and which need attention."),
    TEMPLATES("Reminder packs, ready to go.", "Curated sets for date nights, long distance, daily affirmations, and more."),
}
