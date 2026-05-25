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

        let result = try await Purchases.shared.purchase(package: package)
        apply(info: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        }
        if isPremium {
            return .purchased
        }
        return .pending
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
