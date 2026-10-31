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

- **A failed fetch is not an empty list.** `ReminderRepository.hasLoaded` flips
  on the first successful refresh; `rescheduleNotifications` does nothing until
  then, because a rebuild removes every pending notification first. Route every
  reschedule through the repository, not `NotificationScheduler.reschedule`.
- **A failed couple lookup is not "no couple".** `PairingService.lastLoadFailed`
  keeps `RootDestination.resolve` on `.loading` (the Couldn't connect state with
  Try again), because first-run onboarding ends in `create_solo_couple`
  raising "already in a couple". Android has the same guard (`initialLoadFailed`).
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
