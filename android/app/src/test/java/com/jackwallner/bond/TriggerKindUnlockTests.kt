package com.jackwallner.bond

import com.jackwallner.bond.model.Geofence
import com.jackwallner.bond.model.ReminderTrigger
import com.jackwallner.bond.model.TriggerKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// iOS b9ed93f.
class TriggerKindUnlockTests {
    @Test fun eachStoredTriggerBelongsToItsKind() {
        val t = at(2026, 11, 7, 9)
        val place = Geofence(1.0, 2.0, 200.0, "Home")
        assertEquals(TriggerKind.ONE_TIME, TriggerKind.of(ReminderTrigger.OneTime(t)))
        assertEquals(TriggerKind.RECURRING, TriggerKind.of(ReminderTrigger.Recurring("FREQ=DAILY", t)))
        assertEquals(TriggerKind.LOCATION, TriggerKind.of(ReminderTrigger.Location(place, true)))
        assertEquals(TriggerKind.RANDOM_WINDOW, TriggerKind.of(ReminderTrigger.RandomWindow(t, t.plusSeconds(60))))
        assertEquals(TriggerKind.RANDOM_WINDOW, TriggerKind.of(ReminderTrigger.RandomRecurring(t, t.plusSeconds(60))))
    }

    // Presubmit review 2026-11-08: a free user opening a place or surprise reminder met the paywall on Save.
    @Test fun aFreeUserKeepsTheKindTheReminderAlreadyHas() {
        assertFalse(TriggerKind.needsUnlock(TriggerKind.LOCATION, TriggerKind.LOCATION, isPremium = false))
        assertFalse(TriggerKind.needsUnlock(TriggerKind.RANDOM_WINDOW, TriggerKind.RANDOM_WINDOW, isPremium = false))
    }

    @Test fun aFreeUserChoosingAPlusKindIsAskedToUnlock() {
        assertTrue(TriggerKind.needsUnlock(TriggerKind.LOCATION, null, isPremium = false))
        assertTrue(TriggerKind.needsUnlock(TriggerKind.RANDOM_WINDOW, TriggerKind.ONE_TIME, isPremium = false))
        assertTrue(TriggerKind.needsUnlock(TriggerKind.LOCATION, TriggerKind.RANDOM_WINDOW, isPremium = false))
        assertFalse(TriggerKind.needsUnlock(TriggerKind.LOCATION, null, isPremium = true))
        assertFalse(TriggerKind.needsUnlock(TriggerKind.RECURRING, null, isPremium = false))
    }
}
