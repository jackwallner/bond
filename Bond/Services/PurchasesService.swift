import Foundation
import OSLog
import RevenueCat

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

@MainActor
@Observable
final class PurchasesService {
    static let shared = PurchasesService()
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "purchases")

    static let apiKey = "appl_mNANfaYASZUZZwdRZuLHXzovffW"
    /// MUST exactly match the entitlement *identifier* in the RevenueCat
    /// dashboard (Product catalog → Entitlements), NOT the display name. It is
    /// `Husband & Wife Reminder - Bond Pro` — the long-standing "payment went
    /// through but still syncing" bug was this checking `"premium"`, which never
    /// existed, so a successful purchase could never resolve to an entitlement.
    static let entitlementId = "Husband & Wife Reminder - Bond Pro"

    private(set) var isPremium = false
    private(set) var customerInfo: CustomerInfo?
    private(set) var products: [Package] = []
    /// Product identifiers we actually sell, collected as offerings load. Used
    /// as a fallback unlock signal when the named entitlement doesn't resolve.
    private(set) var knownProductIds: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var purchaseInFlight = false
    private(set) var introEligibility: [String: Bool] = [:]
    var lastError: String?
    /// True when the most recent purchase failure is one where Apple may have
    /// already taken payment (receipt/ownership conflicts) — i.e. a Restore
    /// could complete the unlock. Lets the paywall avoid offering Restore for
    /// failures (network, store outage) where there's nothing to restore.
    private(set) var lastErrorSuggestsRestore = false

    private var streamTask: Task<Void, Never>?
    private var paywallImpressionsThisSession: Set<String> = []

    private init() {}

    func bootstrap() async {
        Purchases.logLevel = .info
        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: Self.apiKey)
        }
        await refresh()
        await fetchProducts()

        streamTask?.cancel()
        streamTask = Task { @MainActor [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info: info)
            }
        }
    }

    func refresh() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info: info)
        } catch {
            lastError = error.localizedDescription
            log.error("Refresh failed: \(error.localizedDescription)")
        }
    }

    func fetchProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            products = offerings.bondPaywallOffering?.bondSortedPackages ?? []
            // Remember every Bond+ product id we've ever seen offered. `apply`
            // uses this to treat ownership of a known product as premium even
            // when the dashboard entitlement mapping is the broken link.
            knownProductIds.formUnion(products.map(\.storeProduct.productIdentifier))
            lastError = nil
            await refreshIntroEligibility()
            log.info("Loaded \(self.products.count) packages")
        } catch {
            lastError = "Couldn't load subscription options. Check your connection and try again."
            log.error("Product fetch failed: \(error.localizedDescription)")
        }
    }

    private func refreshIntroEligibility() async {
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map(\.storeProduct.productIdentifier)
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: identifiers
        )
        introEligibility = result.mapValues { $0.status == .eligible }
    }

    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.bondIntroOfferLabel != nil else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? true
    }

    /// Reports a custom-paywall impression to RevenueCat (required for native paywalls).
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
        log.info("Tracked paywall impression: \(id)")
    }

    @discardableResult
    func purchase(_ package: Package) async throws -> PurchaseState {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        lastError = nil
        lastErrorSuggestsRestore = false

        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(package: package)
        } catch let error as RevenueCat.ErrorCode {
            // RevenueCat can throw ErrorCode directly. A user backing out of
            // Apple's payment sheet is a cancel, not a failure — surface no
            // error and no Restore prompt.
            if error == .purchaseCancelledError { return .cancelled }
            log.error("Purchase threw ErrorCode \(error.rawValue): \(error.localizedDescription)")
            // Some codes mean Apple accepted payment but RC couldn't attach it
            // to this user — a restore usually completes the unlock.
            if await recoverFromKnownPurchaseError(error) {
                return .purchased
            }
            lastError = readablePurchaseError(error)
            lastErrorSuggestsRestore = errorSuggestsRestore(error)
            throw error
        } catch {
            // RevenueCat normally surfaces failures as a bridged NSError in its
            // own domain. Only interpret the numeric code as an RC ErrorCode
            // when the domain matches — otherwise an unrelated NSError code
            // could collide with an RC raw value and trigger a bogus restore.
            let nsError = error as NSError
            log.error("Purchase threw \(nsError.domain):\(nsError.code) — \(error.localizedDescription)")
            if nsError.domain == RevenueCat.ErrorCode.errorDomain,
               let code = RevenueCat.ErrorCode(rawValue: nsError.code) {
                if code == .purchaseCancelledError { return .cancelled }
                if await recoverFromKnownPurchaseError(code) {
                    return .purchased
                }
                lastError = readablePurchaseError(code)
                lastErrorSuggestsRestore = errorSuggestsRestore(code)
            } else {
                lastError = readablePurchaseError(error)
            }
            throw error
        }
        apply(info: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        }
        if isPremium {
            return .purchased
        }
        // StoreKit → RevenueCat can lag a beat after Apple confirms payment —
        // especially in sandbox/TestFlight where transactions can take several
        // seconds to propagate. Force a sync (stronger than `customerInfo()`
        // which can return cached data) and poll until the entitlement lands
        // or we give up.
        do {
            let synced = try await Purchases.shared.syncPurchases()
            apply(info: synced)
            if isPremium { return .purchased }
        } catch {
            log.warning("syncPurchases after purchase failed: \(error.localizedDescription)")
        }
        for attempt in 1...15 {
            try await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
            if isPremium {
                log.info("Premium unlocked after purchase (attempt \(attempt))")
                return .purchased
            }
        }
        log.warning("Purchase completed but entitlement still inactive")
        return .pending
    }

    /// Some RC errors mean "Apple took the payment, but the entitlement is
    /// attached to a different RC user / receipt" — restore reattaches it.
    /// Returns true when a restore successfully unlocked premium.
    private func recoverFromKnownPurchaseError(_ code: RevenueCat.ErrorCode) async -> Bool {
        switch code {
        case .receiptAlreadyInUseError,
             .productAlreadyPurchasedError,
             .missingReceiptFileError,
             .invalidReceiptError:
            log.info("Attempting restore to recover from \(code.rawValue)")
            do {
                let info = try await Purchases.shared.restorePurchases()
                apply(info: info)
                if isPremium {
                    log.info("Recovered: restore unlocked premium")
                    return true
                }
            } catch {
                log.error("Recovery restore failed: \(error.localizedDescription)")
            }
            return false
        default:
            return false
        }
    }

    /// Whether the failure represents a purchase that may already exist on the
    /// Apple ID (so Restore can finish the unlock), vs. an outright failure
    /// where nothing was charged.
    private func errorSuggestsRestore(_ error: Error) -> Bool {
        guard let code = error as? RevenueCat.ErrorCode else { return false }
        switch code {
        case .receiptAlreadyInUseError,
             .productAlreadyPurchasedError,
             .missingReceiptFileError,
             .invalidReceiptError,
             .paymentPendingError:
            return true
        default:
            return false
        }
    }

    private func readablePurchaseError(_ error: Error) -> String {
        if let code = error as? RevenueCat.ErrorCode {
            switch code {
            case .receiptAlreadyInUseError:
                return "This purchase is tied to another Apple ID. Tap Restore to unlock with the original account."
            case .productAlreadyPurchasedError:
                return "You already own this. Tap Restore to unlock it on this device."
            case .paymentPendingError:
                return "Your payment is pending approval. We'll unlock Bond+ as soon as it clears."
            case .purchaseNotAllowedError:
                return "In-app purchases are restricted on this device."
            case .networkError, .offlineConnectionError:
                return "Network issue completing the purchase. Check your connection and try again."
            case .storeProblemError, .unknownBackendError, .unexpectedBackendResponseError:
                return "The App Store had a problem. Wait a moment and try again, or tap Restore."
            default:
                return "Couldn't complete the purchase (\(code.rawValue)). \(error.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    func identify(supabaseUserId: UUID) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(supabaseUserId.uuidString)
            apply(info: info)
            log.info("Identified user \(supabaseUserId) — premium: \(self.isPremium)")
        } catch {
            lastError = error.localizedDescription
            log.error("Identify failed: \(error.localizedDescription)")
        }
    }

    func signOut() async {
        do {
            let info = try await Purchases.shared.logOut()
            apply(info: info)
            log.info("Signed out of RevenueCat")
        } catch {
            lastError = error.localizedDescription
            log.error("Sign out failed: \(error.localizedDescription)")
        }
    }

    func restore() async {
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info: info)
            lastError = isPremium ? nil : "No active Bond+ purchase found for this Apple ID."
            log.info("Restored purchases — premium: \(self.isPremium)")
        } catch {
            lastError = "Couldn't restore purchases. Try again."
            log.error("Restore failed: \(error.localizedDescription)")
        }
    }

    var premiumSince: Date? {
        customerInfo?.entitlements[Self.entitlementId]?.latestPurchaseDate
            ?? customerInfo?.entitlements.active.values.compactMap(\.latestPurchaseDate).max()
    }

    /// Whether this customer should have Bond+ unlocked.
    ///
    /// Bond sells exactly one paid tier, so we unlock on the first signal that
    /// the user has paid — in priority order:
    ///   1. the configured `premium` entitlement is active (the happy path), or
    ///   2. *any* entitlement is active — covers an entitlement-identifier
    ///      mismatch between this app and the RevenueCat dashboard, or
    ///   3. they own an active subscription / a known Bond+ product — covers a
    ///      missing or broken product→entitlement mapping in the dashboard.
    ///
    /// (2) and (3) are the recurring TestFlight/sandbox failure mode: Apple
    /// takes payment and RevenueCat records the transaction, but
    /// `entitlements["premium"]` never populates, so the old entitlement-only
    /// check left a paying user stuck on "payment went through but still
    /// syncing" no matter how long we polled.
    private func hasActivePremium(_ info: CustomerInfo) -> Bool {
        if info.entitlements[Self.entitlementId]?.isActive == true { return true }
        if !info.entitlements.active.isEmpty { return true }
        if !info.activeSubscriptions.isEmpty { return true }
        // Lifetime / non-consumable ownership. Restrict to products we actually
        // sell so a stray transaction can't grant access.
        if !knownProductIds.isEmpty,
           info.nonSubscriptions.contains(where: { knownProductIds.contains($0.productIdentifier) }) {
            return true
        }
        return false
    }

    private func apply(info: CustomerInfo) {
        customerInfo = info
        isPremium = hasActivePremium(info)
        log.info("""
            Customer info updated — premium: \(self.isPremium) \
            (entitlement: \(info.entitlements[Self.entitlementId]?.isActive == true), \
            activeEntitlements: \(info.entitlements.active.count), \
            activeSubs: \(info.activeSubscriptions.count))
            """)
    }
}
