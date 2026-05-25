import Foundation

/// App Store review deep links for Bond.
enum AppStoreReviewLinks {
    /// Numeric App Store ID from App Store Connect. Set `BondAppStoreID` in Info.plist before launch.
    static var appStoreID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BondAppStoreID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Opens the App Store write-review page (explicit user-initiated rating CTAs only).
    static var writeReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}
