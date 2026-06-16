import Foundation

extension Notification.Name {
    /// Posted when the user completes a reminder - host may ask the system to
    /// present the native App Store rating prompt after a short delay.
    static let bondPositiveMomentForReview = Notification.Name("com.jackwallner.bond.positiveMomentForReview")
}

/// Persists launch counts, positive moments, and review-prompt eligibility in the app group.
///
/// We never filter users by sentiment or route anyone away from the App Store
/// rating prompt (App Store Guideline 5.6.1). These thresholds only throttle how
/// often we hand off to Apple's native `requestReview()`, which itself decides
/// whether to actually show the system rating dialog.
@MainActor
enum ReviewPromptTracker {
    private static let defaults = AppGroup.defaults

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"

    static let minimumLaunchCount: Int = {
        #if DEBUG
        return 2
        #else
        return 5
        #endif
    }()

    static let minimumDaysSinceFirstOpen = 7
    static let cooldownDays = 120

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    static func recordPositiveMoment() {
        positiveMomentCount += 1
        hasPendingPositiveMoment = true
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func cooldownElapsed(now: Date = .now) -> Bool {
        guard let last = lastShownDate else { return true }
        let cooldown = TimeInterval(cooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    static func canRequestReview(
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> Bool {
        guard ProcessInfo.processInfo.environment["UITesting"] != "1" else { return false }
        guard hasCompletedSetup else { return false }
        guard cooldownElapsed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard let first = firstAppOpenDate else { return false }
        let minInterval = TimeInterval(minimumDaysSinceFirstOpen) * 86_400
        guard now.timeIntervalSince(first) >= minInterval else { return false }
        return true
    }

    static func shouldRequestAfterPositiveMoment(
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(hasCompletedSetup: hasCompletedSetup, now: now)
    }

    static func markRequested(now: Date = .now) {
        lastShownDate = now
        consumePendingPositiveMoment()
    }
}
