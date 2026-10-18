package com.jackwallner.bond.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import com.jackwallner.bond.AppGraph
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No graph") }

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

@Composable
fun currentActivity(): Activity? = LocalContext.current.findActivity()

/** Web links open in a Custom Tab; mail and market links go to their apps. */
fun openLink(context: Context, url: String) {
    val uri = Uri.parse(url)
    runCatching {
        if (uri.scheme == "http" || uri.scheme == "https") {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri)
        } else {
            context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    runCatching { context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

object Formats {
    private val zone: ZoneId get() = ZoneId.systemDefault()

    /** "Oct 18, 2026 at 6:30 PM" (`.formatted(date: .abbreviated, time: .shortened)`). */
    fun dateTime(instant: Instant): String {
        val local = instant.atZone(zone)
        val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()).format(local)
        val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()).format(local)
        return "$date at $time"
    }

    fun date(date: java.time.LocalDate, style: FormatStyle = FormatStyle.LONG): String =
        DateTimeFormatter.ofLocalizedDate(style).withLocale(Locale.getDefault()).format(date)

    fun time(instant: Instant): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()).format(instant.atZone(zone))

    /** `RelativeDateTimeFormatter` with `.full` units: "in 3 hours", "2 days ago". */
    fun relative(target: Instant, now: Instant = Instant.now()): String {
        val seconds = target.epochSecond - now.epochSecond
        val future = seconds >= 0
        val abs = kotlin.math.abs(seconds)
        val (value, unit) = when {
            abs < 60 -> abs to "second"
            abs < 3_600 -> abs / 60 to "minute"
            abs < 86_400 -> abs / 3_600 to "hour"
            abs < 7 * 86_400 -> abs / 86_400 to "day"
            abs < 30 * 86_400 -> abs / (7 * 86_400) to "week"
            abs < 365 * 86_400 -> abs / (30 * 86_400) to "month"
            else -> abs / (365 * 86_400) to "year"
        }
        if (unit == "second" && value == 0L) return "now"
        val phrase = "$value $unit${if (value == 1L) "" else "s"}"
        return if (future) "in $phrase" else "$phrase ago"
    }
}
