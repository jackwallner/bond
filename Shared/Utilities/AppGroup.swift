import Foundation

public enum AppGroup {
    public static let identifier = "group.com.jackwallner.bond"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
