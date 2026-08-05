# iOS 27 compatibility audit: Bond

- Audit date: 2026-08-05
- Runtime: iOS 27.0 (24A5390f)
- Xcode: 26.6 (17F113)
- Scheme: `Bond`
- Unit target: `BondTests`
- Overall: Pass with update candidates

## Checks

- Debug build: Pass.
- Unit tests: Pass.
- Normal rebuild after tests: Pass.
- Install and launch smoke test: Pass.
- Runtime UI snapshot: Pass. Onboarding rendered with invite and name-entry controls.

## Findings

- `Shared/Utilities/AppStoreReviewLinks.swift:26` uses `SKPaymentQueue`, `storefront`, and `countryCode`, deprecated since iOS 18 (and watchOS 11).
- `PaywallView.swift:320` has an unused `days` value.
- `ReminderRepository.swift:101,108` uses deprecated Supabase `postgresChange` and `subscribe()` APIs.
- No iOS 27-specific compiler error or runtime blocker was observed.

## Recommended follow-up

- Migrate StoreKit review-link code and Supabase realtime calls before the next compatibility cleanup.
- Remove the unused paywall value.
