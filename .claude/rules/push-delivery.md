---
paths:
  - "supabase/migrations/**"
  - "supabase/tests/**"
  - "SupabaseFunctions/send-push/**"
  - "Bond/Services/PushRegistrar.swift"
  - "Bond/Services/NotificationScheduler.swift"
  - "Bond/Services/NotificationRouter.swift"
---

# Partner push delivery (0014 to 0021, council reviews 2026-11-06)

- **Lease, then acknowledge.** `claim_due_reminder_pushes` leases each due
  occurrence for 2 minutes and returns it once, with `due_at`, `user_id` and a
  `devices` list. Only `ack_reminder_push(reminder, due_at, user)` moves it on
  (delete a silent or one-shot row, refresh a repeating one). send-push acks
  when no device failed for a passing reason (429, 5xx, network, a refused provider
  token); a dead token or any other 4xx is over for that phone. An ack whose `due_at` no longer matches the row does nothing, so pass the
  claim's string back untouched (JS `Date` drops the microseconds).
- **Per phone.** When a phone has to be retried, `mark_push_sent` records the ones
  that are done (`sent_tokens` on the row, emptied whenever the row moves on), and
  the claim only lists the phones still owed it. A row none are owed is finished.
  So a good phone gets one copy however long another fails. The collapse id only
  covers a lost ack.
- **Batches fit the lease.** send-push claims 25 occurrences and 25 signals at a
  time, so even with every request timing out (10 phones each, chunks of 50, 8 s)
  all of it is recorded inside the 2 minute lease. It claims again while there is
  more, up to 60 s.
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
  Due, unsent rows always stay due. A token new to the server is left out of them
  (it rang them itself) unless the row is a hidden surprise, which it could not
  arm. The cost: a phone that never fetched the reminder misses that one push, and
  sees it in the app it just opened. Tokens must match `^[0-9a-fA-F]{64,200}$`; a
  user keeps 10 devices. An evicted phone trusts the server until it next opens, so
  the cap is well above a real household. Test tokens are hex (`repeat('b', 64)`).
- **Dead tokens.** `delete_push_device(token, user, seen)` removes the row only if
  `updated_at` is what the claim returned, so a phone that registered again stays.
- **Completion dates.** A trigger stops `acted_at` at the server's now. Past dates
  stay, for offline completions.
- **Words on a place.** `reminders_sync_location_text` queues a silent push when the
  title, body or love language of a location reminder changes.
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
- **Lost registration answer.** If the app can't tell whether registering worked
  and can't take the token back either, the token goes to `push.pendingRelease`
  and the next registration settles it. Until then a background alert can arrive
  twice (local and server); foreground server ones are suppressed.
- **Deploy order.** Check each migration's header. For 0020: migration, then
  send-push, then 0021, which drops the old `delete_push_device` overloads.
