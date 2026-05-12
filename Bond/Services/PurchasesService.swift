import Foundation
import RevenueCat

@MainActor
@Observable
final class PurchasesService {
    static let shared = PurchasesService()

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
        }
    }

    func identify(supabaseUserId: UUID) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(supabaseUserId.uuidString)
            apply(info: info)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            let info = try await Purchases.shared.logOut()
            apply(info: info)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(info: CustomerInfo) {
        customerInfo = info
        isPremium = info.entitlements[Self.entitlementId]?.isActive == true
    }
}
