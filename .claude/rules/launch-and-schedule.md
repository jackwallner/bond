---
paths:
  - "Bond/BondApp.swift"
  - "Bond/Services/ReminderRepository.swift"
  - "Bond/Services/MilestonesService.swift"
  - "Bond/Services/PairingService.swift"
  - "Bond/Services/NotificationScheduler.swift"
  - "Bond/Services/WidgetSnapshotPump.swift"
  - "Shared/Models/MilestoneDTO.swift"
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
- The services expose their fetches (`loadRows`, `fetchCouples`,
  `scheduleNotifications`, `deleteRow`) as closures so tests can fail them
  without a network. New test suites went into the existing test files because
  `Bond.xcodeproj` is tracked and a new file needs `xcodegen generate`.
