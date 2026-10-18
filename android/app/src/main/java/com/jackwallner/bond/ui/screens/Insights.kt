package com.jackwallner.bond.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.Insights
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.model.LoveLanguageAnalyzer
import com.jackwallner.bond.model.repeatsOnSchedule
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.components.GroupRow
import com.jackwallner.bond.ui.components.GroupSection
import com.jackwallner.bond.ui.components.LocalSheets
import com.jackwallner.bond.ui.components.RowDivider
import com.jackwallner.bond.ui.components.TopBar
import com.jackwallner.bond.ui.components.icon
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import java.time.format.TextStyle
import java.util.Locale

private val PINK = Color(0xFFFF2D55)
private val ORANGE = Color(0xFFFF9500)
private val GREEN = Color(0xFF34C759)
private val YELLOW = Color(0xFFFFCC00)

/** `StatsView.swift`, the Insights tab. */
@Composable
fun InsightsScreen() {
    val graph = LocalGraph.current
    val sheets = LocalSheets.current
    LaunchedEffect(Unit) { graph.events.refresh() }
    val reminders = graph.reminders.reminders
    val events = graph.events.events
    val analyzer = LoveLanguageAnalyzer(reminders, events)

    Column(Modifier.fillMaxSize().testTag("screen.insights")) {
        TopBar("Insights", large = true)
        if (reminders.isEmpty()) {
            Unavailable(
                Icons.Rounded.BarChart, "No data yet",
                "Create reminders and mark them done to see your relationship analytics.",
                Modifier.testTag("insights.empty"),
            )
            return@Column
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = Spacing.base),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            GroupSection { StreakRow(analyzer) }
            if (!graph.subscriptions.isPremium) {
                UnlockCard(
                    Icons.Rounded.Insights, "Unlock the full picture",
                    "Little Gestures+ opens up your love-language balance, weekly trends, and personalized insights.",
                    onUnlock = { sheets.presentPaywall() },
                    modifier = Modifier.padding(horizontal = Spacing.base).testTag("insights.teaser"),
                )
                return@Column
            }
            val counts = analyzer.reminderCounts()
            val colors = Bond.colors
            GroupSection(
                header = "Balance score",
                footer = {
                    BText(
                        "How evenly your reminders cover the five love languages. 100 means a perfectly even spread; a low score means most of your reminders lean on one or two languages.",
                        BondType.footnote, colors.inkSecondary,
                    )
                },
                modifier = Modifier.testTag("insights.balance"),
            ) { BalanceSection(analyzer) }
            GroupSection(header = "Reminders per love language") {
                Box(Modifier.padding(Spacing.base)) { HorizontalBars(counts) }
            }
            FollowThroughSection(analyzer)
            val trends = analyzer.weeklyTrends()
            if (trends.isNotEmpty()) {
                GroupSection(header = "Weekly activity") {
                    Box(Modifier.padding(Spacing.base)) { WeeklyChart(trends) }
                }
            }
            val insights = analyzer.insights()
            if (insights.isNotEmpty()) {
                GroupSection(header = "Insights") {
                    insights.forEachIndexed { index, insight ->
                        if (index > 0) RowDivider()
                        GroupRow {
                            Icon(Icons.Rounded.Lightbulb, null, tint = YELLOW, modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(8.dp))
                            BText(insight, BondType.subheadline)
                        }
                    }
                }
            }
            GroupSection(header = "Summary") {
                val total = counts.sumOf { it.second }
                SummaryRow("Total reminders", total)
                RowDivider()
                SummaryRow("For partner", reminders.count { it.authorId != it.targetId })
                RowDivider()
                SummaryRow("Repeating", reminders.count { it.repeatsOnSchedule() })
                RowDivider()
                SummaryRow("Total actions", events.size)
                RowDivider()
                SummaryRow("Actions completed", events.count { it.actedAt != null })
            }
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: Int) {
    GroupRow {
        BText(label, BondType.body, modifier = Modifier.weight(1f))
        BText("$value", BondType.body, Bond.colors.inkSecondary)
    }
}

@Composable
private fun StreakRow(analyzer: LoveLanguageAnalyzer) {
    val rate = analyzer.completionRate()
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).padding(vertical = Spacing.base), verticalAlignment = Alignment.CenterVertically) {
        Metric("${analyzer.currentStreak()}", "day streak", PINK, Modifier.weight(1f))
        VerticalDivider(Modifier.height(40.dp), color = Bond.colors.hairline)
        Metric("${analyzer.longestStreak()}", "best streak", ORANGE, Modifier.weight(1f))
        VerticalDivider(Modifier.height(40.dp), color = Bond.colors.hairline)
        Metric(rate?.let { "${it.toInt()}%" } ?: "–", "done this week", GREEN, Modifier.weight(1f))
    }
}

@Composable
private fun Metric(value: String, label: String, tint: Color, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BText(value, BondType.title.bold, tint)
        BText(label, BondType.caption, Bond.colors.inkSecondary)
    }
}

@Composable
private fun BalanceSection(analyzer: LoveLanguageAnalyzer) {
    val colors = Bond.colors
    val score = analyzer.balanceScore()
    val ring = when {
        score > 60 -> GREEN
        score > 30 -> ORANGE
        else -> Color(0xFFFF3B30)
    }
    Column(Modifier.fillMaxWidth().padding(vertical = Spacing.base), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(80.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 10.dp.toPx()
                val inset = stroke / 2
                val arcSize = Size(size.width - stroke, size.height - stroke)
                drawArc(Color.Gray.copy(alpha = 0.2f), 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
                drawArc(ring, -90f, (score / 100.0 * 360).toFloat(), false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            BText("${score.toInt()}", BondType.title2.bold)
        }
        analyzer.mostUsed()?.let { (lang, _) -> LanguageLine("Most: ", lang) }
        analyzer.mostNeglected()?.let { (lang, _) -> LanguageLine("Needs attention: ", lang) }
    }
}

@Composable
private fun LanguageLine(prefix: String, lang: LoveLanguage) {
    val colors = Bond.colors
    Row(verticalAlignment = Alignment.CenterVertically) {
        BText(prefix, BondType.caption, colors.inkSecondary)
        BText(lang.title, BondType.caption.bold)
        Spacer(Modifier.width(4.dp))
        Icon(lang.icon, null, tint = colors.tint(lang), modifier = Modifier.size(12.dp))
    }
}

/** The per-language bar chart (`Chart` with horizontal `BarMark`s and trailing counts). */
@Composable
private fun HorizontalBars(counts: List<Pair<LoveLanguage, Int>>) {
    val colors = Bond.colors
    val max = maxOf(counts.maxOfOrNull { it.second } ?: 0, 1)
    Column(Modifier.fillMaxWidth().testTag("insights.bars"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        counts.forEach { (lang, count) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                BText(lang.title, BondType.caption, colors.inkSecondary, modifier = Modifier.width(132.dp), maxLines = 1)
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    if (count > 0) {
                        Box(
                            Modifier.weight(count.toFloat() / max).height(22.dp).clip(RoundedCornerShape(4.dp)).background(colors.tint(lang)),
                        )
                    }
                    Spacer(Modifier.width(6.dp))
                    BText("$count", BondType.caption2, colors.inkSecondary)
                    if (count < max) Spacer(Modifier.weight((max - count).toFloat() / max))
                }
            }
        }
    }
}

/** Weekly activity: grouped bars per week, one per love language (`.position(by:)`). */
@Composable
private fun WeeklyChart(trends: List<LoveLanguageAnalyzer.WeeklyTrend>) {
    val colors = Bond.colors
    val max = maxOf(trends.maxOfOrNull { week -> week.counts.maxOfOrNull { it.second } ?: 0 } ?: 0, 1)
    Column(Modifier.fillMaxWidth()) {
        Canvas(Modifier.fillMaxWidth().height(170.dp)) {
            val groupWidth = size.width / trends.size
            val barWidth = (groupWidth * 0.8f) / LoveLanguage.entries.size
            trends.forEachIndexed { weekIndex, week ->
                val start = weekIndex * groupWidth + groupWidth * 0.1f
                LoveLanguage.entries.forEachIndexed { langIndex, lang ->
                    val count = week.counts.firstOrNull { it.first == lang }?.second ?: 0
                    if (count == 0) return@forEachIndexed
                    val h = size.height * count / max
                    drawRoundRect(
                        colors.tint(lang),
                        topLeft = Offset(start + langIndex * barWidth + 1f, size.height - h),
                        size = Size(barWidth - 2f, h),
                        cornerRadius = CornerRadius(3f, 3f),
                    )
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth()) {
            trends.forEach { week ->
                BText(
                    week.weekStart.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault()) + " " + week.weekStart.dayOfMonth,
                    BondType.caption2, colors.inkSecondary, modifier = Modifier.weight(1f),
                    align = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun FollowThroughSection(analyzer: LoveLanguageAnalyzer) {
    val colors = Bond.colors
    val items = analyzer.followThrough()
    val byLanguage = analyzer.completionByLanguage().filter { it.expected > 0 }
    GroupSection(header = "Follow-through · last 7 days") {
        if (items.isEmpty() && byLanguage.isEmpty()) {
            GroupRow {
                BText("Mark reminders done (tap the circle on a reminder) and your follow-through shows up here.", BondType.footnote, colors.inkSecondary)
            }
            return@GroupSection
        }
        items.forEachIndexed { index, item ->
            if (index > 0) RowDivider()
            val tint = colors.tint(item.reminder.loveLanguage)
            GroupRow {
                Icon(item.reminder.loveLanguage.icon, null, tint = tint, modifier = Modifier.width(24.dp).size(18.dp))
                Spacer(Modifier.width(Spacing.m))
                BText(item.reminder.title, BondType.subheadline, maxLines = 1, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(Spacing.s))
                BText("${item.completed} of ${item.expected}", BondType.subheadline.copy(fontFeatureSettings = "tnum"), colors.inkSecondary)
                Spacer(Modifier.width(Spacing.m))
                LinearProgressIndicator(
                    progress = { item.completed.toFloat() / maxOf(item.expected, 1) },
                    modifier = Modifier.width(56.dp),
                    color = tint,
                    trackColor = tint.copy(alpha = 0.2f),
                    drawStopIndicator = {},
                )
            }
        }
        byLanguage.forEach { row ->
            RowDivider()
            GroupRow {
                BText(row.language.title, BondType.caption, colors.inkSecondary, modifier = Modifier.weight(1f))
                BText("${row.completed} of ${row.expected} done", BondType.caption.copy(fontFeatureSettings = "tnum"), colors.inkSecondary)
            }
        }
    }
}
