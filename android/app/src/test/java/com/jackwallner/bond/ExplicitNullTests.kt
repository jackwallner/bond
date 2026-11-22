package com.jackwallner.bond

import com.jackwallner.bond.data.Codec
import com.jackwallner.bond.model.MilestoneDto
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExplicitNullTests {
    // iOS 3f0d6c9: an upsert only changes the columns in its body, so a cleared field is sent as null.
    @Test fun aClearedNoteRepeatRuleAndLabelGoOutAsExplicitNulls() {
        val cleared = reminder("one_time", fireAt = at(2026, 11, 7, 9)).copy(body = null, rrule = null)
        val body = Codec.reminderJson(cleared)
        for (key in listOf("body", "rrule", "geofence", "window_start", "window_end", "fire_at")) {
            assertTrue("$key missing from the body", body.has(key))
        }
        assertTrue(body.isNull("body"))
        assertTrue(body.isNull("rrule"))
        assertFalse("created_at stays out when unknown", body.has("created_at"))
        val milestone = Codec.milestoneJson(MilestoneDto(UUID.randomUUID(), UUID.randomUUID(), "birthday", null, LocalDate.of(2000, 1, 2), true))
        assertTrue(milestone.has("label"))
        assertTrue(milestone.isNull("label"))
        assertNull(milestone.opt("created_at"))
    }
}
