import Foundation

enum SupabaseConfig {
    static let url: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
                ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
                ?? ""
        return URL(string: raw) ?? URL(string: "https://placeholder.supabase.co")!
    }()

    static let anonKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
    }()

    static var isConfigured: Bool {
        !anonKey.isEmpty && url.host?.contains("placeholder") == false
    }
}
