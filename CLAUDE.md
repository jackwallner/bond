# Bond — Project Guide

Love-language reminders for couples: each partner records what the other
actually appreciates, and Bond turns it into timed nudges, a daily check-in and
milestones. XcodeGen project/scheme: `Bond`, sim lease owner `bond`. App Store
ID `6768514177` (`BondAppStoreID` in `Bond/Info.plist`). Positioning and the
phased plan are in the `project_bond` memory and `aso-plan.md`.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency), Plus Jakarta Sans bundled in `Bond/Resources/Fonts`
- Supabase (supabase-swift) for the couple, reminders, events and push, with
  local notifications scheduled on device
- WidgetKit, a watchOS companion, Sign in with Apple
- XcodeGen (`project.yml`). Targets: iOS 17+, watchOS
- RevenueCat; the entitlement id is `Husband & Wife Reminder - Bond Pro`
  (`PurchasesService.entitlementId`) and the gate is `PurchasesService.isPremium`

## Targets / bundle IDs
- `Bond` — `com.jackwallner.bond`
- `BondWatch` — `.watch`, `BondWidgets` — the widget extension
- `BondTests` — `.tests`, `BondUITests` — `.uitests`
- App Group: `group.com.jackwallner.bond`

## Architecture
- `Shared/` is what the widget and watch compile too: `DTOs/` (`CoupleDTO`,
  `ProfileDTO`, `ReminderDTO`, `ReminderEventDTO`), `Models/` (`LoveLanguage`,
  `ReminderTrigger`, `RecurrencePreset`, `ReminderTemplate`, `MilestoneDTO`,
  `DailyQuestionDTO`), `Utilities/` (`AppGroup`, `WidgetSnapshot`,
  `WatchPayload`, `BondColors`, `AppStoreReviewLinks`) and `ReviewPromptTracker`.
- `Bond/Services/` — `SupabaseConfig` + `SupabaseService` (the backend),
  `PairingService`, `ReminderRepository` / `ReminderEventRepository`,
  `NotificationScheduler` + `NotificationRouter`, `DailyCheckInService`,
  `MilestonesService`, `LoveLanguageAnalyzer`, `PurchasesService`,
  `WatchConnectivityBridge`, `WidgetSnapshotPump`, `AppleSignInHelper`,
  `LocationService`, `ConversionDiagnostics`.
- `Bond/Features/` — one folder per surface: Onboarding, Pairing, ReminderList,
  ReminderEditor, Templates, CheckIn, Milestones, Stats, Paywall, Review,
  Settings.
- `Bond/DesignSystem/` — `BondTheme`, `BondFont`, `BondStyle`, `BondComponents`,
  plus `PremiumGate.swift` (`PremiumFeature`, `BondUnlockCard`,
  `BondRestoreButton`) and its `GateSampleContent`.
- `supabase/migrations/` is the schema (`0001_init` through the solo-mode,
  premium-features, leave-couple and pair-in-place migrations), and
  `SupabaseFunctions/send-push/` is the only backend function.

## Rules that hold everywhere
- **Solo and paired are both first-class.** A user can run Bond alone
  (`0002_solo_mode`) and pair later (`0005_pair_in_place`), so every surface,
  including the paywall copy (`BondPlusBenefits.benefits(isSolo:)`), has to read
  correctly in both states. Never assume a partner exists.
- **Supabase config comes from `Info.plist` keys** (`SUPABASE_URL`,
  `SUPABASE_ANON_KEY`) through `SupabaseConfig`, which treats a placeholder host
  as unconfigured rather than crashing. Migrations are append-only once applied.
- **The entitlement id is the dashboard string, not a guess.**
  `PurchasesService.entitlementId` is `Husband & Wife Reminder - Bond Pro`.
  Checking `"premium"`, which never existed, is what caused the long-standing
  "payment went through but still syncing" bug. Products are
  `com.jackwallner.bond.plus.monthly` and `.plus.yearly` in
  `Bond/Products.storekit`.
- **Premium gating is manual, per surface.** There is no gate wrapper: a locked
  screen checks `!store.isPremium` itself and drops in `BondUnlockCard` from
  `PremiumGate.swift` (see `DailyCheckInView`, `ReminderTemplatesView`,
  `StatsView`). A purchase or restore flips `isPremium` and those checks
  re-render on their own.
- **Never raise a paywall on a beat where the entitlement may still be
  resolving.** `BondApp` checks `!store.isPremium` alongside its own
  one-shot flags (for example the post-pairing paywall) for that reason.
- **Review funnel:** the positive moment is marking a reminder done (swipe Done
  / Handled), never a cold launch, onboarding, pairing success or a paywall
  sheet. Details and the copy: `docs/review-prompt.md`.
- The marketing site is this repo's `docs/`, served by GitHub Pages from
  `jackwallner/bond` (main branch, `/docs`), with clean-URL index routes for
  privacy, terms and support.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
