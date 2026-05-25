# Bond — App Store review prompt

Implements the reusable 5-star review playbook (`app-store-5-star-review-strategy.md` on Desktop).

| Field | Value |
|-------|-------|
| App Store ID | Set `BondAppStoreID` in `Bond/Info.plist` when ASC assigns the numeric ID |
| Display name | Bond |
| Feedback email | bond@jackwallner.com |
| Positive moment A | User marks a reminder done (swipe Done / Handled) |
| Avoid | Cold launch, onboarding, pairing success, paywall sheets |
| App group | `group.com.jackwallner.bond` |

**Code:** `Shared/Services/ReviewPromptTracker.swift`, `Shared/Utilities/AppStoreReviewLinks.swift`, `Bond/Features/Review/ReviewPromptSheet.swift`, host in `Bond/BondApp.swift` (`RootView`).
