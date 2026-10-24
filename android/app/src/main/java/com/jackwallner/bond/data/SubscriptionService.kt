package com.jackwallner.bond.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.bond.BuildConfig
import com.revenuecat.purchases.CacheFetchPolicy
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PeriodType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitLogOut
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import java.math.BigDecimal
import java.math.RoundingMode
import java.security.MessageDigest
import java.text.NumberFormat
import java.time.Instant
import java.util.Currency
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

object Membership {
    const val NAME = "Little Gestures"
    const val PLUS = "Little Gestures+"
    const val ENTITLEMENT_ID = "Husband & Wife Reminder - Bond Pro"
}

/** `BondPackageKind`: the sort order of the plan list (lifetime, yearly, monthly). */
enum class PlanKind { LIFETIME, YEARLY, MONTHLY, OTHER }

enum class PeriodUnit { DAY, WEEK, MONTH, YEAR }

/** What the paywall needs from one store package, free of RevenueCat types so the copy is testable. */
data class PlanInfo(
    val id: String,
    val productId: String,
    val kind: PlanKind,
    val storeTitle: String,
    val price: BigDecimal,
    val formattedPrice: String,
    val currencyCode: String,
    val periodUnit: PeriodUnit? = null,
    val periodValue: Int = 1,
    val trialUnit: PeriodUnit? = null,
    val trialValue: Int = 0,
) {
    val isSubscription: Boolean get() = periodUnit != null

    val displayName: String
        get() = when (kind) {
            PlanKind.LIFETIME -> "Lifetime"
            PlanKind.YEARLY -> "Yearly"
            PlanKind.MONTHLY -> "Monthly"
            PlanKind.OTHER -> storeTitle
        }

    /** "$39.99 / year", or the bare price for a one-time product. */
    val priceLabel: String
        get() {
            val unit = periodUnit ?: return formattedPrice
            val name = unitName(unit, periodValue)
            return if (periodValue == 1) "$formattedPrice / $name" else "$formattedPrice / $periodValue $name"
        }

    /** "7-day free trial" when the product carries a free phase. */
    val introOfferLabel: String?
        get() {
            val unit = trialUnit ?: return null
            if (trialValue <= 0) return null
            if (unit == PeriodUnit.WEEK) return "${trialValue * 7}-day free trial"
            return "$trialValue-${unitName(unit, 1)} free trial"
        }

    val trialDays: Int?
        get() {
            val unit = trialUnit ?: return null
            if (trialValue <= 0) return null
            return when (unit) {
                PeriodUnit.DAY -> trialValue
                PeriodUnit.WEEK -> trialValue * 7
                PeriodUnit.MONTH -> trialValue * 30
                PeriodUnit.YEAR -> trialValue * 365
            }
        }

    val monthlyPriceValue: BigDecimal?
        get() {
            val unit = periodUnit ?: return null
            val months = when (unit) {
                PeriodUnit.DAY -> BigDecimal(periodValue).divide(BigDecimal(30), 10, RoundingMode.HALF_UP)
                PeriodUnit.WEEK -> BigDecimal(periodValue).divide(BigDecimal("4.345"), 10, RoundingMode.HALF_UP)
                PeriodUnit.MONTH -> BigDecimal(periodValue)
                PeriodUnit.YEAR -> BigDecimal(periodValue * 12)
            }
            if (months.signum() <= 0) return null
            return price.divide(months, 10, RoundingMode.HALF_UP)
        }

    /** "$0.77/wk", from the subscription period. */
    val pricePerWeekLabel: String?
        get() {
            val unit = periodUnit ?: return null
            val weeks = when (unit) {
                PeriodUnit.DAY -> BigDecimal(periodValue).divide(BigDecimal(7), 10, RoundingMode.HALF_UP)
                PeriodUnit.WEEK -> BigDecimal(periodValue)
                PeriodUnit.MONTH -> BigDecimal(periodValue).multiply(BigDecimal("4.345"))
                PeriodUnit.YEAR -> BigDecimal(periodValue * 52)
            }
            if (weeks.signum() <= 0) return null
            val perWeek = price.divide(weeks, 2, RoundingMode.HALF_EVEN)
            val format = NumberFormat.getCurrencyInstance().apply {
                runCatching { currency = Currency.getInstance(currencyCode) }
                minimumFractionDigits = 2
                maximumFractionDigits = 2
            }
            return format.format(perWeek) + "/wk"
        }

    fun savingsPercent(monthly: PlanInfo): Int? {
        val mine = monthlyPriceValue ?: return null
        val other = monthly.monthlyPriceValue ?: return null
        if (other.signum() <= 0 || mine >= other) return null
        val percent = other.subtract(mine).divide(other, 10, RoundingMode.HALF_UP).multiply(BigDecimal(100))
        val rounded = percent.setScale(0, RoundingMode.HALF_UP).toInt()
        return rounded.takeIf { it > 0 }
    }

    companion object {
        fun unitName(unit: PeriodUnit, value: Int): String {
            val base = when (unit) {
                PeriodUnit.DAY -> "day"
                PeriodUnit.WEEK -> "week"
                PeriodUnit.MONTH -> "month"
                PeriodUnit.YEAR -> "year"
            }
            return if (value == 1) base else "${base}s"
        }

        fun kindFor(packageType: String, identifier: String, productId: String): PlanKind = when (packageType) {
            "LIFETIME" -> PlanKind.LIFETIME
            "ANNUAL" -> PlanKind.YEARLY
            "MONTHLY" -> PlanKind.MONTHLY
            else -> {
                val ids = listOf(identifier, productId).map { it.lowercase() }
                when {
                    ids.any { "lifetime" in it } -> PlanKind.LIFETIME
                    ids.any { "yearly" in it || "annual" in it } -> PlanKind.YEARLY
                    ids.any { "monthly" in it } -> PlanKind.MONTHLY
                    else -> PlanKind.OTHER
                }
            }
        }

        fun sorted(plans: List<PlanInfo>): List<PlanInfo> =
            plans.sortedWith(compareBy<PlanInfo> { it.kind.ordinal }.thenBy { it.productId })
    }
}

/** Paywall and trial-sheet copy (`PaywallView.swift`, `TrialOfferSheet.swift`) with Google Play wording. */
object PaywallCopy {
    fun ctaTitle(plan: PlanInfo?, trialEligible: Boolean): String = when {
        plan == null -> "Continue"
        plan.kind == PlanKind.LIFETIME -> "Unlock Lifetime"
        trialEligible && plan.trialDays != null -> "Try ${Membership.PLUS} Free"
        trialEligible -> "Start Free Trial"
        else -> "Get ${Membership.PLUS}"
    }

    fun ctaSubline(plan: PlanInfo?, trialEligible: Boolean): String? {
        if (plan == null || plan.kind == PlanKind.LIFETIME) return null
        return if (trialEligible) "No payment today. Then ${plan.priceLabel}. Cancel anytime in Google Play."
        else "${plan.priceLabel}. Renews automatically."
    }

    /** Subscriptions only; a lifetime purchase never renews. */
    fun autoRenewDisclosure(plan: PlanInfo?): String? {
        if (plan == null || !plan.isSubscription) return null
        return "Payment is charged to your Google Play account. Renews automatically until you cancel in Google Play."
    }

    /** "7 days" from "7-day free trial". */
    fun trialPeriodPhrase(offerLabel: String?): String? {
        val match = Regex("^(\\d+)-([A-Za-z]+)").find(offerLabel ?: return null) ?: return null
        val value = match.groupValues[1].toIntOrNull() ?: return null
        val unit = match.groupValues[2]
        return "$value ${if (value == 1) unit else "${unit}s"}"
    }

    fun trialHeadline(offerLabel: String?): String =
        if (trialPeriodPhrase(offerLabel) != null) "Turn intentions into actions." else "Unlock your full Little Gestures plan."

    fun trialCtaTitle(offerLabel: String?): String =
        if (trialPeriodPhrase(offerLabel) != null) "Try ${Membership.PLUS} Free" else "Unlock ${Membership.PLUS}"

    fun trialBillingDisclosure(offerLabel: String?, priceLabel: String?): String? {
        priceLabel ?: return null
        val period = trialPeriodPhrase(offerLabel)
        return if (period != null) "No payment today. Free for $period, then $priceLabel. Cancel anytime in Google Play."
        else "$priceLabel. Payment is charged to your Google Play account. Renews automatically until you cancel in Google Play."
    }

    /** The plan badge: "SAVE 58%" on yearly against monthly, else "BEST VALUE" on yearly. */
    fun badge(plan: PlanInfo, monthly: PlanInfo?): String? {
        if (plan.kind != PlanKind.YEARLY) return null
        val percent = monthly?.let { plan.savingsPercent(it) }
        return percent?.let { "SAVE $it%" } ?: "BEST VALUE"
    }

    /** `String.capitalized` for the trial label: "7-Day Free Trial". */
    fun capitalized(text: String): String =
        text.split(" ").joinToString(" ") { word ->
            word.split("-").joinToString("-") { part -> part.lowercase().replaceFirstChar { it.titlecase() } }
        }
}

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

internal suspend fun resolveOnboardingPurchase(
    result: PurchaseOutcome,
    isPremium: () -> Boolean,
    restore: suspend () -> Unit,
): Boolean = when (result) {
    PurchaseOutcome.CANCELLED -> false
    PurchaseOutcome.PURCHASED -> isPremium()
    PurchaseOutcome.PENDING -> {
        restore()
        isPremium()
    }
}

class PurchaseException(message: String, val suggestsRestore: Boolean = false) : Exception(message)

/** Google Play reviewers reach Little Gestures+ with a code; only its SHA-256 ships in the build. */
class ReviewAccess(private val defaults: KeyValueStore, private val expectedDigest: String) {
    val isGranted: Boolean get() = expectedDigest.length == 64 && defaults.getString(KEY) == expectedDigest

    fun activate(code: String): Boolean {
        if (!expectedDigest.matches(Regex("[a-f0-9]{64}"))) return false
        val digest = MessageDigest.getInstance("SHA-256").digest(code.trim().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        if (!MessageDigest.isEqual(digest.toByteArray(), expectedDigest.toByteArray())) return false
        defaults.putString(KEY, expectedDigest)
        return true
    }

    private companion object {
        const val KEY = "subscription.playReviewAccess"
    }
}

/**
 * RevenueCat behind the Little Gestures+ entitlement (`PurchasesService.swift`).
 * Debug builds use the Test Store key and release builds the Play key; neither
 * ever runs on the other. Reads the `default` offering like iOS.
 */
class SubscriptionService(
    private val context: Context,
    private val defaults: KeyValueStore,
    private val diagnostics: ConversionDiagnostics,
    reviewCodeDigest: String = BuildConfig.PLAY_REVIEW_CODE_SHA256,
) {
    private val reviewAccess = ReviewAccess(defaults, reviewCodeDigest)

    var isPremium by mutableStateOf(reviewAccess.isGranted)
        private set
    var plans by mutableStateOf<List<PlanInfo>>(emptyList())
        private set
    var isLoadingProducts by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
    var premiumSince by mutableStateOf<Instant?>(null)
        private set
    var activeProductId by mutableStateOf<String?>(null)
        private set

    private var packages: Map<String, Package> = emptyMap()
    private var offering: Offering? = null
    private var isConfigured = false
    private var forcePro = false
    private var lastImpressionId: String? = null
    private val impressionsThisSession = mutableSetOf<String>()

    fun activateReviewAccess(code: String): Boolean {
        if (!reviewAccess.activate(code)) return false
        isPremium = true
        return true
    }

    /** Debug-only: open the paid boundary for screenshots and tests. */
    fun forcePremiumForDebug(value: Boolean = true) {
        if (!BuildConfig.DEBUG) return
        forcePro = value
        isPremium = value
    }

    suspend fun bootstrap() {
        if (!configureIfNeeded()) return
        refresh()
        fetchProducts()
    }

    suspend fun refresh(fetchCurrent: Boolean = false) {
        if (!configureIfNeeded()) return
        val policy = if (fetchCurrent) CacheFetchPolicy.FETCH_CURRENT else CacheFetchPolicy.default()
        try {
            apply(Purchases.sharedInstance.awaitCustomerInfo(policy))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            lastError = error.message
        }
    }

    suspend fun fetchProducts() {
        if (!configureIfNeeded()) {
            lastError = "Couldn't load subscription options. Check your connection and try again."
            return
        }
        isLoadingProducts = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val chosen = offerings.all[DEFAULT_OFFERING] ?: offerings.current
            offering = chosen
            val available = chosen?.availablePackages.orEmpty()
            packages = available.associateBy { it.identifier }
            plans = PlanInfo.sorted(available.map(::planInfo))
            lastError = null
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            lastError = "Couldn't load subscription options. Check your connection and try again."
        } finally {
            isLoadingProducts = false
        }
    }

    /** Play only returns offers this account may take, so a free phase on the default option is eligibility. */
    fun isEligibleForIntroOffer(plan: PlanInfo): Boolean = plan.introOfferLabel != null

    fun trackPaywallImpression(id: String, oncePerSession: Boolean = false) {
        if (oncePerSession && !impressionsThisSession.add(id)) return
        lastImpressionId = id
        if (!configureIfNeeded()) return
        diagnostics.recordPitchView(id)
        syncConversionAttributes()
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(CustomPaywallImpressionParams(id)) }
    }

    private fun syncConversionAttributes() {
        if (!isConfigured) return
        val attributes = diagnostics.subscriberAttributes
        if (attributes.isEmpty()) return
        runCatching { Purchases.sharedInstance.setAttributes(attributes) }
    }

    /** RevenueCat's app user id is the Supabase user id, uppercase like Swift's `uuidString`. */
    suspend fun identify(userId: UUID) {
        if (!configureIfNeeded()) return
        try {
            apply(Purchases.sharedInstance.awaitLogIn(userId.toString().uppercase()).customerInfo)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            lastError = error.message
        }
    }

    suspend fun signOut() {
        if (!configureIfNeeded()) return
        runCatching { apply(Purchases.sharedInstance.awaitLogOut()) }
            .onFailure { if (it is CancellationException) throw it }
    }

    suspend fun purchase(activity: Activity, plan: PlanInfo): PurchaseOutcome {
        val pkg = packages[plan.id]
        if (!configureIfNeeded() || pkg == null) throw PurchaseException(UNAVAILABLE)
        lastError = null
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(activity, pkg).build())
            apply(result.customerInfo)
            if (isPremium) {
                val startedTrial = result.customerInfo.entitlements.active.values.any { it.periodType == PeriodType.TRIAL }
                diagnostics.recordConversion(pkg.product.id, startedTrial, pkg.presentedOfferingContext.offeringIdentifier)
                syncConversionAttributes()
                return PurchaseOutcome.PURCHASED
            }
            repeat(10) {
                delay(600)
                refresh(fetchCurrent = true)
                if (isPremium) return PurchaseOutcome.PURCHASED
            }
            PurchaseOutcome.PENDING
        } catch (error: PurchasesTransactionException) {
            when {
                error.userCancelled -> PurchaseOutcome.CANCELLED
                error.code == PurchasesErrorCode.PaymentPendingError -> {
                    lastError = "Your payment is pending approval. We'll unlock ${Membership.PLUS} as soon as it clears."
                    throw PurchaseException(lastError!!, suggestsRestore = true)
                }
                error.code == PurchasesErrorCode.ProductAlreadyPurchasedError -> {
                    restore()
                    if (isPremium) PurchaseOutcome.PURCHASED
                    else throw PurchaseException("You already own this. Tap Restore to unlock it on this device.", true)
                }
                error.code == PurchasesErrorCode.NetworkError ->
                    throw PurchaseException("Network issue completing the purchase. Check your connection and try again.")
                else -> throw PurchaseException("Couldn't complete the purchase. Please try again.")
            }
        }
    }

    suspend fun restore() {
        if (!configureIfNeeded()) {
            lastError = UNAVAILABLE
            return
        }
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            lastError = if (isPremium) null else "No active ${Membership.PLUS} purchase found for this Google account."
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    private fun apply(info: CustomerInfo) {
        if (forcePro) return
        val active = info.entitlements.active.values
        val entitlement = info.entitlements[Membership.ENTITLEMENT_ID]?.takeIf { it.isActive } ?: active.firstOrNull()
        activeProductId = entitlement?.productIdentifier?.substringBefore(":")
        premiumSince = entitlement?.latestPurchaseDate?.toInstant()
        isPremium = active.isNotEmpty() || info.activeSubscriptions.isNotEmpty() || reviewAccess.isGranted
    }

    private fun planInfo(pkg: Package): PlanInfo {
        val product = pkg.product
        val trial = product.defaultOption?.freePhase?.billingPeriod
        return PlanInfo(
            id = pkg.identifier,
            productId = product.id.substringBefore(":"),
            kind = PlanInfo.kindFor(packageTypeName(pkg.packageType), pkg.identifier, product.id),
            storeTitle = product.title,
            price = BigDecimal.valueOf(product.price.amountMicros, 6),
            formattedPrice = product.price.formatted,
            currencyCode = product.price.currencyCode,
            periodUnit = product.period?.let(::unitOf),
            periodValue = product.period?.value ?: 1,
            trialUnit = trial?.let(::unitOf),
            trialValue = trial?.value ?: 0,
        )
    }

    private fun packageTypeName(type: PackageType): String = type.name

    private fun unitOf(period: Period): PeriodUnit? = when (period.unit) {
        Period.Unit.DAY -> PeriodUnit.DAY
        Period.Unit.WEEK -> PeriodUnit.WEEK
        Period.Unit.MONTH -> PeriodUnit.MONTH
        Period.Unit.YEAR -> PeriodUnit.YEAR
        else -> null
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        if (forcePro) return false
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        val builder = PurchasesConfiguration.Builder(context, key)
        // Test Store runs share one tester instead of a fresh anonymous customer
        // per install, so test installs don't inflate the live project's
        // customer charts. Never with the Play key: real buyers would share one identity.
        if (key.startsWith("test_")) builder.appUserID(QA_APP_USER_ID)
        Purchases.configure(builder.build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private companion object {
        const val DEFAULT_OFFERING = "default"
        const val QA_APP_USER_ID = "qa-android"
        const val UNAVAILABLE = "Google Play isn't reachable right now. Check your connection and try again."
    }
}
