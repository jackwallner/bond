# Bond — App Store review prompt

Bond uses the same enjoyment funnel as Vitals across the portfolio.

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
  120-day cooldown), the host presents the enjoyment sheet → review pitch →
  explicit write-review deep link. `requestReview()` only fires on "Maybe later"
  dismiss.
- **Manual (Settings → Help):** "Rate or Send Feedback" opens the same funnel
  (enjoyment step, or feedback-only when routed from coordinator).

**Code:** `Shared/Services/ReviewPromptTracker.swift`,
`Shared/Utilities/AppStoreReviewLinks.swift` (storefront-aware write-review link),
`Bond/Features/Review/ReviewPromptSheet.swift`,
`Bond/Features/Settings/SettingsView.swift` (Help section),
host in `Bond/BondApp.swift` (`RootView.scheduleReviewPromptAfterPositiveMoment`).
