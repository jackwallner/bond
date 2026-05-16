# 06 — Settings (new screen)

**Current source:** doesn't exist
**Priority:** P0 (blocks TestFlight QA — you can't sign out)
**Status today:** Nowhere to go.

## Job
A minimal "I need to do the admin thing" surface. Not a customization playground.

## Must include (MVP)
- **Account** — display name (read-only), email (read-only, Apple-relay address), Sign Out button (destructive style, with confirm).
- **Pairing** — paired-with display name + small avatar (or initials chip), "Unpair" button (destructive, confirm). For solo users: "Pair with someone" CTA that opens PairingView.
- **Premium** — current entitlement state ("Premium since [date]" or "Free — Unlock Premium"). RestorePurchases button. Manage Subscription link (opens Apple's URL).
- **Notifications** — link to system Settings if permission denied; show current state.
- **About** — Version + Build (from Info.plist). Privacy Policy link (`https://jackwallner.com/bond/privacy`). Terms link (same root). Support email link.

## Nice to have (defer)
- Reduce motion / haptic preferences
- Default love-language for new reminders
- Default notification time window

## Navigation
Add as a fifth tab? Or as a `.toolbar` gear icon on the Reminders view? **Recommendation: gear icon on Reminders top-leading**, because adding a fifth tab dilutes the four-tab clarity. Open to your call.

## Constraints
- Sign Out must reset both `SupabaseService` (auth.signOut) and `PurchasesService` (logOut). Both already implemented; we just need the entry point.
- Unpair is destructive — confirm before action. We don't have a "leave couple" RPC yet (would need to add); for MVP it can be "Delete account" full-nuclear instead.
- "Manage Subscription" opens `https://apps.apple.com/account/subscriptions` — system URL, do not redesign.

## Don't
- Don't show debug/diagnostics here.
- Don't show love-language preference here (that's per-reminder, not per-user).
- Don't show partner's email or phone — privacy.
