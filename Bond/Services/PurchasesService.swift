import Foundation
import OSLog
import RevenueCat

@MainActor
@Observable
final class PurchasesService {
    static let shared = PurchasesService()
    private let log = Logger(subsystem: "com.jackwallner.bond", category: "purchases")

    static let apiKey = "appl_mNANfaYASZUZZwdRZuLHXzovffW"
    static let entitlementId = "premium"

    private(set) var isPremium = false
    private(set) var customerInfo: CustomerInfo?
    var lastError: String?

    private init() {}

    func bootstrap() async {
        Purchases.logLevel = .info
        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: Self.apiKey)
        }
        await refresh()

        // Listen for entitlement changes pushed by the SDK.
        Task { @MainActor [weak self] in
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
            log.info("Restored purchases — premium: \(self.isPremium)")
        } catch {
            lastError = error.localizedDescription
            log.error("Restore failed: \(error.localizedDescription)")
        }
    }

    /// When the premium entitlement became active, if known.
    var premiumSince: Date? {
        customerInfo?.entitlements[Self.entitlementId]?.latestPurchaseDate
    }

    private func apply(info: CustomerInfo) {
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementId]?.isActive == true
        log.info("Customer info updated — premium: \(self.isPremium)")
    }
}
