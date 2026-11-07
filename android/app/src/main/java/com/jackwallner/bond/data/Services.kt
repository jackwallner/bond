package com.jackwallner.bond.data

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.bond.model.DailyQuestionDto
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.ProfileDto
import com.jackwallner.bond.model.QuestionResponseDto
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import com.jackwallner.bond.model.currentCompletionEvents
import com.jackwallner.bond.model.nextOccurrence
import com.jackwallner.bond.model.withSchedule
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

/** Where reminder and milestone pings are laid down (AlarmManager in the app, a fake in tests). */
interface ReminderScheduling {
    fun reschedule(selfId: UUID, reminders: List<ReminderDto>, events: List<ReminderEventDto>)
    fun rescheduleMilestones(milestones: List<MilestoneDto>)
    fun clearAll()
}

/**
 * Rebuilds the armed reminders from the two lists. A rebuild replaces every armed
 * reminder with what the lists say, so it waits until both were fetched for the
 * couple the app is on: before that an empty list means "not fetched", and a launch
 * whose fetch failed would cancel every reminder (reminders) or ping every handled
 * one again (completions). Returns whether it ran.
 */
fun rebuildSchedule(
    scheduler: ReminderScheduling,
    me: UUID,
    reminders: ReminderRepository,
    events: ReminderEventRepository,
): Boolean {
    if (!reminders.hasLoaded) return false
    val loaded = events.loadedEvents ?: return false
    scheduler.reschedule(me, reminders.reminders, loaded)
    return true
}

/** Debug screenshot seeding turns every network refresh into a no-op, like `BondScreenshotSeed.isEnabled`. */
class SeedMode {
    var enabled = false
}

private fun logError(tag: String, message: String, error: Throwable? = null) {
    runCatching { Log.w("Bond.$tag", message, error) }
}

/** `SupabaseService.swift`: a silent anonymous identity behind every install. */
class AuthService(private val client: SupabaseClient) {
    var currentUserId by mutableStateOf<UUID?>(null)
        private set
    var isAnonymous by mutableStateOf(false)
        private set
    val isAuthenticated: Boolean get() = currentUserId != null

    private val bootstrapLock = Mutex()
    private var bootstrapped = false

    /** Idempotent: concurrent callers wait for the one restore, so only one anonymous user is ever minted. */
    suspend fun bootstrap() = bootstrapLock.withLock {
        if (bootstrapped) return@withLock
        restoreSession()
        bootstrapped = true
    }

    /** "Try again" on the connection screen: a fresh attempt, not the cached failure. */
    suspend fun retryBootstrap() {
        bootstrapLock.withLock { bootstrapped = false }
        bootstrap()
    }

    private suspend fun restoreSession() {
        try {
            val session = client.restoreSession()
            if (session != null) apply(session) else signInAnonymously()
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            // Offline with a stored session: keep the identity rather than minting a new user.
            client.session?.let(::apply) ?: logError("auth", "restore failed", error)
        }
    }

    private suspend fun signInAnonymously() {
        try {
            apply(client.signInAnonymously())
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            logError("auth", "anonymous sign-in failed", error)
        }
    }

    /** For the screenshot seed only. */
    fun adoptForSeed(userId: UUID) {
        currentUserId = userId
        isAnonymous = true
    }

    private fun apply(session: AuthSession) {
        currentUserId = session.userId
        isAnonymous = session.isAnonymous
    }

    /**
     * Permanently deletes the account (`delete_account` hands a shared couple to
     * the partner first), then starts a fresh anonymous session so the app
     * returns to first run.
     */
    suspend fun deleteAccount() {
        val me = currentUserId ?: return
        client.rpc("delete_account", JSONObject().put("p_user", me.toString()))
        client.clearSession()
        currentUserId = null
        isAnonymous = false
        retryBootstrap()
    }
}

/** `PairingService.swift`. */
class PairingService(
    private val client: SupabaseClient,
    private val auth: AuthService,
    private val prefs: OnboardingPreferences,
    private val seed: SeedMode,
) {
    var coupleId by mutableStateOf<UUID?>(null)
    var partnerProfile by mutableStateOf<ProfileDto?>(null)
    var solo by mutableStateOf(false)
    var pendingInviteCode by mutableStateOf<String?>(null)
        private set
    var pendingInviteUrl by mutableStateOf<String?>(null)
        private set
    var pendingInviteExpiresAt by mutableStateOf<Instant?>(null)
        private set
    var isPairing by mutableStateOf(false)
        private set
    var justPaired by mutableStateOf(false)
    var lastError by mutableStateOf<String?>(null)
    /** An invite captured from a link before this install has a couple: drives invite-first onboarding. */
    var deferredInviteCode by mutableStateOf<String?>(null)

    /**
     * Reads the couple row. Returns false on a transport failure, in which case
     * the previous state is kept rather than pretending there is no couple.
     */
    suspend fun loadCouple(): Boolean {
        if (seed.enabled) return true
        val me = auth.currentUserId ?: return false
        return try {
            val rows = client.select("couples", "select=*&or=(partner_a.eq.$me,partner_b.eq.$me)&limit=1")
            val row = Codec.objects(rows).firstOrNull()?.let(Codec::couple)
            // The partner's profile is part of the answer: commit nothing until it is in,
            // so a failure here leaves the state as it was instead of "paired with no
            // partner" (where For: Partner saved for oneself).
            val partner = row?.partnerId(me)?.takeIf { it != me }
            val profile = partner?.let { id ->
                val profiles = client.select("profiles", "select=*&id=eq.$id")
                Codec.objects(profiles).firstOrNull()?.let(Codec::profile)
                    ?: throw SupabaseException(404, "Partner profile not found")
            }
            coupleId = row?.id
            solo = row?.solo ?: false
            partnerProfile = profile
            // An invitee never typed a name; seed it from the partner's profile.
            val name = profile?.displayName?.trim().orEmpty()
            if (prefs.partnerName.isBlank() && name.isNotEmpty()) prefs.updatePartnerName(name)
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            logError("pairing", "loadCouple failed (state kept)", error)
            false
        }
    }

    /** Polls while the inviter waits on the share screen, until paired, expired or cancelled. */
    suspend fun waitForPartnerToPair(now: () -> Instant = Instant::now) {
        while (true) {
            if (pendingInviteCode == null) return
            pendingInviteExpiresAt?.let { if (it.isBefore(now())) return }
            delay(3_000)
            loadCouple()
            if (coupleId != null && !solo) {
                clearPendingInvite()
                justPaired = true
                return
            }
        }
    }

    suspend fun createSoloCouple() {
        val me = auth.currentUserId ?: run { lastError = "Sign in first."; return }
        lastError = null
        try {
            callCreateSoloCouple(me)
            loadCouple()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (isSchemaCacheError(error)) {
                delay(1_500)
                try {
                    callCreateSoloCouple(me)
                    loadCouple()
                    lastError = null
                    return
                } catch (retry: CancellationException) {
                    throw retry
                } catch (retry: Exception) {
                    logError("pairing", "create_solo_couple retry failed", retry)
                }
            } else {
                logError("pairing", "create_solo_couple failed", error)
            }
            lastError = "We couldn't finish setup. Please try again in a moment."
        }
    }

    private suspend fun callCreateSoloCouple(me: UUID) {
        client.rpc("create_solo_couple", JSONObject().put("p_user", me.toString()))
    }

    private fun isSchemaCacheError(error: Exception): Boolean {
        val text = error.message.orEmpty().lowercase()
        return "schema cache" in text || "pgrst202" in text || "could not find the function" in text
    }

    suspend fun generateInviteCode(now: Instant = Instant.now()): String? {
        val me = auth.currentUserId ?: run { lastError = "Sign in first."; return null }
        lastError = null
        // Retire earlier codes so only the latest shared one works.
        runCatching { client.delete("invite_codes", "created_by=eq.$me") }
            .onFailure { if (it is CancellationException) throw it }
        val code = newInviteCode()
        val expiresAt = now.plusSeconds(60 * 60 * 24)
        return try {
            client.insert(
                "invite_codes",
                JSONObject().put("code", code).put("created_by", me.toString()).put("expires_at", expiresAt.toString()),
            )
            val url = inviteUrl(code)
            pendingInviteCode = code
            pendingInviteUrl = url
            pendingInviteExpiresAt = expiresAt
            url
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message ?: "Couldn't create a code."
            null
        }
    }

    fun clearPendingInvite() {
        pendingInviteCode = null
        pendingInviteUrl = null
        pendingInviteExpiresAt = null
    }

    suspend fun consumeInviteCode(code: String) {
        val me = auth.currentUserId ?: run { lastError = "Sign in first."; return }
        isPairing = true
        lastError = null
        try {
            client.rpc("consume_invite_code", JSONObject().put("p_code", code).put("p_user", me.toString()))
            lastError = null
            loadCouple()
            if (coupleId != null && !solo) justPaired = true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = friendlyPairingError(error.message)
        } finally {
            isPairing = false
        }
    }

    /** Invite-first onboarding: the code is cleared only once pairing actually worked. */
    suspend fun consumeDeferredInviteIfNeeded() {
        val code = deferredInviteCode ?: return
        consumeInviteCode(code)
        if (coupleId != null && !solo) deferredInviteCode = null
    }

    suspend fun leaveCouple() {
        val me = auth.currentUserId ?: run { lastError = "Sign in first."; return }
        try {
            client.rpc("leave_couple", JSONObject().put("p_user", me.toString()))
            lastError = null
            loadCouple()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
        }
    }

    fun reset() {
        coupleId = null
        partnerProfile = null
        solo = false
        clearPendingInvite()
        justPaired = false
        isPairing = false
        lastError = null
        deferredInviteCode = null
    }

    /**
     * Invite links: `https://jackwallner.com/pair/CODE` and `bond://pair/CODE`.
     * With no couple yet the code drives invite-first onboarding; otherwise it
     * is consumed right away (Android pairs on the anonymous identity, see the
     * rule file). Returns the code to consume now, if any.
     */
    fun handleIncomingLink(link: String): String? {
        val code = parseInviteCode(link) ?: return null
        if (coupleId == null) {
            deferredInviteCode = code
            return null
        }
        return code
    }

    companion object {
        const val INVITE_CODE_LENGTH = 6
        const val INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        const val UNIVERSAL_LINK_HOST = "jackwallner.com"

        fun newInviteCode(random: kotlin.random.Random = kotlin.random.Random.Default): String =
            (0 until INVITE_CODE_LENGTH).map { INVITE_ALPHABET[random.nextInt(INVITE_ALPHABET.length)] }.joinToString("")

        fun inviteUrl(code: String) = "https://$UNIVERSAL_LINK_HOST/pair/$code"

        fun parseInviteCode(link: String): String? {
            val uri = runCatching { java.net.URI(link.trim()) }.getOrNull() ?: return null
            val isUniversal = uri.host == UNIVERSAL_LINK_HOST
            val isCustom = uri.scheme == "bond"
            if (!isUniversal && !isCustom) return null
            val parts = uri.path.orEmpty().split("/").filter { it.isNotEmpty() }.toMutableList()
            // In bond://pair/CODE the "pair" segment is the host.
            if (isCustom) uri.host?.let { parts.add(0, it) }
            val index = parts.indexOf("pair")
            if (index < 0 || index + 1 >= parts.size) return null
            return parts[index + 1].uppercase()
        }

        /** The pairing RPC's terse exceptions, in copy a person can act on. */
        fun friendlyPairingError(message: String?): String {
            val text = message.orEmpty().lowercase()
            return when {
                "invalid or expired code" in text -> "That code didn't work. It may have expired. Ask your partner for a fresh one."
                "cannot pair with yourself" in text -> "That's your own code. Share it with your partner and enter theirs here."
                "you are already in a couple" in text -> "You're already paired. Unpair in Settings before using a new code."
                "inviter already in a couple" in text -> "Whoever shared that code is already paired with someone."
                else -> "Pairing didn't work. Check the code and try again."
            }
        }
    }
}

/** `ReminderRepository.swift`. Android refreshes on resume instead of realtime (see the rule file). */
class ReminderRepository(
    private val client: SupabaseClient,
    private val pairing: PairingService,
    private val seed: SeedMode,
) {
    var reminders by mutableStateOf<List<ReminderDto>>(emptyList())
    var isLoading by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
    var onChange: (List<ReminderDto>) -> Unit = {}

    /** The couple the current `reminders` were fetched for. */
    private var loadedCoupleId: UUID? = null

    /**
     * True once a refresh has succeeded for the couple the app is on now. Until
     * then an empty list means "not fetched", not "no reminders", and a schedule
     * rebuilt from it would cancel every armed reminder.
     */
    val hasLoaded: Boolean get() = loadedCoupleId != null && loadedCoupleId == pairing.coupleId

    /** Reads the couple's reminders. True when the list is now what the server holds. */
    suspend fun refresh(): Boolean {
        if (seed.enabled) return true
        val coupleId = pairing.coupleId ?: return false
        isLoading = true
        try {
            val rows = client.select("reminders", "select=*&couple_id=eq.$coupleId&order=fire_at.asc.nullslast")
            reminders = Codec.objects(rows).map(Codec::reminder)
            loadedCoupleId = coupleId
            lastError = null
            onChange(reminders)
            return true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
            logError("reminders", "refresh failed", error)
            return false
        } finally {
            isLoading = false
        }
    }

    /**
     * Puts rows the server just accepted into the loaded list when the re-read
     * after the write failed, so the list and the schedule rebuilt from it show
     * the save instead of what was there before it. Before any list loaded there
     * is nothing to patch: the rebuild waits for a fetch anyway.
     */
    private fun keepSaved(saved: List<ReminderDto>) {
        if (!hasLoaded) return
        var list = reminders
        for (row in saved) {
            list = if (list.any { it.id == row.id }) list.map { if (it.id == row.id) row else it } else list + row
        }
        reminders = list
        onChange(reminders)
    }

    suspend fun upsert(reminder: ReminderDto) {
        if (seed.enabled) {
            reminders = (reminders.filter { it.id != reminder.id } + reminder).sortedWith(byFireAt)
            onChange(reminders)
            return
        }
        val stored = client.upsert("reminders", Codec.reminderJson(reminder))
        val saved = runCatching { Codec.objects(stored).firstOrNull()?.let(Codec::reminder) }.getOrNull() ?: reminder
        if (!refresh()) keepSaved(listOf(saved))
    }

    /** Moves a reminder the partner wrote: its schedule is all the target may change. */
    suspend fun reschedule(reminder: ReminderDto) {
        if (seed.enabled) {
            upsert(reminder)
            return
        }
        client.rpc("reschedule_reminder", Codec.rescheduleJson(reminder))
        if (!refresh()) reminders.firstOrNull { it.id == reminder.id }?.let { keepSaved(listOf(it.withSchedule(reminder))) }
    }

    suspend fun bulkInsert(drafts: List<ReminderDto>) {
        if (drafts.isEmpty()) return
        if (seed.enabled) {
            reminders = (reminders + drafts).sortedWith(byFireAt)
            onChange(reminders)
            return
        }
        client.insert("reminders", JSONArray(drafts.map(Codec::reminderJson)))
        if (!refresh()) keepSaved(drafts)
    }

    suspend fun delete(reminder: ReminderDto) {
        if (!seed.enabled) client.delete("reminders", "id=eq.${reminder.id}")
        reminders = reminders.filter { it.id != reminder.id }
        onChange(reminders)
    }

    private val byFireAt = compareBy<ReminderDto, Instant?>(nullsLast()) { it.fireAt }
}

/** `ReminderEventRepository.swift`: completions. */
class ReminderEventRepository(
    private val client: SupabaseClient,
    private val pairing: PairingService,
    private val seed: SeedMode,
) {
    var events by mutableStateOf<List<ReminderEventDto>>(emptyList())
    var lastError by mutableStateOf<String?>(null)

    /** The couple the current `events` were fetched for. */
    private var loadedCoupleId: UUID? = null

    /**
     * True once a refresh has succeeded for the couple the app is on now. Until
     * then an empty `events` means "not fetched", not "nothing done", and a
     * schedule rebuilt from it would ping every handled reminder again.
     */
    val hasLoaded: Boolean get() = loadedCoupleId != null && loadedCoupleId == pairing.coupleId

    /** The completions a schedule rebuild may trust: null until fetched for the couple the app is on. */
    val loadedEvents: List<ReminderEventDto>? get() = if (hasLoaded) events else null

    /** Reads the couple's completions. True when the list is now what the server holds. */
    suspend fun refresh(): Boolean {
        if (seed.enabled) return true
        val coupleId = pairing.coupleId ?: return false
        return try {
            val rows = client.select("reminder_events", "select=*&couple_id=eq.$coupleId&order=fired_at.desc")
            events = Codec.objects(rows).map(Codec::event)
            loadedCoupleId = coupleId
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
            logError("events", "refresh failed", error)
            false
        }
    }

    /** Records "I did this". Throws when the server did not take it. */
    suspend fun createEvent(reminderId: UUID, coupleId: UUID, now: Instant = Instant.now()) {
        val event = ReminderEventDto(UUID.randomUUID(), reminderId, coupleId, now, now)
        if (seed.enabled) {
            events = listOf(event) + events
            return
        }
        client.insert(
            "reminder_events",
            JSONObject()
                .put("id", event.id.toString())
                .put("reminder_id", reminderId.toString())
                .put("couple_id", coupleId.toString())
                .put("fired_at", now.toString())
                .put("acted_at", now.toString()),
        )
        refresh()
        // The server has it even when the re-read failed. Without it here the reminder
        // still looks open, and a second tap records it twice.
        if (events.none { it.id == event.id }) events = listOf(event) + events
    }

    /**
     * Marks a reminder done. True only when the completion was saved, which is
     * what lets the caller count it as a positive moment.
     */
    suspend fun markDone(reminder: ReminderDto, coupleId: UUID, now: Instant = Instant.now()): Boolean =
        try {
            createEvent(reminder.id, coupleId, now)
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
            logError("events", "marking done failed", error)
            false
        }

    /**
     * Undo of "done": removes every completion covering the current period. Both
     * partners can tick off a shared reminder, so there may be more than one, and
     * leaving any behind keeps it done.
     */
    suspend fun undoCompletion(reminder: ReminderDto, now: Instant = Instant.now()) {
        val covering = reminder.currentCompletionEvents(events, now)
        if (covering.isEmpty()) return
        val ids = covering.map { it.id }.toSet()
        if (!seed.enabled) client.delete("reminder_events", "id=in.(${ids.joinToString(",")})")
        events = events.filter { it.id !in ids }
    }
}

/** `MilestonesService.swift`. */
class MilestonesService(
    private val client: SupabaseClient,
    private val pairing: PairingService,
    private val scheduler: ReminderScheduling,
    private val seed: SeedMode,
) {
    var milestones by mutableStateOf<List<MilestoneDto>>(emptyList())
    var lastError by mutableStateOf<String?>(null)

    suspend fun refresh() {
        if (seed.enabled) return
        val coupleId = pairing.coupleId ?: return
        try {
            val rows = client.select("milestones", "select=*&couple_id=eq.$coupleId")
            milestones = Codec.objects(rows).map(Codec::milestone)
            scheduler.rescheduleMilestones(milestones)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
            logError("milestones", "refresh failed", error)
        }
    }

    suspend fun upsert(milestone: MilestoneDto) {
        if (seed.enabled) {
            milestones = milestones.filter { it.id != milestone.id } + milestone
            return
        }
        client.upsert("milestones", Codec.milestoneJson(milestone))
        refresh()
    }

    suspend fun delete(milestone: MilestoneDto) {
        if (!seed.enabled) client.delete("milestones", "id=eq.${milestone.id}")
        milestones = milestones.filter { it.id != milestone.id }
        if (!seed.enabled) scheduler.rescheduleMilestones(milestones)
    }

    fun nextOccurrence(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Pair<MilestoneDto, LocalDate>? =
        milestones.map { it to it.nextOccurrence(now, zone) }.minByOrNull { it.second }
}

/** `DailyCheckInService.swift`. */
class DailyCheckInService(
    private val client: SupabaseClient,
    private val auth: AuthService,
    private val pairing: PairingService,
    private val seed: SeedMode,
) {
    var todaysQuestion by mutableStateOf<DailyQuestionDto?>(null)
    var myResponse by mutableStateOf<QuestionResponseDto?>(null)
    var partnerResponse by mutableStateOf<QuestionResponseDto?>(null)
    var isLoading by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)

    val hasBothResponded: Boolean get() = myResponse != null && partnerResponse != null

    suspend fun loadTodaysQuestion(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        if (seed.enabled) return
        val coupleId = pairing.coupleId ?: return
        isLoading = true
        try {
            val count = client.count("daily_questions") ?: 30
            val index = questionIndex(dayNumber(now, zone), stableSeed(coupleId), count)
            // Explicit order: both partners must resolve the same index to the same row.
            val rows = client.select("daily_questions", "select=*&order=id.asc&offset=$index&limit=1")
            val dayQuestion = Codec.objects(rows).firstOrNull()?.let(Codec::question)
            if (dayQuestion == null) {
                todaysQuestion = DailyQuestionDto(
                    UUID.randomUUID(),
                    "What is one thing you appreciated about your partner today?",
                    "appreciation",
                    LoveLanguage.WORDS,
                )
                return
            }
            val me = auth.currentUserId ?: return
            val recent = recentResponses(coupleId, now)
            val currentId = currentQuestionId(dayQuestion.id, recent, me, now, zone)
            val question = if (currentId == dayQuestion.id) {
                dayQuestion
            } else {
                val row = client.select("daily_questions", "select=*&id=eq.$currentId&limit=1")
                Codec.objects(row).firstOrNull()?.let(Codec::question) ?: throw SupabaseException(404, "Question not found")
            }
            todaysQuestion = question
            apply(recent, question.id, me)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
            logError("checkin", "load failed", error)
        } finally {
            isLoading = false
        }
    }

    /**
     * The couple's answers from the last two days: an open question was answered
     * within a day, and the second answer to it within the next. Older ones belong
     * to an earlier round of the same question.
     */
    private suspend fun recentResponses(coupleId: UUID, now: Instant): List<QuestionResponseDto> {
        val since = now.minusMillis(2 * OPEN_WINDOW_MS)
        val rows = client.select(
            "question_responses",
            "select=*&couple_id=eq.$coupleId&created_at=gte.${SupabaseClient.encode(since.toString())}",
        )
        return Codec.objects(rows).map(Codec::response)
    }

    private fun apply(responses: List<QuestionResponseDto>, questionId: UUID, me: UUID) {
        val answers = responses.filter { it.questionId == questionId }
        myResponse = answers.firstOrNull { it.userId == me }
        partnerResponse = answers.firstOrNull { it.userId != me }
    }

    private suspend fun loadResponses(questionId: UUID, coupleId: UUID) {
        val me = auth.currentUserId ?: return
        try {
            apply(recentResponses(coupleId, Instant.now()), questionId, me)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            logError("checkin", "responses failed", error)
        }
    }

    suspend fun submitResponse(text: String, now: Instant = Instant.now()) {
        val me = auth.currentUserId
        val coupleId = pairing.coupleId
        val question = todaysQuestion
        if (me == null || coupleId == null || question == null) {
            lastError = "Not set up yet."
            return
        }
        if (seed.enabled) {
            myResponse = QuestionResponseDto(UUID.randomUUID(), question.id, coupleId, me, text, now)
            return
        }
        isLoading = true
        try {
            client.upsert(
                "question_responses",
                JSONObject()
                    .put("question_id", question.id.toString())
                    .put("couple_id", coupleId.toString())
                    .put("user_id", me.toString())
                    .put("response", text)
                    // A question comes round again after the bank is used up; the new answer
                    // starts a new round, so its time moves with it.
                    .put("created_at", now.toString()),
                onConflict = "question_id,couple_id,user_id",
            )
            loadResponses(question.id, coupleId)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            lastError = error.message
        } finally {
            isLoading = false
        }
    }

    fun reset() {
        todaysQuestion = null
        myResponse = null
        partnerResponse = null
        lastError = null
    }

    companion object {
        /** How far back an answer can still be the couple's open question. */
        const val OPEN_WINDOW_MS = 24L * 3_600_000

        /** Swift's `ordinality(of: .day, in: .era)` for a Gregorian date: days since 0001-01-01, plus one. */
        fun dayOrdinal(day: LocalDate): Long = day.toEpochDay() + 719_163

        /**
         * The day a question belongs to: the local calendar date, numbered the way the
         * store version numbers its UTC date, so the two agree for every hour the dates
         * are the same.
         */
        fun dayNumber(at: Instant, zone: ZoneId = ZoneId.systemDefault()): Long =
            dayOrdinal(at.atZone(zone).toLocalDate())

        /** UUID bytes folded as `(acc &* 31) &+ byte`, stable across processes and platforms. */
        fun stableSeed(uuid: UUID): Long {
            var acc = 0L
            val bytes = java.nio.ByteBuffer.allocate(16)
                .putLong(uuid.mostSignificantBits).putLong(uuid.leastSignificantBits).array()
            for (b in bytes) acc = acc * 31 + (b.toLong() and 0xff)
            return acc
        }

        fun questionIndex(day: Long, seed: Long, count: Int): Int =
            abs((day + seed) % maxOf(count, 1)).toInt()

        fun questionIndex(day: LocalDate, coupleId: UUID, count: Int): Int =
            questionIndex(dayOrdinal(day), stableSeed(coupleId), count)

        /**
         * Which question the couple is on, so both partners answer the same one and each
         * sees the reveal, whatever their zones or app versions:
         * 1. one the partner answered in the last day and this user has not,
         * 2. else one both answered, completed today, to keep showing the reveal,
         * 3. else one this user answered in the last day and the partner has not,
         * 4. else the question of this user's local day.
         * A question answered first is the couple's until the other answers it (for a
         * day), so a midnight between the two answers, a partner in another zone, or a
         * partner on a version that changes at 00:00 UTC no longer splits them onto
         * different questions.
         */
        fun currentQuestionId(
            dayQuestion: UUID,
            responses: List<QuestionResponseDto>,
            me: UUID,
            now: Instant,
            zone: ZoneId = ZoneId.systemDefault(),
        ): UUID {
            val openSince = now.minusMillis(OPEN_WINDOW_MS)
            val today = now.atZone(zone).toLocalDate()
            val waitingOnMe = mutableListOf<Pair<UUID, Instant>>()
            val revealedToday = mutableListOf<Pair<UUID, Instant>>()
            val waitingOnPartner = mutableListOf<Pair<UUID, Instant>>()
            for ((question, answers) in responses.groupBy { it.questionId }) {
                val mine = answers.firstOrNull { it.userId == me }
                val theirs = answers.firstOrNull { it.userId != me }
                when {
                    mine == null && theirs != null && theirs.createdAt.isAfter(openSince) ->
                        waitingOnMe += question to theirs.createdAt
                    mine != null && theirs != null -> {
                        val completed = maxOf(mine.createdAt, theirs.createdAt)
                        if (completed.atZone(zone).toLocalDate() == today) revealedToday += question to completed
                    }
                    mine != null && theirs == null && mine.createdAt.isAfter(openSince) ->
                        waitingOnPartner += question to mine.createdAt
                }
            }
            for (candidates in listOf(waitingOnMe, revealedToday, waitingOnPartner)) {
                candidates.maxByOrNull { it.second }?.let { return it.first }
            }
            return dayQuestion
        }
    }
}
