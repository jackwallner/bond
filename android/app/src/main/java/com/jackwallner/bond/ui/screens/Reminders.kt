package com.jackwallner.bond.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddCircleOutline
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.HourglassTop
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.NotificationsNone
import androidx.compose.material.icons.rounded.QuestionAnswer
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Done
import androidx.compose.material.icons.rounded.VolunteerActivism
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.AppGraph
import com.jackwallner.bond.data.Membership
import com.jackwallner.bond.model.RecurrencePreset
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderTrigger
import com.jackwallner.bond.model.StarterChip
import com.jackwallner.bond.model.StarterChips
import com.jackwallner.bond.model.currentCompletionEvent
import com.jackwallner.bond.model.isCompleted
import com.jackwallner.bond.model.repeatsOnSchedule
import com.jackwallner.bond.ui.Formats
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.BackButton
import com.jackwallner.bond.ui.components.Capsule
import com.jackwallner.bond.ui.components.Chevron
import com.jackwallner.bond.ui.components.Detent
import com.jackwallner.bond.ui.components.GroupSection
import com.jackwallner.bond.ui.components.IconChip
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.PillButton
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.RowDivider
import com.jackwallner.bond.ui.components.SectionHeader
import com.jackwallner.bond.ui.components.SheetController
import com.jackwallner.bond.ui.components.TextLink
import com.jackwallner.bond.ui.components.TopBar
import com.jackwallner.bond.ui.components.icon
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Radius
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import com.jackwallner.bond.ui.theme.semibold
import com.jackwallner.bond.ui.theme.weight
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** The completion and delete paths shared by home, Handled and the editor. */
class ReminderActions(private val graph: AppGraph, private val scope: CoroutineScope) {
    /** Reminders with a toggle in flight, so a double tap can't write two completion events. */
    val toggling = mutableStateListOf<UUID>()

    fun isActedOn(reminder: ReminderDto): Boolean = reminder.isCompleted(graph.events.events)

    fun toggle(reminder: ReminderDto) {
        if (isActedOn(reminder)) uncomplete(reminder) else complete(reminder)
    }

    fun complete(reminder: ReminderDto) {
        val coupleId = graph.pairing.coupleId ?: return
        if (reminder.id in toggling || isActedOn(reminder)) return
        toggling.add(reminder.id)
        scope.launch {
            try {
                runCatching { graph.events.createEvent(reminder.id, coupleId) }
                graph.rescheduleNotifications()
                graph.review.recordPositiveMoment()
                graph.positiveMoments += 1
            } finally {
                toggling.remove(reminder.id)
            }
        }
    }

    fun uncomplete(reminder: ReminderDto) {
        if (reminder.id in toggling) return
        val event = reminder.currentCompletionEvent(graph.events.events) ?: return
        toggling.add(reminder.id)
        scope.launch {
            try {
                runCatching { graph.events.deleteEvent(event) }
                graph.rescheduleNotifications()
            } finally {
                toggling.remove(reminder.id)
            }
        }
    }

    fun delete(reminder: ReminderDto) {
        scope.launch {
            runCatching { graph.reminders.delete(reminder) }
            graph.rescheduleNotifications()
        }
    }
}

private enum class HomeRoute { CHECK_IN, HANDLED }

fun SheetController.presentEditor(existing: ReminderDto?, prefill: StarterChip? = null) {
    present("editor", Detent.LARGE) { dismiss -> ReminderEditorSheet(existing, prefill, onClose = dismiss) }
}

fun SheetController.presentTemplates() {
    present("templates", Detent.LARGE) { dismiss -> ReminderTemplatesSheet(onClose = dismiss) }
}

/** `ReminderListView.swift`, the Reminders tab. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReminderListScreen() {
    val graph = LocalGraph.current
    val sheets = LocalSheets.current
    val scope = rememberCoroutineScope()
    val actions = remember(graph) { ReminderActions(graph, scope) }
    val repo = graph.reminders
    val pairing = graph.pairing
    val me = graph.auth.currentUserId
    var hasLoadedOnce by remember { mutableStateOf(graph.seed.enabled) }
    var refreshing by remember { mutableStateOf(false) }
    var route by remember { mutableStateOf<HomeRoute?>(null) }

    suspend fun reload() {
        repo.refresh()
        graph.events.refresh()
    }

    LaunchedEffect(pairing.coupleId) {
        reload()
        hasLoadedOnce = true
        graph.rescheduleNotifications()
        if (!pairing.solo && pairing.coupleId != null && !graph.seed.enabled) graph.checkIn.loadTodaysQuestion()
        maybeShowNotificationPrimer(graph, sheets)
    }
    LaunchedEffect(graph.pendingReminderId, repo.reminders) {
        val id = graph.pendingReminderId ?: return@LaunchedEffect
        val match = repo.reminders.firstOrNull { it.id == id } ?: return@LaunchedEffect
        graph.pendingReminderId = null
        route = null
        sheets.presentEditor(match)
    }
    LaunchedEffect(pairing.justPaired) { if (pairing.justPaired) sheets.dismiss("pairing") }

    when (route) {
        HomeRoute.CHECK_IN -> {
            BackHandler { route = null }
            DailyCheckInScreen(onBack = { route = null })
            return
        }
        HomeRoute.HANDLED -> {
            BackHandler { route = null }
            HandledRemindersScreen(actions, onBack = { route = null })
            return
        }
        null -> Unit
    }

    val now = Instant.now()
    val visible = if (me == null) emptyList() else repo.reminders.filter { it.authorId == me || it.targetId == me }
    val active = visible.filter { it.repeatsOnSchedule() || !actions.isActedOn(it) }
    val partnerRequests = if (me == null || pairing.solo) emptyList() else sortByNext(active.filter { it.authorId != me }, now)
    val mine = active.filter { it.authorId == me }
    val pastDue = sortByNext(mine.filter { isPastDue(it, now) }, now)
    val upNext = sortByNext(mine.filter { !isPastDue(it, now) && nextDate(it, now) != null }, now) +
        sortByCreated(mine.filter { !isPastDue(it, now) && nextDate(it, now) == null })
    val handled = sortByCreated(visible.filter { !it.repeatsOnSchedule() && actions.isActedOn(it) })
    val partnerName = pairing.partnerProfile?.displayName?.takeIf { it.isNotEmpty() } ?: "Your partner"
    val checkIn = graph.checkIn
    val checkInState = when {
        pairing.solo || checkIn.todaysQuestion == null -> null
        checkIn.myResponse == null -> CheckInCardState.PENDING
        checkIn.partnerResponse == null -> CheckInCardState.AWAITING
        else -> CheckInCardState.READY
    }

    val warning = Bond.colors.warning
    Box(Modifier.fillMaxSize().testTag("screen.reminders")) {
        Column(Modifier.fillMaxSize()) {
            TopBar(com.jackwallner.bond.data.Membership.NAME, large = true)
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = { scope.launch { refreshing = true; reload(); refreshing = false } },
                modifier = Modifier.weight(1f),
            ) {
                when {
                    !hasLoadedOnce && repo.isLoading && repo.reminders.isEmpty() ->
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Bond.colors.accent) }
                    visible.isEmpty() -> EmptyRemindersView(
                        chips = StarterChips.forPreferences(graph.prefs.focusAreas, graph.prefs.partnerLoveLanguage),
                        onTapChip = { sheets.presentEditor(null, it) },
                        onBrowseTemplates = { sheets.presentTemplates() },
                    )
                    else -> LazyColumn(
                        Modifier.fillMaxSize().testTag("reminders.list"),
                        contentPadding = PaddingValues(top = Spacing.s, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(Spacing.base),
                    ) {
                        checkInState?.let { state ->
                            item("checkin") {
                                CheckInPromptCard(state, partnerName, Modifier.padding(horizontal = Spacing.base)) { route = HomeRoute.CHECK_IN }
                            }
                        }
                        if (partnerRequests.isNotEmpty()) {
                            item("from.header") { SectionHeader("From $partnerName", modifier = Modifier.padding(horizontal = Spacing.base)) }
                            items(partnerRequests, key = { "req.${it.id}" }) { reminder ->
                                PartnerRequestCard(
                                    reminder, partnerName, now,
                                    onEdit = { sheets.presentEditor(reminder) },
                                    onDone = { actions.complete(reminder) },
                                )
                            }
                        }
                        if (mine.isEmpty() && partnerRequests.isEmpty()) {
                            item("clear") {
                                MyListEmptyView(partnerName, !pairing.solo, onAdd = { sheets.presentEditor(null) })
                            }
                        }
                        reminderSection("pastdue", "Past due", warning, pastDue, me, actions, sheets)
                        reminderSection("upnext", "Up next", null, upNext, me, actions, sheets)
                        if (handled.isNotEmpty()) {
                            item("handled") {
                                GroupSection {
                                    com.jackwallner.bond.ui.components.GroupRow(onClick = { route = HomeRoute.HANDLED }, tag = "reminders.handled") {
                                        BText("Handled", BondType.subheadline, modifier = Modifier.weight(1f))
                                        BText("${handled.size}", BondType.subheadline, Bond.colors.inkSecondary)
                                        Spacer(Modifier.width(Spacing.xs))
                                        Chevron()
                                    }
                                }
                            }
                        }
                        if (pairing.solo && !graph.flags.pairingNudgeDismissed) {
                            item("nudge") {
                                var dismissed by remember { mutableStateOf(false) }
                                if (!dismissed) {
                                    GroupSection {
                                        PairingNudgeRow(
                                            onPair = { sheets.present("pairing") { d -> PairingSheet(onClose = d) } },
                                            onDismiss = { graph.flags.pairingNudgeDismissed = true; dismissed = true },
                                        )
                                    }
                                }
                            }
                        }
                        item("templates") {
                            GroupSection { TemplatesHomeRow(graph.subscriptions.isPremium) { sheets.presentTemplates() } }
                        }
                    }
                }
            }
        }
        ComposeButton(Modifier.align(Alignment.BottomEnd)) { sheets.presentEditor(null) }
    }
}

private fun LazyListScope.reminderSection(
    key: String,
    title: String,
    tint: Color?,
    reminders: List<ReminderDto>,
    me: UUID?,
    actions: ReminderActions,
    sheets: SheetController,
) {
    if (reminders.isEmpty()) return
    item(key) {
        GroupSection(header = title, headerTint = tint ?: Bond.colors.muted) {
            reminders.forEachIndexed { index, reminder ->
                if (index > 0) RowDivider(start = 56.dp)
                key(reminder.id) { SwipeableReminderRow(reminder, me, actions, onOpen = { sheets.presentEditor(reminder) }) }
            }
        }
    }
}

/** Leading swipe marks done (or undoes), trailing swipe deletes, like the iOS swipe actions. */
@Composable
fun SwipeableReminderRow(reminder: ReminderDto, me: UUID?, actions: ReminderActions, onOpen: () -> Unit) {
    val acted = actions.isActedOn(reminder)
    val state = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    SwipeToDismissBox(
        state = state,
        onDismiss = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> actions.toggle(reminder)
                SwipeToDismissBoxValue.EndToStart -> actions.delete(reminder)
                SwipeToDismissBoxValue.Settled -> Unit
            }
            scope.launch { state.reset() }
        },
        backgroundContent = {
            val toEnd = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            val colors = Bond.colors
            Box(
                Modifier.fillMaxSize().background(if (toEnd) (if (acted) colors.inkSecondary else colors.success) else colors.danger)
                    .padding(horizontal = Spacing.l),
                contentAlignment = if (toEnd) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Icon(
                    if (toEnd) (if (acted) Icons.AutoMirrored.Rounded.Undo else Icons.Rounded.Done) else Icons.Rounded.Delete,
                    null, tint = Color.White,
                )
            }
        },
    ) {
        Box(Modifier.background(Bond.colors.cardFill)) {
            ReminderRow(reminder, me, acted, onToggleDone = { actions.toggle(reminder) }, onClick = onOpen)
        }
    }
}

/** `ReminderRow.swift`. */
@Composable
fun ReminderRow(
    reminder: ReminderDto,
    me: UUID?,
    isActedOn: Boolean,
    onToggleDone: (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    val colors = Bond.colors
    val tint = colors.tint(reminder.loveLanguage)
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = Spacing.base, vertical = 10.dp)
            .alpha(if (isActedOn) 0.6f else 1f).testTag("reminder.row.${reminder.title}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.Top) {
            Box(
                Modifier.size(28.dp).clip(CircleShape)
                    .then(if (onToggleDone != null) Modifier.clickable(onClick = onToggleDone) else Modifier)
                    .semantics { contentDescription = if (isActedOn) "Mark as not done" else "Mark as done" }
                    .testTag("reminder.toggle.${reminder.title}"),
                contentAlignment = Alignment.Center,
            ) {
                if (isActedOn) {
                    Icon(Icons.Rounded.CheckCircle, null, tint = colors.success, modifier = Modifier.size(28.dp))
                } else {
                    Box(Modifier.fillMaxSize().border(BorderStroke(1.5.dp, tint.copy(alpha = 0.45f)), CircleShape))
                    Icon(reminder.loveLanguage.icon, null, tint = tint, modifier = Modifier.size(14.dp))
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                BText(reminder.title, BondType.headline, maxLines = 2)
                reminder.body?.takeIf { it.isNotEmpty() }?.let { BText(it, BondType.subheadline, colors.inkSecondary, maxLines = 2) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (isActedOn) {
                        BText(doneLabel(reminder), BondType.caption.semibold, colors.success)
                    } else {
                        reminder.trigger?.upcomingFireDate()?.let { BText(Formats.relative(it), BondType.caption, colors.inkSecondary) }
                    }
                    cadenceLabel(reminder)?.let { Capsule(it, colors.hairline) }
                    if (reminder.targetId != me) Capsule("for partner", tint.copy(alpha = 0.15f))
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        Chevron()
    }
}

private fun doneLabel(reminder: ReminderDto): String {
    val t = reminder.trigger
    val preset = (t as? ReminderTrigger.Recurring)?.let { RecurrencePreset.fromRrule(it.rrule) }
        ?: return if (reminder.repeatsOnSchedule()) "Done today" else "Done"
    return when (preset) {
        RecurrencePreset.DAILY -> "Done today"
        RecurrencePreset.WEEKLY -> "Done this week"
        RecurrencePreset.MONTHLY -> "Done this month"
        RecurrencePreset.YEARLY -> "Done this year"
    }
}

private fun cadenceLabel(reminder: ReminderDto): String? {
    if (reminder.trigger is ReminderTrigger.RandomRecurring) return "Daily surprise"
    if (reminder.triggerType != "recurring") return null
    return reminder.rrule?.let(RecurrencePreset::fromRrule)?.title
}

private fun nextDate(reminder: ReminderDto, now: Instant): Instant? = reminder.trigger?.upcomingFireDate(now)

private fun isPastDue(reminder: ReminderDto, now: Instant): Boolean =
    (reminder.trigger as? ReminderTrigger.OneTime)?.fireAt?.isBefore(now) == true

private fun sortByNext(list: List<ReminderDto>, now: Instant) = list.sortedBy { nextDate(it, now) ?: Instant.MAX }

private fun sortByCreated(list: List<ReminderDto>) = list.sortedByDescending { it.createdAt ?: Instant.MIN }

/** The primer shows once, only while the system permission hasn't been asked. */
private fun maybeShowNotificationPrimer(graph: AppGraph, sheets: SheetController) {
    val scheduler = graph.notifications
    if (graph.flags.hasShownNotificationPrimer || scheduler.isAuthorized || scheduler.permissionAsked || graph.seed.enabled) {
        graph.primerResolved = true
        return
    }
    graph.flags.hasShownNotificationPrimer = true
    var requested = false
    sheets.present("primer", Detent.MEDIUM, onDismiss = { if (!requested) graph.primerResolved = true }) { dismiss ->
        NotificationPrimerSheet(
            onRequest = {
                requested = true
                graph.scope.launch {
                    scheduler.permissionAsked = true
                    graph.permissions.request()
                    graph.rescheduleNotifications()
                    graph.notifications.rescheduleMilestones(graph.milestones.milestones)
                    graph.primerResolved = true
                }
                dismiss()
            },
            onLater = dismiss,
        )
    }
}

/** `NotificationPrimerSheet.swift`. */
@Composable
fun NotificationPrimerSheet(onRequest: () -> Unit, onLater: () -> Unit) {
    val colors = Bond.colors
    Column(
        Modifier.fillMaxWidth().padding(top = Spacing.l).padding(horizontal = Spacing.base).testTag("primer"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        Spacer(Modifier.height(Spacing.s))
        Icon(Icons.Rounded.NotificationsNone, null, tint = colors.accent, modifier = Modifier.size(48.dp))
        Column(Modifier.padding(horizontal = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.m), horizontalAlignment = Alignment.CenterHorizontally) {
            BText("${Membership.NAME} is silent without your permission.", BondType.title2.bold, align = TextAlign.Center)
            BText(
                "Reminders fire as notifications. No notifications, no reminders. That's the whole app.",
                BondType.body, colors.inkSecondary, align = TextAlign.Center,
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            PrimaryButton("Turn on notifications", tag = "primer.allow", onClick = onRequest)
            TextLink("Maybe later", style = BondType.footnote, color = colors.inkSecondary, tag = "primer.later", onClick = onLater)
        }
        Spacer(Modifier.height(Spacing.s))
    }
}

@Composable
private fun ComposeButton(modifier: Modifier, onClick: () -> Unit) {
    val colors = Bond.colors
    Box(
        modifier.padding(Spacing.base).size(58.dp)
            .shadow(12.dp, CircleShape, ambientColor = colors.accent.copy(alpha = 0.28f), spotColor = colors.accent.copy(alpha = 0.28f))
            .clip(CircleShape).background(colors.accent).clickable(onClick = onClick)
            .semantics { contentDescription = "Add reminder" }.testTag("reminders.add"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Rounded.Add, null, tint = Color.White, modifier = Modifier.size(30.dp))
    }
}

/** Floating warm-white card with a hairline and soft shadow (`HomeHeroCardBackground`). */
@Composable
private fun HeroCard(modifier: Modifier = Modifier, loud: Boolean = false, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val colors = Bond.colors
    val shape = RoundedCornerShape(Radius.card)
    Box(
        modifier.fillMaxWidth().shadow(6.dp, shape, ambientColor = colors.shadow, spotColor = colors.shadow).clip(shape)
            .then(if (loud) Modifier.background(colors.accentGradient) else Modifier.background(colors.cardFill).border(BorderStroke(0.5.dp, colors.hairline), shape))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(Spacing.base),
    ) { content() }
}

enum class CheckInCardState { PENDING, AWAITING, READY }

@Composable
private fun CheckInPromptCard(state: CheckInCardState, partnerName: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = Bond.colors
    val loud = state == CheckInCardState.READY
    val (icon, headline, subhead) = when (state) {
        CheckInCardState.PENDING -> Triple(Icons.Rounded.QuestionAnswer, "Today's check-in", "Answer to see $partnerName's reply.")
        CheckInCardState.AWAITING -> Triple(Icons.Rounded.HourglassTop, "Waiting on $partnerName", "We'll let you know when their answer lands.")
        CheckInCardState.READY -> Triple(Icons.Rounded.AutoAwesome, "$partnerName answered", "Tap to reveal both answers.")
    }
    HeroCard(modifier.testTag("reminders.checkInCard"), loud = loud, onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconChip(icon, tint = if (state == CheckInCardState.AWAITING) colors.inkSecondary else colors.accent, onGradient = loud)
            Spacer(Modifier.width(Spacing.m))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                BText(headline, BondType.subheadline.semibold, if (loud) Color.White else colors.ink)
                BText(subhead, BondType.caption, if (loud) Color.White.copy(alpha = 0.85f) else colors.inkSecondary)
            }
            Chevron(if (loud) Color.White.copy(alpha = 0.7f) else colors.inkTertiary)
        }
    }
}

@Composable
private fun PartnerRequestCard(reminder: ReminderDto, partnerName: String, now: Instant, onEdit: () -> Unit, onDone: () -> Unit) {
    val colors = Bond.colors
    val next = reminder.trigger?.upcomingFireDate(now)
    HeroCard(Modifier.padding(horizontal = Spacing.base).testTag("reminders.request.${reminder.title}")) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            Row(verticalAlignment = Alignment.Top) {
                IconChip(Icons.Rounded.AutoAwesome)
                Spacer(Modifier.width(Spacing.m))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    BText("$partnerName added this", BondType.caption.semibold, colors.accent)
                    BText(reminder.title, BondType.headline)
                    reminder.body?.takeIf { it.isNotEmpty() }?.let { BText(it, BondType.subheadline, colors.inkSecondary) }
                    next?.let {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Schedule, null, tint = colors.inkSecondary, modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(4.dp))
                            BText(Formats.dateTime(it), BondType.caption, colors.inkSecondary)
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                PillButton(if (next == null) "Pick a time" else "Reschedule", prominent = true, onClick = onEdit)
                PillButton("Handled", prominent = false, tag = "request.handled", onClick = onDone)
            }
        }
    }
}

@Composable
private fun PairingNudgeRow(onPair: () -> Unit, onDismiss: () -> Unit) {
    val colors = Bond.colors
    Row(Modifier.fillMaxWidth().padding(start = Spacing.base, end = Spacing.s, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable(onClick = onPair).padding(vertical = Spacing.s).testTag("reminders.pairNudge"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Favorite, null, tint = colors.accent, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(Spacing.m))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                BText("Pair with your partner", BondType.subheadline.semibold)
                BText("Share reminders and a daily check-in.", BondType.caption, colors.inkSecondary)
            }
            Spacer(Modifier.width(Spacing.s))
            BText("Pair", BondType.subheadline.bold, colors.accent)
        }
        Box(
            Modifier.size(40.dp).clip(CircleShape).clickable(onClick = onDismiss).semantics { contentDescription = "Dismiss" }
                .testTag("reminders.pairNudge.dismiss"),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Close, null, tint = colors.inkSecondary, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun MyListEmptyView(partnerName: String, isPaired: Boolean, onAdd: () -> Unit) {
    val colors = Bond.colors
    Column(
        Modifier.fillMaxWidth().padding(vertical = Spacing.xxl, horizontal = Spacing.base),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.base),
    ) {
        Icon(Icons.Rounded.VolunteerActivism, null, tint = colors.accent, modifier = Modifier.size(40.dp))
        BText("Your list is clear", BondType.title3.bold)
        BText(
            if (isPaired) "Add something for you or $partnerName, or pick a template below." else "Add a reminder, or pick a template below.",
            BondType.subheadline, colors.inkSecondary, align = TextAlign.Center,
        )
        PillButton("Add one", prominent = true, onClick = onAdd)
    }
}

@Composable
private fun TemplatesHomeRow(isPremium: Boolean, onTap: () -> Unit) {
    val colors = Bond.colors
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onTap).padding(horizontal = Spacing.base, vertical = 14.dp).testTag("reminders.templates"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.GridView, null, tint = colors.accent, modifier = Modifier.width(28.dp).size(20.dp))
        Spacer(Modifier.width(Spacing.m))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                BText("Reminder templates", BondType.subheadline.semibold)
                if (!isPremium) {
                    Row(
                        Modifier.clip(CircleShape).background(colors.accent).padding(horizontal = Spacing.s, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Rounded.Lock, null, tint = Color.White, modifier = Modifier.size(9.dp))
                        Spacer(Modifier.width(3.dp))
                        BText(Membership.PLUS, BondType.caption2.weight(FontWeight.ExtraBold), Color.White, maxLines = 1)
                    }
                }
            }
            BText("Date nights, long distance, daily affirmations & more", BondType.caption, colors.inkSecondary, maxLines = 2)
        }
        Chevron()
    }
}

/** `EmptyRemindersView.swift`. */
@Composable
private fun EmptyRemindersView(chips: List<StarterChip>, onTapChip: (StarterChip) -> Unit, onBrowseTemplates: () -> Unit) {
    val colors = Bond.colors
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 96.dp).testTag("reminders.empty")) {
        Spacer(Modifier.height(Spacing.xxxl))
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            Icon(Icons.Rounded.VolunteerActivism, null, tint = colors.inkSecondary, modifier = Modifier.size(48.dp))
            BText("No reminders yet.", BondType.title3.bold)
            BText(
                "Add one with the + button, or start with these.", BondType.subheadline, colors.inkSecondary,
                align = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.xl),
            )
        }
        Spacer(Modifier.height(Spacing.xxl))
        Column(Modifier.padding(horizontal = Spacing.base), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            BText("Start here", BondType.subheadline.bold)
            chips.forEach { chip ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.inline)).background(colors.cardFill)
                        .clickable { onTapChip(chip) }.padding(horizontal = Spacing.base, vertical = Spacing.m)
                        .testTag("chip.${chip.title}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(chip.loveLanguage.icon, null, tint = colors.tint(chip.loveLanguage), modifier = Modifier.width(24.dp))
                    Spacer(Modifier.width(Spacing.m))
                    BText(chip.title, BondType.callout, modifier = Modifier.weight(1f))
                    Icon(Icons.Rounded.AddCircleOutline, null, tint = colors.inkTertiary)
                }
            }
        }
        Row(
            Modifier.align(Alignment.CenterHorizontally).padding(top = Spacing.base).clip(RoundedCornerShape(8.dp))
                .clickable(onClick = onBrowseTemplates).padding(Spacing.s).testTag("reminders.browseTemplates"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BText("Browse templates", BondType.footnote.bold, colors.accent)
            Spacer(Modifier.width(Spacing.xs))
            Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, tint = colors.accent, modifier = Modifier.size(14.dp))
        }
    }
}

/** `HandledRemindersView`: completed one-shots, pushed from home. */
@Composable
private fun HandledRemindersScreen(actions: ReminderActions, onBack: () -> Unit) {
    val graph = LocalGraph.current
    val sheets = LocalSheets.current
    val me = graph.auth.currentUserId
    val handled = graph.reminders.reminders
        .filter { it.authorId == me || it.targetId == me }
        .filter { !it.repeatsOnSchedule() && it.isCompleted(graph.events.events) }
        .sortedByDescending { it.createdAt ?: Instant.MIN }
    Column(Modifier.fillMaxSize().testTag("screen.handled")) {
        TopBar("Handled", leading = { BackButton(onBack) })
        LazyColumn(contentPadding = PaddingValues(vertical = Spacing.base)) {
            item {
                GroupSection {
                    handled.forEachIndexed { index, reminder ->
                        if (index > 0) RowDivider(start = 56.dp)
                        key(reminder.id) { SwipeableReminderRow(reminder, me, actions, onOpen = { sheets.presentEditor(reminder) }) }
                    }
                }
            }
        }
    }
}
