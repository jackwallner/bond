# State machine audit, 2026-11-06

Scope: iOS app, `Shared/`, widgets, watch, and `SupabaseFunctions/send-push` plus migrations 0001 to 0014 (read only). Android out of scope. Tree audited: branch `fleet/20261106-142641-5308-claude` at `cee122f`; `git stash -u` found nothing to stash. No app code changed, no bug fixed.

**Summary: 16 bugs. 6 proved by a failing test (6 of 6 failed, 6 of 6 controls passed), 10 code path only.** 10 further items are product calls and are not counted.

Test run: `gh-sim test --scheme Bond --only BondTests/StateMachineAuditRepro`, run `bond@20261106-142641-5308-claude-imac4a60-1106-152539-5344` (Xcode 27.1, iPhone 17, iOS 27.2). Suite: `state-machines-2026-11-06-repro.swift` in this folder. Values quoted below are copied from that run's `test.log`.

Test seams that exist, and what I used: `ReminderRepository.loadRows / insertRows / rescheduleRow / currentUserId / scheduleNotifications / armingContext` (used: sm1, sm2, sm5); `PairingService.fetchCouples / onRelationshipChange` (sm4); `SupabaseService.restoreSession / signInWithApple(link:signIn:)` (not needed); `MilestonesService.loadRows / scheduleNotifications / deleteRow` (not needed); `ConversionDiagnostics.defaultsOverride` (not needed); pure functions `isCompleted`, `currentCompletionEvent`, `currentPeriodStart(at:calendar:)`, `LoveLanguageAnalyzer`, `WidgetSnapshot.make` (sm1, sm3, sm6). Seams that do **not** exist, which is why ten claims stay Code path: `NotificationScheduler` hard-codes `UNUserNotificationCenter.current()` (no fake, and a test host cannot add or read real requests), `PurchasesService.apply` is private and `CustomerInfo` has no public initializer, `ReminderEventRepository` and `DailyCheckInService` call the Supabase client directly, and views keep their logic in private members and `@State`. I did not add a fake to app code (not allowed).

Caveat on two tests. sm5 uses a repository with no couple as the stand-in for a failed completions fetch: my first version tried a real request, which succeeded against the configured backend and returned zero rows (`[events] Refreshed 0 events`), so the "failed" precondition did not hold and I rewrote it. The failure path itself (`ReminderEventRepository.swift:34-37`) leaves `events` at its initial `[]`, the same value. sm4 relies on the partner-profile request failing; in the run it did (`[pairing] loadCouple failed (state kept): Cannot coerce the result to a single JSON object`) and the test asserts that precondition.

## Bugs, ranked by impact (users reached x cost to them)

| Id | Bug | What the user sees | Promise (file:line) | Route | Impact | Evidence | Code |
|---|---|---|---|---|---|---|---|
| B1 | Unpair does not stop the server pushing the other partner's reminders | After Unpair, the partner's recurring or future reminders for me keep arriving on my phone, and I cannot see or delete them | `SettingsView.swift:76` "Unpairing immediately stops your partner from sending you anything." | Settings tab > Pairing > Unpair > confirm | Every unpaired user whose partner had written a recurring or still-due reminder for them, and whose phone registered for push (notifications allowed, any device on the shipping build). Highest cost: it is the abuse case the Unpair copy and "Report a concern" exist for | Code path | `0009_leave_couple_split.sql:81-93` (updates `couple_id` only); `0014:219-223` (queue trigger columns exclude `couple_id`); `0014:330-338` (claim joins `push_devices` on target, no couple check); `0014:355` (recurring rows re-queue) |
| B2 | A launch that knows no completions rebuilds every notification as if nothing was done | A reminder marked Handled before its time (or a daily random one done today) pings again | `ReminderRepository.swift:119-123` "A rebuild replaces every pending notification with what `reminders` says, so it waits for a successful fetch"; `NotificationScheduler.swift:24-26` events exist "so a handled one-shot stops pinging" | Launch (or silent-push launch) when the reminders request succeeds and the completions request fails or has not landed; Reminders tab `.task` | Anyone with a handled, still-future one-shot or a done daily-random reminder, on a flaky launch (two sequential requests, one fails). Silent-push launches always start with `events == []` | Test sm5: `rebuilt → [[]]`, "rebuilt every pending notification from completions=0"; control passes | `ReminderListView.swift:114-126`, `ReminderRepository.swift:128-130`, `:157-164`, `BondApp.swift:33-41`, `ReminderEventRepository.swift:34-37`, `NotificationScheduler.swift:49-51` |
| B3 | Daily template packs cannot arrive "one at a time" | Importing New Parents (4 daily reminders) gives four notifications at 9:00 every day, starting at the next 9:00 | `ReminderTemplatesView.swift:185` "spread across the coming days so they arrive one at a time, not all at once" | Reminders tab > Templates row (Bond+) > New Parents > Add 4 reminders; solo or paired | Bond+ users who import a pack with 2 or more dailies (Daily Affirmations 2, New Parents 4, Daily Appreciation 2). Repeating triggers carry hour and minute only, so a day offset cannot separate dailies | Code path | `ReminderTemplatesView.swift:210-215` (same 9:00, offset in whole days); `NotificationScheduler.swift:250-253,291` (daily trigger = hour+minute, repeats); server mirror `0014:99-101,118-122` (same time of day after day 3) |
| B4 | Insights count and name the partner's own reminders | Total reminders, balance score and Follow-through list include (and print the titles of) reminders my partner made for themselves | `ReminderListView.swift:186-187` "Everything the user should see: their own reminders (regardless of target) plus reminders the partner addressed to them"; `WidgetSnapshot.swift:66-72`; `ReminderEditorView.swift:291` "Only you see this one." (unfolded Duo preview) | Partner A: Reminders > + > For: Me > Recurring > Every day > Save. Partner B (Bond+, paired): Insights tab > Follow-through, and Summary > Total reminders | Every paired Bond+ couple where either writes a recurring reminder for themselves (counts leak for all reminders, titles for recurring ones). Medium frequency, medium cost (private note titles) | Test sm1: total `2` not `1`; follow-through `["Mine", "Partner private"]`; widget control passes | `StatsView.swift:11-13,62,164-193`, `LoveLanguageAnalyzer.swift:17-21,97-116` |
| B5 | Tapping a reminder banner while the editor is open loads a different reminder into the old form | Saving writes the first reminder's title, note, language and schedule over the second reminder | Editor Save implies the form shows the reminder being saved (`ReminderEditorView.swift:496-541`) | Reminders tab > tap reminder A (editor open, edit) > another reminder's banner arrives (`NotificationRouter.swift:34`) > tap the banner > Save | Foreground users editing when a reminder fires. Low frequency, high cost (overwrite, no undo) | Code path | `ReminderListView.swift:156-163` sets `editingReminder` while `isEditorPresented` is already true; `UnfoldedSplit.swift:372-374` re-runs the content closure; `ReminderEditorView.swift:134` hydrates `@State` only `onAppear`; `:517-541` overwrites every field from state |
| B6 | Daily random reminders stop after 5 idle days | "Fires once a day" stops firing on day 6 without opening the app | `ReminderEditorView.swift:418` "Fires once a day, at a different random time in this window each day." | Reminders > + > Schedule: Random surprise (Bond+) > Repeat every day > Save; do not open the app for 6 days | Bond+ users of daily random who ignore banners rather than tap them (a tap opens the app and re-lays 5 days). Medium cost: silent stop | Code path | `NotificationScheduler.swift:151,160` (5 one-time requests, no background refresh); no BGTask or timer in the repo |
| B7 | Couples in different time zones get different "today" questions | Each partner sees "Waiting on partner" while the partner answered another question | `DailyCheckInView.swift:53` "seeing each other's response once you've both replied"; `DailyCheckInService.swift:39` partners must see the same question | Both partners Bond+, paired, far apart (the Long Distance pack targets them). Check-In tab, any time the two local dates differ | Bond+ long-distance couples 5 or more hours apart: the dates differ for 5 or more hours of every day (for example New York and Tokyo for about 13) | Code path | `DailyCheckInService.swift:37-43` (local-day ordinal), `:80-89` (match by question id) |
| B8 | Undo of a completion can leave the reminder done | "Not done" swipe or circle tap does nothing visible, once per extra event | `ReminderListView.swift:500-503` "...makes undo look broken because deleting one still leaves the reminder 'done'" (author names the failure) | Partner A and partner B both see the reminder (author and target); A taps Done; B's list is stale (events are not on the realtime feed) and B taps Done; either swipes Not done. Also: insert ok, re-read failed, user taps Done again | Couples sharing a reminder, plus flaky connections. Low-medium frequency, low cost | Test sm6: "Not done left 1 completion(s) in place"; control passes | `ReminderListView.swift:504,519-520`, `ReminderCompletion.swift:45-49`, `ReminderEventRepository.swift:57-69`, `0001_init.sql` (no unique key) |
| B9 | Local recurring triggers ignore the "Starting" date | A daily reminder set to start next month pings tomorrow; a yearly "Starting 2027" pings this year | `ReminderEditorView.swift:373` label "Starting"; the row shows the anchor date (`ReminderRow.swift:82`, `ReminderTrigger.swift:41-48`) | Reminders > + > Recurring > Starting: a date more than one period ahead > Save | Anyone who sets a start beyond the next occurrence (free tier included). Monthly on the 29th to 31st also skips short months locally while the server clamps | Code path | `NotificationScheduler.swift:250-253,285-299` (components drop the anchor date) vs `0014:99-101` (server honours it) |
| B10 | Local calendar triggers float with the device time zone | After flying, one-time and random reminders fire at the same wall-clock time in the new zone, hours off the instant the list shows, until the app is opened | List row shows the stored instant (`ReminderRow.swift:82`) | Schedule a one-time reminder in Pacific time, change zone to Eastern (travel), do not open the app | Travellers across zones with pending reminders. Low frequency, low-medium cost | Code path | `NotificationScheduler.swift:124,245,271` (components without `timeZone`); no zone observer (grep `TimeZoneDidChange` empty) |
| B11 | Apple sign-in that recovers an older account leaves the old couple in memory | The recovered account looks empty ("Your list is clear") until the app is backgrounded and reopened; saving errors | `SupabaseService.swift:165-169` "so they can recover that account" | Settings > Pairing > Connect a partner > Sign in with Apple (Apple ID already linked to an older Bond account, reinstall case) > close sheet > Reminders | Reinstalling users who had linked Apple. Low frequency, looks like data loss (recovers on next foreground) | Code path | `SupabaseService.swift:149-179`; `PairingView.swift:359-377` only calls `identify` and `consumeDeferredInviteIfNeeded`, never `loadCouple`; `ReminderListView.swift:188-191` then filters on the new id |
| B12 | A Done that failed to save still counts as a positive moment | Tap Done offline: nothing changes, no message, yet the review prompt counter moves | `AGENTS.md` "the positive moment is marking a reminder done"; `docs/review-prompt.md` "after a positive moment (reminder completed)" | Offline: Reminders > tap the check circle | Offline or flaky users. Low cost | Code path | `ReminderListView.swift:507-510` (`try?` swallows, then `recordPositiveMoment`) |
| B13 | A half-failed couple lookup leaves "paired with no partner" | After pairing on a bad connection the app is paired but has no partner name, and "For: Partner" saves for me | `PairingService.swift:102-103` "keep whatever state we had" | Pair (code entry or link) while the profiles request fails; New reminder > For: Partner > Save | Pairings on a flaky connection. Low frequency, a reminder silently addressed to self | Test sm4: `coupleId` changed, `solo=false`, `partnerProfile` nil, `told → 1`; control passes (editor retarget at `ReminderEditorView.swift:503-506` is code path) | `PairingService.swift:75-107` |
| B14 | A save whose re-read fails arms the old time | Reschedule a reminder, bad connection: the old time is armed and listed, the sheet said saved | `launch-and-schedule.md` "Anything new that writes reminders must end in `rescheduleNotifications`" (it rebuilds, from the old list) | Reminders tab > partner's reminder card > Reschedule > pick a time > Save, with the next request failing | Rare: a failure between two sequential requests. Heals on next foreground | Test sm2: armed `2026-11-07 01:50:08 +0000`, saved `05:50:08 +0000`; control passes | `ReminderRepository.swift:166-197`, `ReminderEditorView.swift:608-609` |
| B15 | Weekly "done" window differs between app and server on Sunday-first locales | A weekly partner reminder marked done on Saturday: the app shows it open on Sunday, the server skips Sunday's push | `0014:132` "Mirrors ReminderCompletion" | Partner-written weekly reminder; target (en_US, Sunday-first) taps Done Saturday; due Sunday | en_US and other Sunday-first locales with weekly partner reminders, done on the boundary day. Low | Test sm3 (client half): device `2026-11-08 08:00 +0000`, server week start `2026-11-02 08:00 +0000`; Monday-first control passes. Server half is SQL read | `ReminderCompletion.swift:23`, `0014:144-152` |
| B16 | "Bond+ since" shows the latest renewal, not the start | A yearly subscriber after renewal, or a monthly one every month, reads "since" the latest charge | `SettingsView.swift:90` "Little Gestures+ since <date>" | Settings tab > Little Gestures+ section as a renewed subscriber | Every renewed subscriber, cosmetic | Code path | `PurchasesService.swift:425-428` uses `latestPurchaseDate` (RevenueCat: latest purchase or renewal) not `originalPurchaseDate`. Settle with a sandbox renewal |

What would settle each Code path claim: B1 run `scripts/test-db.sh` extended with: couple A+B, B-authored daily reminder targeting A, `register_push_device` for A, `leave_couple(A)`, set `next_push_at` to the past, then `claim_due_reminder_pushes()` must return no row for A. B3, B9, B10: a device or a seam-injected fake behind `UNUserNotificationCenter` that records `nextTriggerDate()` of the pending requests after import, after a Starting date, and after a zone change. B5: a UI test that opens reminder A, posts a notification response for B, then saves. B6: pending requests read on day 6. B7: `DailyCheckInService` with an injectable client and two zones. B11: a UI test through the Apple gate with a fake `signIn`. B12: inject `createEvent`. B16: sandbox renewal.

## Product calls (not counted)

No promise or a documented rule covers these.

- PC-1 Editing a Handled one-shot to a new time never re-arms it: `ReminderCompletion.swift:3-7` documents "completed forever by one acted event". The editor offers the date picker on it from the Handled list (`ReminderListView.swift:605`).
- PC-2 Marking a repeating reminder done does not silence today's local ping (repeating trigger); the server does skip it for partner-delivered ones (`0014:143-160`). `NotificationScheduler.swift:24-26` scopes completion to one-shots and daily random.
- PC-3 The Settings notification label is read once per appearance (`SettingsView.swift:221-224`), so it is stale after returning from iOS Settings until the tab reappears.
- PC-4 A surprise reminder is delivered only by server push (`ReminderEditorView.swift:539-540`); a partner without push never gets it and the author is not told.
- PC-5 Positive moments can be farmed by toggling Done and Not done (`ReviewPromptTracker.swift:105-108`).
- PC-6 The author can tick off a reminder addressed to the partner, which silences the partner's push (`0014:345`).
- PC-7 iOS keeps 64 pending requests; 13 daily-random reminders (5 each) plus milestones exceed it (`NotificationScheduler.swift:151`).
- PC-8 `ReminderRepository.refresh` has no sequence number, an older slow fetch can overwrite a newer one until the realtime echo heals it (`:96-100`).
- PC-9 After sign-out RevenueCat is anonymous and the new anonymous Supabase user is not identified until next launch (`SettingsView.swift:233-243`, `BondApp.swift:359`); a thrown `logOut` leaves the old `isPremium` (`PurchasesService.swift:399-405`).
- PC-10 After Unpair, reminders each partner wrote for the other stay on the author's list as "for partner" with nobody to receive them (`0009:81-83`).

## Related fixes, in order

1. B1 first (server): re-queue or drop `reminder_push_queue` rows on `leave_couple` and make `claim_due_reminder_pushes` require couple membership of author and target. Fixes PC-10 at the same time.
2. B2, B14, B8: treat completions like the list (`hasLoaded` for events, one sequence-numbered refresh path, one event per period by unique key). One change in `ReminderRepository` and `ReminderEventRepository`.
3. B3, B9, B10, B6: one scheduler change: put the anchor date, the zone and a runway refresh into the trigger construction, stagger templates by time of day.
4. B4: filter Insights input with the same visible-reminder rule as the list and the widget.
5. B13, B11: re-read couple, partner profile and repositories whenever identity or couple changes; keep partial results out of `PairingService`.
6. B5: key the editor on the reminder id.
7. B7, B15: derive the day and the week from one agreed rule on both sides.
8. B12, B16: copy and counter fixes.

## State machines

Notation: **I** is an invariant, **T** a transition. "Breaks" names the invariant a reachable bad transition violates and the bug id. Sources are file:line in the committed tree (nothing was stashed: the working tree was clean).

### M1. Reminder completion (per reminder, derived)

Not stored. It is a pure function of `(reminder, acted events, now)`: `ReminderDTO.isCompleted(in:at:)` (`Shared/Models/ReminderCompletion.swift:35`). The home list, Handled screen, widget-adjacent counts and `NotificationScheduler.reschedule` all call it.

States: **Open** (no acted event for the period), **DoneForPeriod** (repeating: recurring or daily random, acted event at or after `currentPeriodStart`), **Handled** (one-shot, any acted event, forever), **PastDue** (one-time, `fireAt < now`, not acted), **Deleted**.

Invariants
- I1.1 At most one acted event per reminder per period. Guard is `togglingIds` in `ReminderListView` (`:26`, `:504`), per device and per view only. The table has no unique key (`0001_init.sql` `reminder_events`).
- I1.2 Undo returns the reminder to Open. `currentCompletionEvent` returns one event (`ReminderCompletion.swift:45`).
- I1.3 The local list and the server's `reminder_done_now` agree on which period an event belongs to (`0014:132`, "Mirrors ReminderCompletion").
- I1.4 What a user sees is `authorId == me || targetId == me` (`ReminderListView.swift:186-191`).

| T | From | To | Breaks |
|---|---|---|---|
| Tap circle or swipe Done | Open | Done/Handled | CP-6 (a failed insert is swallowed with `try?`, `:507`, and the review counter still moves) |
| Second Done on a stale list (partner phone, or insert ok but re-read failed) | Done | Done with 2 events | I1.1 |
| Not done | Done with 2 events | still Done | I1.2, SM-6 |
| Midnight, week or month rollover | DoneForPeriod | Open | I1.3 on Sunday-first locales (SM-3) |
| Edit time of a Handled one-shot | Handled | Handled | PC-1 (documented rule) |
| Partner marks it done on their phone | Open | Done (server) | local copy only learns at the next foreground, `reminder_events` is not on the realtime feed (`ReminderRepository.subscribeRealtime` filters `reminders` only) |
| Delete | any | Deleted | none found (`delete` removes the row, `rescheduleNotifications` follows) |

### M2. On-device notification schedule

State is the set of pending `UNNotificationRequest`s. Written only by `NotificationScheduler.reschedule` (removes everything except `milestone.*`, then adds) and `rescheduleMilestones`. Call sites of the reminder rebuild (all route through `ReminderRepository.rescheduleNotifications`, which waits for `hasLoaded`): `ReminderListView.task` (`:122`), primer grant (`:103`), complete, undo, delete (`:508`, `:521`, `:526`, `:552`), Handled delete (`HandledRemindersView` `:596`), `refreshAndRearm` (`:541`), `ReminderEditorView.save` (`:609`), `importReminders` (`ReminderRepository.swift:219`), `rearm()` (realtime, watch, push registration, relationship change), `catchUp` (foreground, silent push). A direct `NotificationScheduler.reschedule` call exists only inside the repository's default closure (`:58`).

States: **Unarmed** (`!hasLoaded`), **Armed(L, E, perm, serverDelivers)** where L is the list and E the completions at the last rebuild, **Stale** (L or E differ from the server, or the clock/zone moved).

Invariants
- I2.1 Never rebuild from a list that was not fetched (`hasLoaded`, `ReminderRepository.swift:22`).
- I2.2 Never rebuild from completions that were not fetched. **Not enforced** for events: `eventsRepo.events` starts `[]` and `refresh()` swallows errors (SM-5).
- I2.3 Pending set equals f(L, E) for the user's current zone and day.
- I2.4 A phone arms partner reminders locally unless `PushRegistrar.serverDelivers` (`NotificationScheduler.armsLocally`, `:60`).

| T | Trigger | Effect | Breaks |
|---|---|---|---|
| Launch | `ReminderListView.task` | refresh, events refresh, rebuild | I2.2 when only the events request fails (SM-5) |
| Silent-push launch | `onRemoteChange` (`BondApp.swift:33`) | catchUp with `events.events` | I2.2, same, fresh process so E is `[]` |
| Save / reschedule | editor | upsert, refresh (errors swallowed), rebuild | I2.3 when the refresh fails (SM-2) |
| Foreground | `catchUpOnForeground` | pair lookup, catchUp, push refresh | none (reconciles permission granted later: `.notDetermined` -> granted arms everything, control) |
| 5 days idle | none | daily-random runway ends (`:151`) | I2.3 (CP-3) |
| Zone change | none (no observer exists, grep `TimeZoneDidChange` is empty) | calendar triggers float with the zone | I2.3 (CP-5) |
| Recurring with far "Starting" | save | repeating trigger ignores the anchor day (`:285-299`) | I2.3 (CP-2) |
| Unpair | `onRelationshipChange` | rebuild drops partner rows locally | server side keeps pushing (CP-1) |
| Complete a repeating reminder | Done | one-shot skipped, random-daily skips today, repeating trigger not skipped | PC-2 |

### M3. Push delivery registration (`PushRegistrar`, `0014_partner_delivery.sql`)

State is three UserDefaults keys (`push.token`, `push.user`, `push.synced`) plus the server's `push_devices` and `reminder_push_queue`.

States: **None**, **Registered(me, token, tz, day)**, **Forgotten** (after sign-out, delete, or `.denied`).

Invariants
- I3.1 `push.user == me` implies the server has a live device row for this phone and a queue row for each partner reminder addressed to me.
- I3.2 The queue only holds rows for reminders whose target and author are in one couple (not enforced, CP-1).
- I3.3 Re-registration when token, user, zone or day changes (`store`, `:59`).

| T | Effect | Breaks |
|---|---|---|
| Permission granted | `refresh` -> `registerForRemoteNotifications` -> `store` -> RPC -> `onRegistered` rearm drops local partner copies | none |
| Permission denied later | `refresh` unregisters, forget; next rebuild arms locally | none (note `catchUpOnForeground` rebuilds before the refresh, irrelevant while denied) |
| Sign out | `unregister` then `forget` | none |
| Unpair (either side) | `leave_couple` updates `couple_id` only | I3.2 (CP-1) |
| Token rotates / APNs 410 | server deletes row; next foreground `store` sees new token | none |

### M4. Notification permission and primer

States: notDetermined -> (primer shown, flag `hasShownNotificationPrimer` written *before* the sheet, `ReminderListView.swift:182`) -> requested -> authorized | denied. "Maybe later" leaves notDetermined with the flag set, the system prompt then comes from the first save or Done (`requestAuthIfNeeded` defaults true) or the Milestones tab.

Invariants: I4.1 the system prompt is not raised at launch (`requestAuthIfNeeded: false`); I4.2 granted later is picked up on foreground. Both hold. The Settings label (`SettingsView.swift:221`) is read once per appearance: PC-3.

### M5. Entitlement and purchase (`PurchasesService`)

States: **Unresolved** (`isPremium == false`, `customerInfo == nil`), **Free**, **Premium**, **Purchasing** (`purchaseInFlight`), **Pending** (payment ok, entitlement not yet visible, up to 15 polls of 0.6 s after `syncPurchases`), **Restoring**, **Error**. `isPremium = hasActivePremium(info)` on every `apply`.

Invariants
- I5.1 `isPremium` is derived from the last `CustomerInfo` for the current RevenueCat user.
- I5.2 The RevenueCat user is the Supabase user (`identify`, `BondApp.swift:359`, `:463`, `PairingView.swift:373`, `InviteWelcomeView.swift:112`).
- I5.3 No paywall on a beat where the entitlement may still be resolving (AGENTS.md). Post-pair and post-onboarding both check `!store.isPremium` at the moment, the bootstrap `refresh()` has long finished by those taps.

| T | Notes | Breaks |
|---|---|---|
| Launch | `bootstrap` refresh + offerings + stream | gates flash teaser for a beat (I5.3 not at risk, nothing raises a paywall there) |
| Purchase `.pending` | restore then error with Restore | none |
| Sign out | `purchases.signOut()` then `supabase.signOut()`; a thrown `logOut` leaves the old `isPremium` | PC-9, I5.1 only if `logOut` throws |
| Sign out, then new anonymous user | RevenueCat stays anonymous until next launch `identify` | PC-9, I5.2 |
| Renewal | Settings reads `latestPurchaseDate` | CP-7 |

### M6. Root routing and session (`RootDestination.resolve`, `SupabaseService`)

States: loading, intentSetup, inviteWelcome, inviteeIntake, pairingSuccess, home. Inputs: bootstrapped, authenticated, hasCouple, coupleLookupFailed, deferred invite, justPaired, solo, intake captured. Tested in `RootDestinationTests`.

Invariants: I6.1 a failed lookup is not "no couple" (held); I6.2 a failed restore is not "no session" (held, `shouldStartFreshSession`); I6.3 after the identity changes, the couple, reminders and completions in memory are re-read.

| T | Breaks |
|---|---|
| Apple link works | none |
| Apple link fails, server answered (identity belongs to an older account) -> `signIn` as that account | I6.3: nothing reloads `PairingService` / repositories, the old anonymous couple stays in memory until the next foreground (CP-9) |
| Sign out | `pairing.reset()` clears the couple; repositories keep the old arrays but `hasLoaded` goes false |
| Delete account | same |

### M7. Pairing (`PairingService`, `0005`, `0009`, `0010`)

States: **Uncoupled**, **Solo** (own couple row, partner_a == partner_b), **Paired**, **Unpaired** (split into two solo couples), plus invite sub-state (code pending 24 h, consumed, expired) and `deferredInviteCode` + `requiresSignInToPair` for anonymous users.

Invariants: I7.1 `!solo` implies `partnerProfile != nil` (nothing enforces it, SM-4); I7.2 a failed lookup changes nothing (`PairingService.swift:102`, broken half-way in SM-4); I7.3 after unpair, the other partner cannot send anything (`SettingsView.swift:76`, broken server-side, CP-1).

| T | Notes | Breaks |
|---|---|---|
| Consume code | merges the invitee's solo rows onto the survivor | none |
| Lookup with profile fetch failing | `coupleId`/`solo` already written, `lastLoadFailed`, `onRelationshipChange` still fires | I7.1, I7.2 (SM-4) |
| Unpair | `leave_couple` | I7.3 (CP-1) |

### M8. Paywall and review presentation flags

UserDefaults: `hasShownPostPairPaywall`, `hasShownPostOnboardingPaywall` (set at `IntentSetupView.enterTrialStep`, `:430`, and again on the `.intentSetup -> .home` edge, `BondApp.swift:408`), `hasShownNotificationPrimer`, `pairingNudgeDismissed`. View state: `pendingPostOnboardingPaywall`, `showPostPairPaywall`, `showReviewPrompt`, `reviewPromptShownThisSession`. `ReviewPromptTracker` (app group): launch count, first open, positive moments, last shown, outcome.

Invariants: each one-shot flag is written before its sheet appears (a sheet that fails to present is never retried, by design). Review funnel needs a real done (AGENTS.md): CP-6.

### M9. Daily check-in (`DailyCheckInService`)

Per local calendar day: noQuestion -> pending -> awaitingPartner -> readyToReveal -> revealed (`revealPhase`, `reveal-shown-<yyyy-MM-dd>`). The question index is `(local day ordinal + coupleSeed) % count` (`:37-43`); responses are matched by question id.

Invariant I9.1: both partners are on the same question on the same day. Broken whenever their local dates differ (CP-8). `todaysQuestion`, `myResponse`, `partnerResponse` are not cleared on sign-out or unpair; they are reassigned by the next successful load.

### M10. Milestones and widget/watch sync

Milestones: `refresh` writes list, widget snapshot, and `milestone.*` notifications (next occurrence only; 7 days, 1 day, day-of at 9:00). Re-armed only when the list is re-read. Widget snapshot is rebuilt whole and waits for `reminderRepo.hasLoaded`; a failed load keeps the last good one (documented). Watch: `createReminder` -> `upsert` -> `rearm()`; reply carries the real outcome.

### M11. Server push queue (SQL)

`reminder_push_queue(reminder_id, next_push_at, silent)`. Rows are written by trigger `reminders_sync_push_queue` on insert or update of `fire_at, rrule, geofence, window_start, window_end, trigger_type, author_id, target_id, surprise_hidden_from_partner`, by `register_push_device`, and by `claim_due_reminder_pushes` (which moves each row on before sending). Not in the column list: `couple_id`. Invariants: I11.1 a row exists only while the target should still receive it; I11.2 done-for-period uses the same period as the client (SM-3); I11.3 claim skips rows stale by more than an hour.
