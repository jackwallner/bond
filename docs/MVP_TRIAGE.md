# Bond — MVP Release Triage

> Phase 1 audit, read-only. No code changed.
> **Assumption (please confirm):** MVP audience = TestFlight friends & family (10–50 users), not public App Store launch. Several P1s would escalate to P0 for public launch (esp. settings/sign-out, push reliability, App Store metadata).

---

## 0. Build & test status

| Check | Result |
|---|---|
| `xcodegen generate` | OK |
| `xcodebuild ... build` (Bond + BondWidgets, iPhone 17 sim) | **BUILD SUCCEEDED** |
| `xcodebuild ... test` (BondTests) | **TEST SUCCEEDED** — 56 tests / 10 suites / 0 failures |
| Warnings | 1: unused `actedReminderIds` in `ReminderListView.swift:92` (dead code from incomplete past/upcoming logic — see B1) |

Watch target (`BondWatch`) was not built in this pass (separate scheme).

---

## 1. Feature walkthrough

| Feature | Happy path | Status |
|---|---|---|
| **Onboarding (SIWA)** | App → SignInWithApple → Supabase session | ⚠ Working but **fragile**: visible SIWA button is decorative; sign-in actually runs through a transparent `Button` overlay (see B2). Apple review risk. |
| **Pairing** | Generate code → share universal link → partner consumes | ✅ Works. No QR, no in-app code reader beyond manual paste. Universal link domain `bond.jackwallner.com` — AASA must be hosted there. |
| **Solo mode** | "Just me" → `create_solo_couple` RPC → home | ✅ Works. |
| **Reminders — create/edit/delete** | Editor → save → list refresh → notifications scheduled | ✅ Core works. Bugs: recurring reminders incorrectly grouped as "past" once first fire date passes (B1); partner-targeted reminders never schedule a local notification & push isn't wired (B3). |
| **Reminders — mark done** | Swipe → event row inserted | ⚠ Half-built. Inserts `reminder_events` row, but reminder itself stays "scheduled" forever. No way to actually complete a one-time reminder. Tap-to-edit still works on completed rows. |
| **Templates (premium)** | Pick group → "Add N reminders" | ⚠ Works but every template fires at `now + 1h` regardless of recurrence anchor; 4 reminders in a group all fire at the same minute (B4). |
| **Milestones (premium)** | Create/edit/delete countdown | ✅ Works. Leap-year/year-boundary covered by tests. |
| **Daily Check-In (premium, paired only)** | Daily question → both answer → reveal partner | 🔴 **Broken core feature.** Question selection uses `coupleId.uuidString.hashValue` as a seed — Swift's `hashValue` is randomized per process. Partners on the same day get **different questions**; the same user gets different questions across app launches (B5). |
| **Stats / Insights (premium)** | Charts, streaks, balance score | ✅ Renders. Streak math reasonable. `weeklyTrends` chart uses `.position(by:)` inside `ForEach` — may overlap visually with sparse data, cosmetic only. |
| **Paywall** | `RevenueCatUI.PaywallView` | ✅ Standard. RevenueCat API key hardcoded — public key, fine. |
| **Widgets** | UpcomingReminder + AnniversaryCountdown | ✅ Snapshot pumped from app on every change. Empty state present. |
| **Watch — dictate reminder** | Type text → send to phone → phone creates row | ⚠ "Sent" UI message lies: bridge silently drops payload if phone has `coupleId == nil` (B6). Watch can only target self, fixed 1h offset. |
| **Watch — view/manage reminders** | n/a | ❌ Not implemented. Acceptable MVP scope. |
| **Sign out / account management** | n/a | ❌ **No settings screen anywhere.** No sign-out, no privacy link, no support contact, no version info (B7). |
| **Push notifications** | Edge function `send-push` exists | 🔴 **Not wired.** No APNs token registration in `BondApp`, no `UNUserNotificationCenter.delegate`, `apns_token` never written to `profiles` (B3). |

---

## 2. Bugs & risks (B1–B12)

### B1 — Recurring reminders permanently land in "Past" section
`ReminderListView.grouped` (line 88) sorts reminders into upcoming/past by `trigger?.nextFireDate < now`. For `.recurring(rrule, nextFire)` the date comes straight from `fireAt` in the DB row — which is never advanced after firing. Once `fireAt` is in the past, every recurring reminder is "Past" forever. The unused `actedReminderIds` variable on line 92 is a vestige of the half-built fix.

### B2 — Sign-in-with-Apple button is a stack of two views
`OnboardingView.swift:1423`. The native `SignInWithAppleButton` has an empty `onCompletion`; a transparent `Button` is overlaid on top to drive `AppleSignInHelper`. Risks:
- Apple App Store review may reject (button must actually perform SIWA action)
- VoiceOver announces the overlay, not "Sign in with Apple"
- Hit area drifts on Dynamic Type / iPad multitasking

### B3 — Push notifications don't work
- No `UIApplicationDelegate` registration for remote notifications anywhere in `BondApp`
- `apns_token` column on `profiles` is never written from the client
- `NotificationScheduler.reschedule(forSelfUserId:)` only schedules local notifications **where `targetId == selfId`**, so partner-targeted reminders rely entirely on push
- **Result:** if you create a reminder targeting your partner, neither device will fire a notification.

### B4 — Templates fire all at once, 1h from creation
`TemplateGroupDetailView.createAll` uses `Date().addingTimeInterval(60 * 60)` for every template's `fireAt` regardless of `triggerRecurrence`. A user adding "New Parents" gets 4 daily reminders all anchored to the same minute.

### B5 — Daily Check-In uses random per-process seed
`DailyCheckInService.loadTodaysQuestion`:
```swift
let coupleSeed = coupleId.uuidString.hashValue   // randomized per process!
let questionIndex = abs((dayOffset + coupleSeed) % count)
```
Swift's `String.hashValue` is salted per app launch since Swift 4.2. Two partners on the same day see different questions, and a single user sees a different question each cold start. Use a stable hash (`coupleId.uuidString.utf8.reduce(0, { ($0 &* 31) &+ Int($1) })` or a deterministic UUID byte sum) or just use `coupleId.uuid.0 & 0xff` etc.

### B6 — Watch shows "Sent" even when reminder was dropped
`WatchConnectivityBridge.createReminder` returns silently if `coupleId` or `currentUserId` is nil. Watch UI displays "Sent — will fire in ~1h." regardless. Common case: user opens watch app before phone has loaded session.

### B7 — No Settings / Account screen
There is no UI to sign out, see the paired partner's identity, unpair, view a privacy link, get help, or know the app version. This blocks: (a) testing the second account during pairing QA, (b) App Store privacy-URL requirement (if you go public), (c) any "I'm stuck" recovery for a TestFlight user.

### B8 — Location reminders need "Always" auth but only request "When in use"
`LocationService.currentLocation()` calls `manager.requestWhenInUseAuthorization()`. Info.plist declares `NSLocationAlwaysAndWhenInUseUsageDescription`, but the upgrade to Always is never requested. Geofence reminders won't fire while the app is backgrounded → core feature value gone. (Premium, so paywalled users get the worst experience.)

### B9 — Random-window reminder is one-shot
After firing, the random window is exhausted — never re-rolls. "Random surprise" is one surprise, ever, per reminder.

### B10 — Reminder filter "For Me" can produce a misleading empty state
`ReminderListView` empty-state check uses `repo.reminders.isEmpty`, not `filteredReminders.isEmpty`. Switching the filter when nothing matches yields a blank list with no copy.

### B11 — `lastError` never cleared
`PairingService.lastError` is set on failure but never reset on retry success. Old errors linger across the UI (`PreferenceChoiceView`, `PairingView`).

### B12 — Realtime channel doesn't re-subscribe after pairing change
`ReminderRepository.subscribeRealtime()` early-returns if `realtimeChannel != nil`. If a user goes from solo → paired (or accepts an invite), the channel is filtered by the old `coupleId`. Edge case but real.

### Minor
- `inviteCodeAlphabet.randomElement()!` — force unwrap on static array, always safe; cosmetic.
- `NotificationScheduler.removeAllPendingNotificationRequests()` clears non-Bond app notifications too if anyone added some via extensions later. Defensive only.
- `SupabaseConfig` ships anon key in Info.plist — fine by design.
- No `UNUserNotificationCenter.delegate` set → tapping a local notification doesn't deep-link to the reminder.

---

## 3. MVP gaps (features a user would expect)

| Gap | Impact |
|---|---|
| No sign-out / settings screen | High — blocks QA and feels broken |
| No "what does this do" explainer after sign-in | Medium — pairing screen is the first thing seen, no app tour |
| No notification permission primer | Medium — system prompt fires from `NotificationScheduler` only after first reminder save; users may decline without context |
| No empty-state CTA in reminders list to open templates | Low — feature is discoverable via toolbar |
| Cannot snooze / dismiss a fired reminder from notification | Medium — only "default" tap behavior; no actions |
| Cannot "mark complete" a one-time reminder so it disappears | High — clutter accumulates |
| No partner avatar / display name shown anywhere in the home UI | Low — `partnerProfile` is loaded but unused |
| No iPad-friendly layout | Low — `TARGETED_DEVICE_FAMILY: "1"` is iPhone-only; fine |
| No "Recently Deleted" recovery | Low |

---

## 4. Prioritized list

### 🔴 P0 — must fix before TestFlight
Justification: each one either crashes the experience, breaks a core advertised feature, or risks Apple review/data loss.

1. **B5** Daily Check-In uses unstable seed — feature is shipped & paywalled but produces wrong content. *Hot fix: deterministic hash.*
2. **B3** Push notifications not wired (no APNs token registration) — partner-targeted reminders never notify anyone. If push isn't realistic for MVP (paid Dev account / APNs key not set up), fallback: schedule local notifications on **both** devices, dedup by author client-side. *Decision point — confirm scope.*
3. **B1** Recurring reminders permanently shown as "Past" — the most-used reminder type appears broken on day 2. *Hot fix: re-derive next fire date with `RecurrencePreset.nextOccurrence(after:)`.*
4. **B2** SIWA decorative button — Apple review risk. *Fix: drop the overlay, use `SignInWithAppleButton`'s built-in completion handler.*
5. **B6** Watch reports "Sent" when reminder was dropped — silent data loss. *Fix: propagate failure back to watch and show "Open Bond on phone first."*
6. **B7** No sign-out / settings — blocks TestFlight QA (can't test two accounts on one device). *Fix: minimal Settings tab with Sign Out, paired-partner name, version, support link.*

### 🟡 P1 — visibly broken or confusing, fix if cheap
7. **B8** Location reminders never fire in background (premium feature value gone). *Fix: request Always auth at editor open; gate location trigger behind that grant.*
8. **B4** Template reminders all fire simultaneously at `now + 1h`. *Fix: stagger or use recurrence-aware anchor.*
9. **B10** Empty state misleading when filter active.
10. **B11** Stale error messages linger across screens.
11. Notification tap doesn't deep-link to reminder (`UNUserNotificationCenter.delegate` unset).
12. No notification permission primer screen before the system prompt.
13. **B9** Random-window reminders one-shot — at minimum document, ideally re-roll on fire.

### 🟢 P2 — defer past MVP
- B12 Realtime channel re-subscription
- Mark-complete UX on one-time reminders (event log exists; surface in Stats only for now)
- Empty-state CTA → Templates
- Partner avatar / display name surfaces in chrome
- iPad layout, Live Activities, Siri intents, Interactive widgets
- LoveLanguageAnalyzer chart polish, Insights copy variations
- "Recently Deleted" / soft delete
- Service-layer DI for testability
- All of Plan §3.x–9.x

---

## 5. Recommended sequence (P0 + P1 only, ~6–10 commits)

```
fix: daily check-in uses deterministic couple seed                 (B5)
fix: recurring reminders re-compute next fire date for grouping    (B1)
fix: SIWA uses native button completion handler                    (B2)
fix: watch surfaces send failure when phone has no couple loaded   (B6)
feat: minimal Settings screen with sign-out                        (B7)
fix: register APNs token + persist to profiles                     (B3 — or decide to defer push to v1.1 and add local-on-both fallback)
fix: request Always location auth before saving geofence reminder  (B8)
fix: templates stagger fireAt by recurrence and offset             (B4)
fix: reminder list empty state respects active filter              (B10)
fix: clear stale pairing errors on retry                           (B11)
```

Each commit: implement → `xcodebuild build` → `xcodebuild test` → commit. One concern per commit per global rules. Stop and re-check if any "fix" turns into a redesign (esp. B3 push wiring — that's a project, not a fix).

---

## 6. Decisions I need from you before Phase 3 (writing code)

1. **Audience confirm.** TestFlight friends/family, or do you want App Store-ready? (Changes whether B7 settings, privacy policy link, App Store metadata are P0.)
2. **Push.** Do you have an APNs key / paid Dev account set up? Three options:
   - (a) Wire push now (B3 stays P0, ~half day)
   - (b) Defer push to v1.1, ship with local-only notifications + caveat that partner reminders only notify the partner if they have the app open (cheap)
   - (c) Hide partner targeting from the editor entirely until push works (most honest)
3. **Daily Check-In.** Confirm it's intended for MVP — it's gated premium, broken, and would feel sad if shipped half-working. Cheap to fix (B5) so I'd vote yes.
4. **Watch dictate.** OK to leave one-way + self-targeted only?
5. **Templates fireAt.** What's the desired UX — stagger (e.g. one per day for 4 days)? Anchor to a user-picked start time? Just fix to a sane recurrence start?
6. **WIP commit.** The current branch has ~13 modified files + a pile of new ones. I'd recommend committing the existing WIP as a `feat: premium features WIP` checkpoint before I start fixes, so my diff is reviewable. Want me to do that as commit #0?
