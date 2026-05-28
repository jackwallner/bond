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
    static let entitlementId = "premium"

    private(set) var isPremium = false
    private(set) var customerInfo: CustomerInfo?
    private(set) var products: [Package] = []
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
    }

    private func apply(info: CustomerInfo) {
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementId]?.isActive == true
        log.info("Customer info updated — premium: \(self.isPremium)")
    }
}
