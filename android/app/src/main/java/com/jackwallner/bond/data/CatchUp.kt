package com.jackwallner.bond.data

import java.util.UUID

/**
 * Re-reads the couple's reminders and completions and rebuilds the alarms from
 * them (`ReminderRepository.catchUp`). A failed read leaves the armed alarms
 * alone, see [rebuildSchedule]. Returns whether the alarms were rebuilt.
 */
suspend fun catchUpReminders(
    scheduler: ReminderScheduling,
    me: UUID?,
    reminders: ReminderRepository,
    events: ReminderEventRepository,
): Boolean {
    reminders.refresh()
    events.refresh()
    return me != null && rebuildSchedule(scheduler, me, reminders, events)
}
