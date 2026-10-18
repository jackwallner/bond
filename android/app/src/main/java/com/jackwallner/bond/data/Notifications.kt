package com.jackwallner.bond.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.jackwallner.bond.BondApplication
import com.jackwallner.bond.MainActivity
import com.jackwallner.bond.R
import com.jackwallner.bond.model.MilestoneDto
import com.jackwallner.bond.model.NotificationPlanner
import com.jackwallner.bond.model.NotificationSpec
import com.jackwallner.bond.model.RecurrencePreset
import com.jackwallner.bond.model.ReminderDto
import com.jackwallner.bond.model.ReminderEventDto
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONObject

/** The platform half: post-permission state and alarm arming, faked in tests. */
interface AlarmPlatform {
    fun canNotify(): Boolean
    fun arm(spec: NotificationSpec)
    fun cancel(id: String)
}

/**
 * `NotificationScheduler.swift` on inexact alarms. Every pending ping is
 * persisted (so a reboot can re-arm it) under an id index; milestone ids keep
 * their `milestone.` prefix so reminder churn leaves them alone, as on iOS.
 */
class AlarmNotificationScheduler(
    private val platform: AlarmPlatform,
    private val defaults: KeyValueStore,
    private val now: () -> Instant = Instant::now,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) : ReminderScheduling {
    val isAuthorized: Boolean get() = platform.canNotify()

    /** Asked at least once (primer or system dialog), so "never asked" stays distinct from "denied". */
    var permissionAsked: Boolean
        get() = defaults.getBoolean(ASKED_KEY)
        set(value) = defaults.putBoolean(ASKED_KEY, value)

    override fun reschedule(selfId: UUID, reminders: List<ReminderDto>, events: List<ReminderEventDto>) {
        ids().filterNot { it.startsWith(MILESTONE_PREFIX) }.forEach(::remove)
        NotificationPlanner.reminderSpecs(selfId, reminders, events, now(), zone()).forEach(::put)
    }

    override fun rescheduleMilestones(milestones: List<MilestoneDto>) {
        ids().filter { it.startsWith(MILESTONE_PREFIX) }.forEach(::remove)
        NotificationPlanner.milestoneSpecs(milestones, now(), zone()).forEach(::put)
    }

    override fun clearAll() = ids().forEach(::remove)

    fun spec(id: String): NotificationSpec? = defaults.getString(specKey(id))?.let(::parse)

    fun pendingSpecs(): List<NotificationSpec> = ids().mapNotNull(::spec).sortedBy { it.fireAt }

    /** After a reboot, update or clock change: re-arm what is still ahead, roll repeats forward. */
    fun rearmAll() {
        val current = now()
        for (id in ids()) {
            val spec = spec(id) ?: continue
            when {
                spec.repeat != null -> rollForward(spec, current)?.let(::put) ?: remove(id)
                spec.fireAt.isAfter(current) -> platform.arm(spec)
                else -> remove(id)
            }
        }
    }

    /** A one-shot that fired is spent; a recurring one re-arms for its next calendar match. */
    fun markDelivered(id: String) {
        val spec = spec(id) ?: return
        if (spec.repeat == null) {
            remove(id)
            return
        }
        val next = rollForward(spec, maxOf(now(), spec.fireAt))
        if (next == null) remove(id) else put(next)
    }

    private fun rollForward(spec: NotificationSpec, after: Instant): NotificationSpec? {
        val preset = spec.repeat ?: return null
        if (spec.fireAt.isAfter(after)) return spec
        val next = NotificationPlanner.nextCalendarMatch(spec.anchor ?: spec.fireAt, preset, after, zone()) ?: return null
        return spec.copy(fireAt = next)
    }

    private fun put(spec: NotificationSpec) {
        defaults.putString(specKey(spec.id), json(spec))
        defaults.putStringSet(INDEX_KEY, ids() + spec.id)
        platform.arm(spec)
    }

    private fun remove(id: String) {
        defaults.remove(specKey(id))
        defaults.putStringSet(INDEX_KEY, ids() - id)
        platform.cancel(id)
    }

    private fun ids(): Set<String> = defaults.getStringSet(INDEX_KEY)

    companion object {
        const val CHANNEL_ID = "reminders"
        const val EXTRA_REMINDER_ID = "reminder_id"
        private const val MILESTONE_PREFIX = "milestone."
        private const val INDEX_KEY = "notifications.index"
        private const val ASKED_KEY = "notifications.permissionAsked"

        fun specKey(id: String) = "notificationSpec.$id"

        fun json(spec: NotificationSpec): String = JSONObject()
            .put("id", spec.id)
            .put("title", spec.title)
            .put("body", spec.body ?: JSONObject.NULL)
            .put("fireAt", spec.fireAt.toEpochMilli())
            .put("reminderId", spec.reminderId?.toString() ?: JSONObject.NULL)
            .put("repeat", spec.repeat?.name ?: JSONObject.NULL)
            .put("anchor", spec.anchor?.toEpochMilli() ?: JSONObject.NULL)
            .toString()

        fun parse(text: String): NotificationSpec? = runCatching {
            val o = JSONObject(text)
            NotificationSpec(
                id = o.getString("id"),
                title = o.getString("title"),
                body = if (o.isNull("body")) null else o.getString("body"),
                fireAt = Instant.ofEpochMilli(o.getLong("fireAt")),
                reminderId = if (o.isNull("reminderId")) null else UUID.fromString(o.getString("reminderId")),
                repeat = if (o.isNull("repeat")) null else RecurrencePreset.valueOf(o.getString("repeat")),
                anchor = if (o.isNull("anchor")) null else Instant.ofEpochMilli(o.getLong("anchor")),
            )
        }.getOrNull()

        fun ensureChannel(context: Context) {
            val channel = NotificationChannel(CHANNEL_ID, "Reminders", NotificationManager.IMPORTANCE_DEFAULT)
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}

/** Inexact windowed alarms: exact ones need a Play declaration, and a few minutes late costs nothing here. */
class AndroidAlarmPlatform(private val context: Context) : AlarmPlatform {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    override fun canNotify(): Boolean {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return granted && NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    override fun arm(spec: NotificationSpec) {
        alarms.setWindow(AlarmManager.RTC_WAKEUP, spec.fireAt.toEpochMilli(), WINDOW_MS, pending(spec.id))
    }

    override fun cancel(id: String) = alarms.cancel(pending(id))

    private fun pending(id: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        id.hashCode(),
        Intent(context, ReminderReceiver::class.java).putExtra(EXTRA_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val EXTRA_ID = "bond.notificationId"
        private const val WINDOW_MS = 15 * 60 * 1000L
    }
}

/** Waits on the activity's permission dialog. */
class PermissionBridge {
    private var pending: CompletableDeferred<Boolean>? = null
    var launch: (() -> Unit)? = null

    suspend fun request(): Boolean {
        val launcher = launch ?: return false
        val deferred = CompletableDeferred<Boolean>()
        pending = deferred
        launcher()
        return deferred.await()
    }

    fun complete(granted: Boolean) {
        pending?.complete(granted)
        pending = null
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(AndroidAlarmPlatform.EXTRA_ID) ?: return
        val scheduler = (context.applicationContext as? BondApplication)?.graph?.notifications ?: return
        val spec = scheduler.spec(id) ?: return
        scheduler.markDelivered(id)
        if (!scheduler.isAuthorized) return
        AlarmNotificationScheduler.ensureChannel(context)
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .apply { spec.reminderId?.let { putExtra(AlarmNotificationScheduler.EXTRA_REMINDER_ID, it.toString()) } }
        val content = PendingIntent.getActivity(
            context, id.hashCode(), open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, AlarmNotificationScheduler.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(spec.title)
            .setContentIntent(content)
            .setAutoCancel(true)
        spec.body?.let { builder.setContentText(it).setStyle(NotificationCompat.BigTextStyle().bigText(it)) }
        try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), builder.build())
        } catch (_: SecurityException) {
            // Permission revoked between the check and the post.
        }
    }
}

/** Alarms do not survive a reboot, an update, or a clock change. */
class ScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        (context.applicationContext as? BondApplication)?.graph?.notifications?.rearmAll()
    }
}
