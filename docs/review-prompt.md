# Bond — App Store review prompt

Bond uses Apple's **native** rating prompt (`requestReview()` / StoreKit). We do
**not** filter users by sentiment or pre-screen with an "Are you enjoying it?"
question before routing to the App Store — that is prohibited under App Store
Guideline 5.6.1 (it manipulates reviews by steering only happy users to rate).

| Field | Value |
|-------|-------|
| App Store ID | `BondAppStoreID` in `Bond/Info.plist` (`6768514177`) |
| Display name | Bond |
| Feedback email | jackwallner+b@gmail.com |
| Positive moment | User marks a reminder done (swipe Done / Handled) |
| Avoid | Cold launch, onboarding, pairing success, paywall sheets |
| App group | `group.com.jackwallner.bond` |

## How it works

- **Automatic:** after a positive moment (reminder completed), and once throttle
  thresholds pass (`ReviewPromptTracker`: launch count, days-since-first-open,
  120-day cooldown), the host calls Apple's native `requestReview()`. Apple shows
  its standard 1-5 star dialog and decides whether to display it at all. No
  sentiment gate, no custom pre-prompt.
- **Manual (Settings → Help):** two ungated, direct actions — "Rate Bond on the
  App Store" (write-review deep link) and "Send Feedback" (mail draft). Every
  user sees both regardless of how they feel.

**Code:** `Shared/Services/ReviewPromptTracker.swift` (throttling),
`Shared/Utilities/AppStoreReviewLinks.swift` (write-review link),
`Bond/Features/Settings/SettingsView.swift` (Help section),
host in `Bond/BondApp.swift` (`RootView.requestNativeReviewAfterPositiveMoment`).
