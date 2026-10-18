package com.jackwallner.bond.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CardGiftcard
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.Mail
import androidx.compose.material.icons.rounded.PanTool
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.VolunteerActivism
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.model.LoveLanguage
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Radius
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold
import com.jackwallner.bond.ui.theme.semibold

/** `LoveLanguage.symbolName` in Material symbols. */
val LoveLanguage.icon: ImageVector
    get() = when (this) {
        LoveLanguage.WORDS -> Icons.Rounded.FormatQuote
        LoveLanguage.ACTS -> Icons.Rounded.VolunteerActivism
        LoveLanguage.GIFTS -> Icons.Rounded.CardGiftcard
        LoveLanguage.TIME -> Icons.Rounded.Schedule
        LoveLanguage.TOUCH -> Icons.Rounded.PanTool
    }

@Composable
fun BText(
    text: String,
    style: TextStyle = BondType.body,
    color: Color = Bond.colors.ink,
    modifier: Modifier = Modifier,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    Text(
        text, modifier = modifier, style = style, color = color, textAlign = align,
        maxLines = maxLines, overflow = if (maxLines == Int.MAX_VALUE) TextOverflow.Clip else TextOverflow.Ellipsis,
    )
}

/** `BondSoftButtonStyle`: top-lit gradient, warm shadow, sinks when pressed, flattens when disabled. */
@Composable
fun PrimaryButton(
    title: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false,
    destructive: Boolean = false,
    icon: ImageVector? = null,
    tag: String? = null,
    onClick: () -> Unit,
) {
    val colors = Bond.colors
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val active = enabled && !isLoading
    val scale by animateFloatAsState(if (pressed) 0.98f else 1f, label = "press")
    val shape = RoundedCornerShape(Radius.inline)
    val fill: Brush = when {
        destructive -> Brush.verticalGradient(listOf(colors.danger.copy(alpha = 0.92f), colors.danger))
        enabled -> colors.accentGradient
        else -> Brush.linearGradient(listOf(Color(0xFF9E9590), Color(0xFF8A817C)))
    }
    Box(
        modifier
            .fillMaxWidth()
            .scale(scale)
            .shadow(if (enabled) (if (pressed) 2.dp else 8.dp) else 0.dp, shape, ambientColor = colors.shadow, spotColor = colors.shadow)
            .clip(shape)
            .background(fill)
            .alpha(if (enabled) (if (pressed) 0.92f else 1f) else 0.55f)
            .clickable(interactionSource = interaction, indication = null, enabled = active, role = Role.Button, onClick = onClick)
            .heightIn(min = 52.dp)
            .padding(horizontal = Spacing.l)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .semantics { contentDescription = title },
        contentAlignment = Alignment.Center,
    ) {
        if (isLoading) {
            CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.5.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                icon?.let { Icon(it, null, tint = Color.White) }
                BText(title, BondType.headline, Color.White, maxLines = 1)
            }
        }
    }
}

/** A tappable text button in the accent colour (iOS plain `Button`). */
@Composable
fun TextLink(
    title: String,
    modifier: Modifier = Modifier,
    style: TextStyle = BondType.subheadline.semibold,
    color: Color = Bond.colors.accent,
    enabled: Boolean = true,
    tag: String? = null,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .heightIn(min = 40.dp)
            .padding(horizontal = Spacing.s, vertical = Spacing.xs)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        BText(title, style, if (enabled) color else color.copy(alpha = 0.45f), align = TextAlign.Center)
    }
}

/** A smaller filled or outlined accent button (iOS `.borderedProminent` / `.bordered`). */
@Composable
fun PillButton(title: String, prominent: Boolean, modifier: Modifier = Modifier, tag: String? = null, onClick: () -> Unit) {
    val colors = Bond.colors
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier
            .clip(shape)
            .background(if (prominent) colors.accent else colors.accent.copy(alpha = 0.14f))
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 40.dp)
            .padding(horizontal = 14.dp, vertical = 8.dp)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        BText(title, BondType.subheadline.semibold, if (prominent) Color.White else colors.accent)
    }
}

@Composable
fun SectionHeader(title: String, tint: Color = Bond.colors.muted, modifier: Modifier = Modifier) {
    BText(title, BondType.footnote.semibold, tint, modifier.padding(start = Spacing.base, bottom = 6.dp, top = 2.dp))
}

/** An inset grouped section: warm-white rows on the cream wash, with a header and footer. */
@Composable
fun GroupSection(
    modifier: Modifier = Modifier,
    header: String? = null,
    headerTint: Color = Bond.colors.muted,
    footer: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.base)) {
        header?.let { SectionHeader(it, headerTint) }
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(Bond.colors.cardFill),
            content = content,
        )
        footer?.let { Box(Modifier.padding(horizontal = Spacing.base, vertical = 6.dp)) { it() } }
    }
}

@Composable
fun RowDivider(start: Dp = Spacing.base) {
    HorizontalDivider(Modifier.padding(start = start), thickness = 0.5.dp, color = Bond.colors.hairline)
}

/** One row of a grouped section. */
@Composable
fun GroupRow(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    tag: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .heightIn(min = 48.dp)
            .padding(horizontal = Spacing.base, vertical = 10.dp)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun Chevron(tint: Color = Bond.colors.inkTertiary) {
    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = tint, modifier = Modifier.size(20.dp))
}

@Composable
fun InlineError(message: String, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = Spacing.base), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.ErrorOutline, null, tint = Bond.colors.danger, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        BText(message, BondType.footnote, Bond.colors.danger)
    }
}

@Composable
fun ScreenHeader(title: String, subtitle: String? = null, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        BText(title, BondType.title.bold)
        subtitle?.let { BText(it, BondType.body, Bond.colors.inkSecondary) }
    }
}

@Composable
fun SoftCard(
    modifier: Modifier = Modifier,
    radius: Dp = Radius.card,
    fill: Brush? = null,
    hairline: Boolean = true,
    elevation: Dp = 6.dp,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Bond.colors
    val shape = RoundedCornerShape(radius)
    Column(
        modifier
            .shadow(elevation, shape, ambientColor = colors.shadow, spotColor = colors.shadow)
            .clip(shape)
            .background(fill ?: Brush.linearGradient(listOf(colors.cardFill, colors.cardFill)))
            .then(if (hairline) Modifier.border(BorderStroke(0.5.dp, colors.hairline), shape) else Modifier)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(Spacing.base),
        content = content,
    )
}

/** `BondChoiceCard`. */
@Composable
fun ChoiceCard(
    icon: ImageVector,
    title: String,
    description: String,
    tint: Color = Bond.colors.inkSecondary,
    selected: Boolean = false,
    tag: String? = null,
    trailing: @Composable () -> Unit = {},
    onClick: () -> Unit,
) {
    val colors = Bond.colors
    val shape = RoundedCornerShape(Radius.card)
    Row(
        Modifier
            .fillMaxWidth()
            .shadow(6.dp, shape, ambientColor = colors.shadow, spotColor = colors.shadow)
            .clip(shape)
            .background(colors.cardFill)
            .border(if (selected) BorderStroke(2.dp, colors.accent) else BorderStroke(0.5.dp, colors.hairline), shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(Spacing.base)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(28.dp))
        Spacer(Modifier.width(Spacing.base))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            BText(title, BondType.headline)
            BText(description, BondType.subheadline, colors.inkSecondary)
        }
        Spacer(Modifier.width(Spacing.s))
        trailing()
    }
}

/** `BondSealedCard`: a dashed placeholder for an answer not yet revealed. */
@Composable
fun SealedCard(title: String, hint: String, modifier: Modifier = Modifier) {
    val colors = Bond.colors
    val shape = RoundedCornerShape(Radius.inline)
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = 96.dp)
            .clip(shape)
            .background(colors.cardFill)
            .dashedBorder(colors.inkSecondary.copy(alpha = 0.4f), Radius.inline)
            .padding(Spacing.base),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Mail, null, tint = colors.inkSecondary, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(Spacing.s))
            BText(title, BondType.subheadline.bold)
        }
        BText(hint, BondType.callout, colors.inkSecondary)
    }
}

fun Modifier.dashedBorder(color: Color, radius: Dp): Modifier =
    drawWithContent {
        drawContent()
        val stroke = Stroke(width = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
        drawRoundRect(
            color = color,
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius.toPx()),
            style = stroke,
        )
    }

/** A small capsule label. */
@Composable
fun Capsule(text: String, background: Color, color: Color = Bond.colors.ink, style: TextStyle = BondType.caption2) {
    Box(Modifier.clip(CircleShape).background(background).padding(horizontal = 6.dp, vertical = 2.dp)) {
        BText(text, style, color, maxLines = 1)
    }
}

/** A circle with a tinted icon (`CardIconChip`). */
@Composable
fun IconChip(icon: ImageVector, tint: Color = Bond.colors.accent, onGradient: Boolean = false, size: Dp = 36.dp) {
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(if (onGradient) Color.White.copy(alpha = 0.2f) else tint.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = if (onGradient) Color.White else tint, modifier = Modifier.size(size * 0.5f))
    }
}

@Composable
fun ProvideInk(color: Color, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalContentColor provides color, content = content)
}

@Composable
fun CenteredColumn(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().widthIn(max = 560.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = content,
    )
}
