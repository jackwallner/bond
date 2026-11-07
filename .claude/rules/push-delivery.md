---
paths:
  - "supabase/migrations/**"
  - "supabase/tests/**"
  - "SupabaseFunctions/send-push/**"
  - "Bond/Services/PushRegistrar.swift"
  - "Bond/Services/NotificationScheduler.swift"
  - "Bond/Services/NotificationRouter.swift"
---

# Partner push delivery (0014 to 0019, council review 2026-11-06)

- **Lease, then acknowledge.** `claim_due_reminder_pushes` leases each due
  occurrence for 2 minutes and returns it once, with `due_at`, `user_id` and a
  `devices` list. Only `ack_reminder_push(reminder, due_at, user)` moves it on
  (delete a silent or one-shot row, refresh a repeating one). send-push acks
  only when no device failed for a passing reason; a dead token does not count.
  An ack whose `due_at` no longer matches the row does nothing, so pass the
  claim's string back untouched (JS `Date` drops the microseconds).
- **Late is skipped, never burst.** The claim moves a row on unsent once it is
  an hour late; `apns-expiration` is the due time plus that hour and
  `apns-collapse-id` is `<reminder>.<due epoch>`, so a retry replaces a copy.
- **Phone signals.** `push_signals` holds one pending silent push per user. A
  change of a couple's pair state, and a partner's visible location reminder
  being deleted, retargeted or turned into a time, enqueue one. The claim returns
  it with no reminder, it is acked by user, and the app reloads the couple and
  rebuilds (`PushRegistrar.rebuildAfterSilentPush`). Silent pushes are best
  effort: never promise "immediately" in copy.
- **One bad row never stops the rest.** The claim, the ack, both triggers and
  registration wrap each row; a failing row warns and leaves the queue.
  `reminders_times_finite` (NOT VALID) refuses non-finite times on writes.
- **Registration.** The app registers on every foreground (no daily dedupe).
  The server keeps due, unsent rows for a user who already had a device, and
  recomputes them away only on a first device, which rang them locally. Tokens
  must match `^[0-9a-fA-F]{64,200}$`; a user keeps 5 devices. Test tokens are
  hex (`repeat('b', 64)`).
- **Sign-out offline.** A failed `unregister_push_device` keeps the token in
  `push.pendingRelease`; the next registration (any account) moves it, or the
  app registers and releases it. Background alerts for the old account can
  still show until then; foreground ones are suppressed (`NotificationRouter`).
- **Daily random agrees.** Server (`daily_pick_unit`, `daily_window`) and phone
  (`NotificationScheduler.stablePick`) hash the same bytes: the upper-case UUID
  and the day ordinal (whole days from 1970 to local midnight), FNV-1a 64, at
  minute precision. A reminder created inside today's window after today's pick
  falls forward to the same moment on both. Change both or neither; the fixed
  vectors are in `reliable_delivery_test.sql` and `DailyRandomAgreementTests`.
- **Completions stay in their couple.** `reminder_events` writes need
  `reminder_in_couple`, and `reminder_done_at` counts only `e.couple_id =
  r.couple_id`. Reminder edits keep `is_couple_member(couple_id)`.
- **Privileges.** Supabase grants new functions to anon and authenticated by
  name. Every new function revokes from `public, anon, authenticated` and is
  listed in the privilege section of `reliable_delivery_test.sql`.
- **Deploy order.** send-push first (it handles the pre-0019 claim rows), then
  the migration. The old function against the new claim sends nothing for up to
  an hour.
