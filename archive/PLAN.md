# Bond — Comprehensive Expansion & Cleanup Plan

## Overview

Bond is a beautifully architected couples' love-language reminder app (iOS 18+, watchOS 11+) with Supabase backend, RevenueCat monetization, WatchConnectivity, and WidgetKit. It's well-structured with `@Observable` services, snake_case DTOs, RLS-backed Supabase, and a clean state-machine router. The plan below targets every layer — iOS app, watch app, widgets, backend, testing, CI/CD — organized by priority.

---

## Phase 1 — Low-Hanging Fruit (Code Quality & Structure)

### 1.1 Extract duplicated `PremiumGateView` into reusable component
**Problem:** `MilestonesView` and `StatsView` have nearly identical `premiumGate`/`gate` VStack blocks — same layout, same button, different icon/text.  
**Fix:** Create a `PremiumGateView(icon:title:subtitle:)` in `Shared/Views/` (or `Bond/Components/`). Both views drop ~20 lines each.  
**Files:** `Bond/Features/Milestones/MilestonesView.swift`, `Bond/Features/Stats/StatsView.swift` → new `Bond/Components/PremiumGateView.swift`

### 1.2 Extract Paywall sheet presentation into a view modifier
**Problem:** `.sheet(isPresented: $isPaywallPresented) { PaywallView() }` appears identically in 3 files.  
**Fix:** Create `View.paywallSheet(isPresented:)` modifier.  
**Files:** `ReminderEditorView`, `MilestonesView`, `StatsView` → new `Bond/Components/PaywallModifier.swift`

### 1.3 Extract `MilestoneEditorView` to its own file
**Problem:** `MilestoneEditorView` is defined inline in `MilestonesView.swift` — a full sheet-worthy form with navigation toolbar cohabiting with the list view.  
**Fix:** Move to `Bond/Features/Milestones/MilestoneEditorView.swift`.  
**Files:** Split `MilestonesView.swift`

### 1.4 Extract `ReminderRow` to shared component
**Problem:** `ReminderRow` is a `private` struct inside `ReminderListView`, unreusable elsewhere.  
**Fix:** Extract to `Bond/Components/ReminderRow.swift`. Enables reuse in watch app, widgets, or a future notification content extension.  
**Files:** `Bond/Features/ReminderList/ReminderListView.swift` → new `Bond/Components/ReminderRow.swift`

### 1.5 Move view-local enums to dedicated models file
**Problem:** `ReminderTarget`, `TriggerKind`, and form-related enums are defined inside `ReminderEditorView.swift` — harder to discover and import.  
**Fix:** Move to `Shared/Models/ReminderEditorModels.swift` or inline into `ReminderDTO.swift`.  
**Files:** `ReminderEditorView.swift`

### 1.6 Add SwiftLint
**Problem:** No code style enforcement.  
**Fix:** Add `.swiftlint.yml`, integrate into build phases (or CI). Configure rules: `file_length`, `function_body_length`, `type_body_length`, `nesting`, etc.  
**Files:** New `.swiftlint.yml`

### 1.7 Standardize error handling
**Problem:** Each service has `lastError: String?` and views have `errorMessage: String?` — no typed error system.  
**Fix:** Create `BondError: Error, LocalizedError` enum with cases for `network`, `auth`, `notPremium`, `notFound`, `unknown`. Services propagate typed errors; views map to user-facing strings.  
**Files:** New `Shared/Models/BondError.swift`

### 1.8 Add OSLog logging
**Problem:** No structured logging — debugging relies on print statements or nothing.  
**Fix:** Add `Logger` instances to each service with subsystem/category. Log key lifecycle events (auth success, reminder upsert, push delivery, purchase state change).

---

## Phase 2 — Watch App Modernization

### 2.1 Convert `WatchConnectivitySender` to `@Observable`
**Problem:** Watch uses legacy `ObservableObject`/`@Published`/`@StateObject` while iOS app uses modern `@Observable`.  
**Fix:** Port to `@Observable macro`.  
**Files:** `BondWatch/WatchConnectivitySender.swift`

### 2.2 Add reminder list to watch
**Problem:** Watch can only *create* reminders — cannot view existing ones.  
**Fix:** Add phone→watch messaging for reminder list sync. Show a simple `List` of today's/upcoming reminders on watch. Add "Mark complete" swipe action.  
**Files:** New `BondWatch/ReminderListView.swift`, update `WatchPayload.swift`, update `WatchConnectivityBridge.swift`

### 2.3 Add milestone countdown to watch
**Problem:** Next milestone only shows on widgets — watch has no awareness.  
**Fix:** Include next milestone in phone→watch sync payload. Show as a complication/complication text.  
**Files:** Update `BondWatch/DictateView.swift` or new watch companion view

### 2.4 Rich watch reminder creation
**Problem:** Watch reminder is hardcoded to 1-hour offset, self-targeted, one-time trigger only.  
**Fix:** Add trigger type selection (one-time/recurring), target picker (me/partner), and time picker.  
**Files:** `BondWatch/DictateView.swift`

---

## Phase 3 — Widget & System Integration

### 3.1 Interactive widgets (iOS 17+)
**Problem:** Tapping widget opens app — cannot toggle completion or snooze.  
**Fix:** Add `AppIntent`/`Button` toggle for "Mark complete" on upcoming reminder widget.  
**Files:** `BondWidgets/BondWidgetsBundle.swift`, new `BondWidgets/IntentHandlers.swift`

### 3.2 Live Activity for upcoming reminder countdown
**Problem:** No lock screen/dynamic island presence for imminent reminders.  
**Fix:** Start `Activity` when a reminder's `fireAt` is within 1 hour. Displays countdown, love language icon, title. Ends on fire (delivered) or manual dismiss.  
**Files:** New `Bond/Features/LiveActivity/LiveActivityAttributes.swift`, `Bond/LiveActivity/LiveActivityView.swift`

### 3.3 Additional widget sizes
**Problem:** Only systemSmall and systemMedium.  
**Fix:** Add systemLarge showing full upcoming list + milestone + stats preview. Add accessoryCircular/rectangular for lock screen.  
**Files:** `BondWidgets/BondWidgetsBundle.swift`

### 3.4 App Intents / Siri Shortcuts
**Problem:** No Siri/Shortcuts integration — "Hey Siri, create a reminder in Bond" doesn't work.  
**Fix:** Add `CreateReminderIntent` (title, loveLanguage, trigger) and `ShowNextReminderIntent`. Register as `AppShortcutsProvider`.  
**Files:** New `Bond/Intents/AppIntents.swift`

### 3.5 Notification Content Extension
**Problem:** Push notifications show default banner — no rich content (love language icon, action buttons).  
**Fix:** Add `UNNotificationContentExtension` target with custom UI showing love language, full note, "Mark complete" and "Snooze 1h" buttons.  
**Files:** New `NotificationExtension/` target

### 3.6 Rich notifications (media attachments)
**Problem:** Push payload is plain text only.  
**Fix:** APNs payload could include love-language SF symbol as image attachment (rendered server-side or locally mapped).  
**Files:** `SupabaseFunctions/send-push/index.ts` + notification content extension

---

## Phase 4 — Feature Expansion

### 4.1 Reminder events & completion tracking
**Problem:** `reminder_events` table exists but is unused in the app — reminders have no "mark complete" flow.  
**Fix:** Add "Mark as done" action. Log to `reminder_events`. Show completion history and streaks. Stats view shows completion rates.  
**Files:** `Bond/Services/ReminderEventsService.swift`, `ReminderDTO` updates, `StatsView` updates

### 4.2 Streak tracking
**Problem:** No gamification.  
**Fix:** Track consecutive days with at least one completed reminder. Show streak count in Stats or a new StreakView. Use `reminder_events` dates grouped by day.  
**Files:** New `Bond/Services/StreakService.swift`

### 4.3 Reminder templates
**Problem:** Users must create every reminder from scratch.  
**Fix:** Pre-built template collections — "Romantic Date Night" (quality time + physical touch), "Long Distance" (words + gifts), "New Parents" (acts of service + time). Single tap to add all.  
**Files:** New `Shared/Models/ReminderTemplate.swift`, UI in `ReminderListView`

### 4.4 AI-powered suggestions (using existing `ai_usage` table)
**Problem:** `ai_usage` table exists in schema but is unused.  
**Fix:** Integrate with an LLM (OpenAI/Anthropic via Supabase Edge Function) to suggest reminders based on past patterns, love language gaps, partner stats. Track rewrite/suggest usage.  
**Files:** New Supabase Edge Function, new UI suggestion banner in `ReminderListView`

### 4.5 iPad support
**Problem:** Portraits-only iPhone app, no adaptive layout.  
**Fix:** Use `NavigationSplitView` for sidebar + content layout on regular width. Enable all orientations for iPad.  
**Files:** `Bond/Info.plist`, `BondApp.swift`, view layout adjustments

### 4.6 Vision Pro support
**Problem:** No visionOS target.  
**Fix:** Add `project.yml` target for visionOS. Reuse Shared code. Adapt UI for spatial computing — floating panels, 3D love language icons, SharePlay viewing.  
**Files:** New `BondVision` target

---

## Phase 5 — Testing (Major Gap)

### 5.1 Add test targets to project.yml
**Problem:** Zero test targets exist.  
**Fix:** Add `BondTests` (unit) and `BondUITests` (UI) targets to `project.yml`.  
**Files:** `project.yml`

### 5.2 Unit tests for services
- **ReminderRepository:** Test CRUD, realtime subscription setup, filter/pagination logic, `onChange` callback dispatch
- **PairingService:** Test solo couple creation, invite code generation/consumption, partner profile loading, URL handling
- **MilestonesService:** Test CRUD, next occurrence computation
- **PurchasesService:** Test premium state mapping
- **NotificationScheduler:** Test trigger→UNNotificationTrigger mapping for all 4 trigger types and all recurrence presets

### 5.3 Unit tests for models
- **MilestoneDTO:** `nextOccurrence()` — leap years, year boundary, monthly recurrence
- **RecurrencePreset:** RRULE string generation for all presets
- **ReminderTrigger:** Codable round-trip for all 4 cases + Geofence
- **LoveLanguage:** All 5 cases have valid symbolName, title, tint

### 5.4 UI tests for critical flows
- **Onboarding:** Apple Sign-In flow (mock provider)
- **Reminder creation:** Fill form, all 4 trigger types, save, verify in list
- **Reminder edit/delete:** Tap row, modify, save; swipe-to-delete
- **Milestone CRUD:** Create, edit, delete
- **Premium gating:** Verify lock screens appear for non-premium
- **Pairing flow:** Generate code, consume code, verify couple state

### 5.5 Snapshot tests
**Problem:** No visual regression testing.  
**Fix:** Add `swift-snapshot-testing` library. Capture snapshots of all major views in various states (empty, populated, premium-locked, error).  
**Files:** New `BondSnapshotTests` target

---

## Phase 6 — Backend & Database

### 6.1 Database indexes
**Problem:** No explicit indexes beyond PKs — `reminders.couple_id`, `milestones.couple_id`, `reminders.fire_at` are queried frequently without indexes.  
**Fix:** Add indexes for all foreign keys and filtered queries.  
**Files:** New `supabase/migrations/0003_indexes.sql`

### 6.2 Retention policy for stale data
**Problem:** No cleanup — old reminder_events, expired invite_codes, soft-deleted reminders accumulate.  
**Fix:** Add Supabase scheduled function (pg_cron) to delete events >90 days, expire codes >7 days, purge 0002-level stale rows.  
**Files:** New `supabase/migrations/0004_retention.sql`

### 6.3 Type safety in edge function
**Problem:** `send-push/index.ts` uses `any` types for request payload.  
**Fix:** Add full TypeScript types for `WebhookPayload`, `APNsPayload`, `ProfileRow`. Validate payload shape at entry.  
**Files:** `SupabaseFunctions/send-push/index.ts`

### 6.4 Add READ receipts to push
**Problem:** No confirmation partner saw the notification.  
**Fix:** Track push delivery via APNs `apns-push-type` response. Add `delivered_at` and `read_at` to `reminder_events`.  
**Files:** `SupabaseFunctions/send-push/index.ts`, `reminder_events` schema update

### 6.5 Database migration for soft-delete
**Problem:** Reminder delete is hard delete — no undo, no audit trail.  
**Fix:** Add `deleted_at` timestamp to `reminders` and `milestones`. Update RLS to exclude soft-deleted rows. Add "Recently Deleted" recovery UI.  
**Files:** New migration, service updates

---

## Phase 7 — CI/CD & Automation

### 7.1 GitHub Actions workflow
**Problem:** No CI — every build/test/upload is manual.  
**Fix:** Add workflow for:
- PR validation: `xcodegen generate` → build all targets → run tests → lint
- Release: bump build → archive → upload to TestFlight → tag
- Schedule: nightly test run  
**Files:** `.github/workflows/ci.yml`, `.github/workflows/release.yml`

### 7.2 Fastlane integration
**Problem:** Upload scripts are bash-only, no code signing management.  
**Fix:** Migrate `scripts/testflight.sh` to Fastlane lanes: `build`, `test`, `beta`, `release`. Match code signing via `match`.  
**Files:** `fastlane/Fastfile`, `fastlane/Appfile`, `fastlane/Matchfile`

### 7.3 Danger (or similar) for PR automation
**Problem:** No automated PR review — changelog, size warnings, test coverage.  
**Fix:** Add `Danger` Swift to check PR conventions.  
**Files:** `Dangerfile.swift`

---

## Phase 8 — Polish & UX

### 8.1 Accessibility pass
- **Dynamic Type:** Audit all views for legibility at all content size categories
- **VoiceOver:** Add proper `accessibilityLabel`, `accessibilityHint`, `accessibilityValue` to all interactive elements
- **Reduce Motion:** Respect `UIAccessibility.isReduceMotionEnabled` for transitions
- **Reduce Transparency:** Check all `.ultraThinMaterial` backgrounds
- **Switch Control:** Ensure all actions are reachable

### 8.2 Haptic feedback
- **Problem:** No tactile feedback on reminder completion, milestone reached, pairing success
- **Fix:** Add `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` at key interaction points

### 8.3 Empty states
- **Problem:** `ReminderListView`, `MilestonesView`, `StatsView` may show blank views when empty
- **Fix:** Add illustrated empty states with CTA buttons ("Create your first reminder")

### 8.4 Loading & error states
- **Problem:** Some views show no loading indicator during async ops; errors appear as inline text only
- **Fix:** Standardize loading overlay, toast/banner for errors, retry button

### 8.5 Widget configuration (select which reminder list)
- **Problem:** Widget always shows the single next reminder — no user choice
- **Fix:** Add `ConfigurationAppIntent` to let users pick a specific love language filter or reminder

---

## Phase 9 — Codebase Health

### 9.1 Extract services to framework target
**Problem:** `Shared/` is compiled into all 3 targets, but some service code is iOS-only. Services and models should be in a proper SPM framework for explicit dependency control and faster compile times.  
**Fix:** Create `BondShared` Swift package. Move `Shared/` and relevant services.  
**Files:** New `Packages/BondShared/`

### 9.2 Docs generation (DocC)
**Problem:** No API documentation.  
**Fix:** Add DocC documentation comments to all `@Observable` services and public models. Configure DocC catalog for hosted documentation.  
**Files:** Inline `///` comments, new `Bond.docc/`

### 9.3 Dependency graph audit
**Problem:** `project.yml` shows Bond depends on BondWidgets and BondWatch — this is backwards (the app shouldn't depend on its extensions).  
**Fix:** Separate into independent schemes or use correct embedding relationships. Extensions depend on the app, not vice versa.  
**Files:** `project.yml`

### 9.4 Dependency injection framework
**Problem:** Manual `@Environment` injection works but forces all services to be singletons.  
**Fix:** Consider `Factory` or a lightweight DI container for testable service lifetime management.  
**Files:** New `Bond/Services/ServiceContainer.swift`

---

## Priority Matrix

| Priority | Phase | Effort | Impact | Why Now |
|----------|-------|--------|--------|---------|
| 🔴 P0 | 1.1–1.5 | Low | High | Eliminates known duplication, improves structure |
| 🔴 P0 | 5 | High | Critical | Zero tests is a blocker for any refactoring |
| 🔴 P0 | 1.7–1.8 | Low | Medium | Structured errors + logging needed for debugging |
| 🟡 P1 | 2.1–2.4 | Medium | High | Watch is one-directional and limited |
| 🟡 P1 | 3.1–3.2 | Medium | High | iOS 17 interactivity + Live Activities are table stakes |
| 🟡 P1 | 7 | Medium | High | No CI means every release is risky |
| 🟢 P2 | 4.1–4.2 | Medium | High | Core feature gap — reminders have no completion flow |
| 🟢 P2 | 6.1–6.3 | Low | Medium | Database performance and hygiene |
| 🔵 P3 | 4.5–4.6 | High | Medium | New platforms, significant scope |
| 🔵 P3 | 3.3–3.6 | Medium | Medium | Widget/Siri richness |
| 🔵 P3 | 8 | Medium | Medium | UX polish |
| ⚪ P4 | 9 | High | Low | Codebase health, no user-facing impact |

## Recommended Sequence

1. **Phase 1** (code quality) — do first, low risk, immediate improvement
2. **Phase 5** (testing) — must exist before any refactoring is safe
3. **Phase 1.6–1.8** (SwiftLint, errors, logging) — enables enforcement
4. **Phase 7** (CI/CD) — automation makes all future work safer
5. **Phase 2** (watch modernization) — biggest UX gap
6. **Phase 3** (widgets/Live Activities/Siri) — platform feature leverage
7. **Phase 4.1–4.2** (events & streaks) — core mechanics missing
8. **Phase 6** (backend) — performance and data hygiene
9. **Phase 8** (polish) — UX depth
10. **Phase 9** (codebase health) — long-term maintenance
