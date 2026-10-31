---
paths:
  - "Bond/BondApp.swift"
  - "Bond/Services/ReminderRepository.swift"
  - "Bond/Services/MilestonesService.swift"
  - "Bond/Services/PairingService.swift"
  - "Bond/Services/NotificationScheduler.swift"
  - "Bond/Services/WidgetSnapshotPump.swift"
  - "Shared/Models/MilestoneDTO.swift"
  - "Shared/DTOs/ReminderDTO.swift"
  - "Shared/Utilities/WidgetSnapshot.swift"
  - "Bond/Services/SupabaseService.swift"
  - "Bond/Services/WatchConnectivityBridge.swift"
  - "BondTests/ReminderDTOTests.swift"
  - "BondTests/CoupleDTOTests.swift"
  - "BondTests/MilestoneDTOTests.swift"
---

# Launch, schedule and widget invariants (2026-10-31 bug hunt)

- **A failed fetch is not an empty list.** `ReminderRepository.hasLoaded` is true
  once a refresh has succeeded for the couple the app is on now (it goes false
  again when the couple changes); `rescheduleNotifications` does nothing until
  then, because a rebuild removes every pending notification first. Route every
  reschedule through the repository, not `NotificationScheduler.reschedule`.
- **Notifications are only as fresh as the last list.** Partner reminders reach
  this phone as local notifications armed from the fetched list, and the realtime
  feed is not replayed after the app was suspended. So the list is re-read, and
  the schedule rebuilt (`ReminderRepository.catchUp`, no permission prompt), when
  the app returns to the foreground (`BondApp.catchUpOnForeground`, which looks
  the couple up again first because an unpair moves a partner's rows to a new
  couple), and
  `importReminders` rebuilds right after a template pack is inserted. Anything new
  that writes reminders must end in `rescheduleNotifications`.
- **Changes that arrive outside a screen re-arm through the repository.** The
  realtime handler (`handleRemoteChange`) and the watch bridge call `rearm()`,
  which reads the signed-in user and the completions from `armingContext` (set
  in `BondApp`) and never asks for permission. `PairingService.loadCouple` calls
  `onRelationshipChange` when the couple changed or turned solo or paired (not on
  the first lookup after launch or sign-out); the app re-reads milestones and
  catches up, so unpairing silences the partner's reminders at once. The inviter
  keeps the couple id when unpairing, so watching the id alone misses it.
- **A failed couple lookup is not "no couple".** `PairingService.lastLoadFailed`
  keeps `RootDestination.resolve` on `.loading` (the Couldn't connect state with
  Try again), because first-run onboarding ends in `create_solo_couple`
  raising "already in a couple". Android has the same guard (`initialLoadFailed`).
- **A failed restore is not a missing session.** `SupabaseService.restoreSession`
  signs in as a new anonymous user only when the stored-session load fails for a
  reason other than a request that never completed (`shouldStartFreshSession`).
  The new session replaces the stored one, so a timeout while the expired access
  token is refreshed would strand the account (couple, reminders, milestones) of
  an anonymous user. Offline or flaky launches stay on Couldn't connect; Try
  again restores the real session. Android makes the same distinction.
- **Milestones load when home appears**, with `requestAuthIfNeeded: false` so the
  notification primer still explains first. `MilestonesService.onChange` pushes
  the widget snapshot; the snapshot is rebuilt whole, so it waits for
  `reminderRepo.hasLoaded`.
- **Milestone days are calendar days.** `MilestoneDTO.nextOccurrence` compares
  against the start of the reference day (the stored date is local midnight) and
  `daysUntilNextOccurrence` / `NextMilestone.daysAway` count midnights, not
  elapsed seconds.
- **An upsert only changes the columns it is sent.** `ReminderDTO.encode` and
  `MilestoneDTO.encode` write a cleared optional (the note, a repeat rule, the
  label) as an explicit null, as Android's `Codec` does; a nil left out of the
  body meant the old value stayed on the server and the edit vanished on the
  next refresh. `created_at` stays out when unknown so the database default
  applies.
- **The widget shows what the app shows this user.** `WidgetSnapshot.make` keeps
  the reminders the user wrote or that are addressed to them (the couple's rows
  are all readable, and the partner's own reminders are not for this phone) and
  skips a milestone whose day is over.
- **Linking Apple to the anonymous user falls back to a plain sign-in only for a
  failure the server answered** (`SupabaseService.shouldFallBackToSignIn`). A
  request that never completed says nothing about the identity belonging to
  someone else, and signing in then creates a new empty account while the
  anonymous user's couple and reminders are orphaned.
- The services expose their fetches (`loadRows`, `fetchCouples`,
  `scheduleNotifications`, `deleteRow`) as closures so tests can fail them
  without a network. New test suites went into the existing test files because
  `Bond.xcodeproj` is tracked and a new file needs `xcodegen generate`.
