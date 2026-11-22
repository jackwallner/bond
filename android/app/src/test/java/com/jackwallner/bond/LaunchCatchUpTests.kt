package com.jackwallner.bond

import com.jackwallner.bond.data.Codec
import com.jackwallner.bond.data.MilestonesService
import com.jackwallner.bond.data.ReminderEventRepository
import com.jackwallner.bond.data.ReminderRepository
import com.jackwallner.bond.data.ReminderScheduling
import com.jackwallner.bond.data.catchUpReminders
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// iOS 43cec9c, fb1c937, 315e45c, 4ac551e, c581b92 (launch and schedule invariants, 2026-10-31).

internal class Recorder : ReminderScheduling {
    val rebuilt = mutableListOf<List<ReminderEventDto>>()
    val milestoneCalls = mutableListOf<List<MilestoneDto>>()
    override fun reschedule(selfId: UUID, reminders: List<ReminderDto>, events: List<ReminderEventDto>) {
        rebuilt.add(events)
    }
    override fun rescheduleMilestones(milestones: List<MilestoneDto>) { milestoneCalls.add(milestones) }
    override fun clearAll() = Unit
}

class RelationshipChangeTests {
    private fun couple(b: Backend, id: UUID = b.coupleId, solo: Boolean = false) =
        JSONObject().put("id", id.toString()).put("partner_a", b.me.toString())
            .put("partner_b", (if (solo) b.me else b.partner).toString()).put("solo", solo)

    private fun profile(b: Backend) = JSONObject().put("id", b.partner.toString()).put("display_name", "Sam")

    private fun Backend.serve(couple: () -> JSONObject) {
        route = { call ->
            when {
                table(call, "couples") -> Backend.rows(couple())
                table(call, "profiles") -> Backend.rows(profile(this))
                else -> Backend.ok()
            }
        }
    }

    @Test fun theFirstLookupOfALaunchIsNotAChange() = runTest {
        val b = Backend()
        b.serve { couple(b) }
        var changes = 0
        b.pairing.onRelationshipChange = { changes++ }
        assertTrue(b.pairing.loadCouple())
        assertEquals(0, changes)
    }

    @Test fun theSameCoupleAgainIsNotAChange() = runTest {
        val b = Backend()
        b.serve { couple(b) }
        var changes = 0
        b.pairing.onRelationshipChange = { changes++ }
        b.pairing.loadCouple()
        b.pairing.loadCouple()
        assertEquals(0, changes)
    }

    @Test fun theInviterKeepsTheCoupleIdWhenUnpairing_soTheCoupleTurningSoloIsTheSignal() = runTest {
        val b = Backend()
        var solo = false
        b.serve { couple(b, solo = solo) }
        var changes = 0
        b.pairing.onRelationshipChange = { changes++ }
        b.pairing.loadCouple()
        solo = true
        b.pairing.loadCouple()
        assertEquals(1, changes)
        assertTrue(b.pairing.solo)
    }

    @Test fun anotherCoupleIsAChange() = runTest {
        val b = Backend()
        var id = b.coupleId
        b.serve { couple(b, id) }
        var changes = 0
        b.pairing.onRelationshipChange = { changes++ }
        b.pairing.loadCouple()
        id = UUID.randomUUID()
        b.pairing.loadCouple()
        assertEquals(1, changes)
        assertEquals(id, b.pairing.coupleId)
    }

    @Test fun aFailedLookupAnnouncesNothing() = runTest {
        val b = Backend()
        var up = true
        b.route = { call ->
            when {
                !up -> Backend.down()
                b.table(call, "couples") -> Backend.rows(couple(b))
                b.table(call, "profiles") -> Backend.rows(profile(b))
                else -> Backend.ok()
            }
        }
        var changes = 0
        b.pairing.onRelationshipChange = { changes++ }
        b.pairing.loadCouple()
        up = false
        assertFalse(b.pairing.loadCouple())
        assertEquals(0, changes)
    }
}

class CatchUpTests {
    private fun repos(b: Backend) = ReminderRepository(b.client, b.pairing, b.seed) to ReminderEventRepository(b.client, b.pairing, b.seed)

    @Test fun aCatchUpReadsTheListAndRearmsFromIt() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val theirs = reminder("one_time", fireAt = at(2026, 11, 7, 9), authorId = b.partner, targetId = b.me)
        val done = acted(theirs, at(2026, 11, 6, 10))
        b.route = { call ->
            when {
                b.table(call, "reminders") -> Backend.rows(Codec.reminderJson(theirs))
                b.table(call, "reminder_events") -> Backend.rows(Codec.eventJson(done))
                else -> Backend.ok()
            }
        }
        val (reminders, events) = repos(b)
        val scheduler = Recorder()
        assertTrue(catchUpReminders(scheduler, b.me, reminders, events))
        assertEquals(listOf(theirs.id), reminders.reminders.map { it.id })
        assertEquals(listOf(listOf(done)), scheduler.rebuilt)
    }

    @Test fun aCatchUpWhoseReadFailedLeavesTheArmedAlarmsAlone() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        b.route = { Backend.down() }
        val (reminders, events) = repos(b)
        val scheduler = Recorder()
        assertFalse(catchUpReminders(scheduler, b.me, reminders, events))
        assertTrue(scheduler.rebuilt.isEmpty())
    }

    @Test fun aCatchUpBeforeSignInDoesNothing() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val (reminders, events) = repos(b)
        assertFalse(catchUpReminders(Recorder(), null, reminders, events))
    }

    @Test fun milestonesLoadedAtLaunchLayDownTheirPings() = runTest {
        val b = Backend()
        b.pairing.coupleId = b.coupleId
        val m = MilestoneDto(UUID.randomUUID(), b.coupleId, "anniversary", "Ours", LocalDate.of(2000, 12, 1), true)
        b.route = { call -> if (b.table(call, "milestones")) Backend.rows(Codec.milestoneJson(m)) else Backend.ok() }
        val scheduler = Recorder()
        MilestonesService(b.client, b.pairing, scheduler, b.seed).refresh()
        assertEquals(listOf(listOf(m)), scheduler.milestoneCalls)
    }
}
