package com.jackwallner.bond.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.bond.R
import com.jackwallner.bond.data.Accent
import com.jackwallner.bond.model.LoveLanguage

private fun rgb(r: Double, g: Double, b: Double, a: Double = 1.0) = Color(r.toFloat(), g.toFloat(), b.toFloat(), a.toFloat())

/** `BondStyle.swift` and `BondTheme.swift`, value for value: the "Soft Tactile" warm palette. */
@Immutable
data class BondColors(
    val isDark: Boolean,
    val accent: Color,
    val gradientStart: Color,
    val gradientEnd: Color,
    val secondary: Color,
    val gold: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val cardFill: Color,
    val hairline: Color,
    val shadow: Color,
    val muted: Color,
    val backgroundTop: Color,
    val backgroundBottom: Color,
    val ink: Color,
    val inkSecondary: Color,
    val inkTertiary: Color,
    val success: Color,
    val warning: Color,
    val danger: Color,
    val touch: Color,
) {
    val accentGradient: Brush get() = Brush.linearGradient(listOf(gradientStart, gradientEnd))
    val backgroundGradient: Brush get() = Brush.verticalGradient(listOf(backgroundTop, backgroundBottom))

    /** `LoveLanguage.tint`: the iOS system pink, orange, purple and blue, and the terracotta for touch. */
    fun tint(language: LoveLanguage): Color = when (language) {
        LoveLanguage.WORDS -> if (isDark) rgb(1.0, 0.216, 0.373) else rgb(1.0, 0.176, 0.333)
        LoveLanguage.ACTS -> if (isDark) rgb(1.0, 0.624, 0.039) else rgb(1.0, 0.584, 0.0)
        LoveLanguage.GIFTS -> if (isDark) rgb(0.749, 0.353, 0.949) else rgb(0.686, 0.322, 0.871)
        LoveLanguage.TIME -> if (isDark) rgb(0.039, 0.518, 1.0) else rgb(0.0, 0.478, 1.0)
        LoveLanguage.TOUCH -> touch
    }

    companion object {
        private val systemPinkLight = rgb(1.0, 0.176, 0.333)
        private val systemPinkDark = rgb(1.0, 0.216, 0.373)

        fun light(accent: Accent) = BondColors(
            isDark = false,
            accent = if (accent == Accent.PINK) systemPinkLight else rgb(0.745, 0.314, 0.282),
            gradientStart = if (accent == Accent.PINK) systemPinkLight.copy(alpha = 0.85f) else rgb(0.878, 0.518, 0.353),
            gradientEnd = if (accent == Accent.PINK) systemPinkLight else rgb(0.753, 0.314, 0.420),
            secondary = rgb(0.549, 0.353, 0.451),
            gold = rgb(0.784, 0.580, 0.235),
            surface = rgb(0.973, 0.886, 0.776),
            surfaceElevated = rgb(1.0, 0.945, 0.871),
            cardFill = rgb(1.0, 0.976, 0.945),
            hairline = rgb(0.71, 0.45, 0.30, 0.18),
            shadow = rgb(0.45, 0.22, 0.10, 0.12),
            muted = rgb(0.478, 0.357, 0.282),
            backgroundTop = rgb(0.973, 0.886, 0.776),
            backgroundBottom = rgb(0.949, 0.812, 0.682),
            ink = rgb(0.13, 0.10, 0.09),
            inkSecondary = rgb(0.40, 0.33, 0.29),
            inkTertiary = rgb(0.55, 0.47, 0.42),
            success = rgb(0.157, 0.627, 0.275),
            warning = rgb(0.86, 0.47, 0.0),
            danger = rgb(0.85, 0.20, 0.17),
            touch = rgb(0.71, 0.34, 0.25),
        )

        fun dark(accent: Accent) = BondColors(
            isDark = true,
            accent = if (accent == Accent.PINK) systemPinkDark else rgb(0.918, 0.553, 0.471),
            gradientStart = if (accent == Accent.PINK) systemPinkDark.copy(alpha = 0.85f) else rgb(0.933, 0.612, 0.447),
            gradientEnd = if (accent == Accent.PINK) systemPinkDark else rgb(0.816, 0.416, 0.518),
            secondary = rgb(0.780, 0.604, 0.690),
            gold = rgb(0.902, 0.753, 0.455),
            surface = rgb(0.106, 0.082, 0.075),
            surfaceElevated = rgb(0.176, 0.141, 0.129),
            cardFill = rgb(0.208, 0.173, 0.157),
            hairline = rgb(1.0, 0.85, 0.70, 0.14),
            shadow = rgb(0.0, 0.0, 0.0, 0.45),
            muted = rgb(0.788, 0.702, 0.643),
            backgroundTop = rgb(0.106, 0.082, 0.075),
            backgroundBottom = rgb(0.157, 0.114, 0.094),
            ink = rgb(0.96, 0.93, 0.90),
            inkSecondary = rgb(0.79, 0.72, 0.67),
            inkTertiary = rgb(0.62, 0.56, 0.52),
            success = rgb(0.188, 0.820, 0.345),
            warning = rgb(1.0, 0.62, 0.04),
            danger = rgb(1.0, 0.41, 0.38),
            touch = rgb(0.85, 0.44, 0.34),
        )
    }
}

val LocalBondColors = staticCompositionLocalOf { BondColors.light(Accent.TERRACOTTA) }

object Bond {
    val colors: BondColors
        @Composable @ReadOnlyComposable get() = LocalBondColors.current
}

object Spacing {
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val base = 16.dp
    val l = 20.dp
    val xl = 24.dp
    val xxl = 32.dp
    val xxxl = 48.dp
}

object Radius {
    val chip = 10.dp
    val inline = 16.dp
    val card = 24.dp
    val hero = 28.dp
}

/** Plus Jakarta Sans at the iOS text-style sizes (`BondFont.swift`). */
object BondType {
    val family = FontFamily(
        Font(R.font.plusjakartasans_regular, FontWeight.Normal),
        Font(R.font.plusjakartasans_medium, FontWeight.Medium),
        Font(R.font.plusjakartasans_semibold, FontWeight.SemiBold),
        Font(R.font.plusjakartasans_bold, FontWeight.Bold),
    )

    private fun style(size: Int, weight: FontWeight = FontWeight.Normal, line: Double = 1.25) =
        TextStyle(fontFamily = family, fontWeight = weight, fontSize = size.sp, lineHeight = (size * line).sp)

    val largeTitle = style(34, FontWeight.Bold, 1.2)
    val title = style(28, FontWeight.Bold, 1.2)
    val title2 = style(22, FontWeight.Bold)
    val title3 = style(20, FontWeight.Normal)
    val headline = style(17, FontWeight.SemiBold)
    val body = style(17)
    val callout = style(16)
    val subheadline = style(15)
    val footnote = style(13)
    val caption = style(12)
    val caption2 = style(11)
}

fun TextStyle.weight(value: FontWeight) = copy(fontWeight = value)
val TextStyle.bold get() = copy(fontWeight = FontWeight.Bold)
val TextStyle.semibold get() = copy(fontWeight = FontWeight.SemiBold)

@Composable
fun BondTheme(dark: Boolean, accent: Accent, content: @Composable () -> Unit) {
    val colors = if (dark) BondColors.dark(accent) else BondColors.light(accent)
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.accent, onPrimary = Color.White, background = colors.surface,
            surface = colors.surfaceElevated, onSurface = colors.ink, onBackground = colors.ink,
            surfaceVariant = colors.cardFill, onSurfaceVariant = colors.inkSecondary,
            surfaceContainerHigh = colors.surfaceElevated, surfaceContainerHighest = colors.cardFill,
            error = colors.danger, outline = colors.hairline,
        )
    } else {
        lightColorScheme(
            primary = colors.accent, onPrimary = Color.White, background = colors.surface,
            surface = colors.surfaceElevated, onSurface = colors.ink, onBackground = colors.ink,
            surfaceVariant = colors.cardFill, onSurfaceVariant = colors.inkSecondary,
            surfaceContainerHigh = colors.surfaceElevated, surfaceContainerHighest = colors.cardFill,
            error = colors.danger, outline = colors.hairline,
        )
    }
    val typography = MaterialTheme.typography.let { t ->
        t.copy(
            bodyLarge = BondType.body, bodyMedium = BondType.subheadline, bodySmall = BondType.footnote,
            titleLarge = BondType.title2, titleMedium = BondType.headline, titleSmall = BondType.subheadline.semibold,
            labelLarge = BondType.subheadline.semibold, labelMedium = BondType.footnote, labelSmall = BondType.caption,
            headlineSmall = BondType.title2, headlineMedium = BondType.title, headlineLarge = BondType.largeTitle,
        )
    }
    CompositionLocalProvider(LocalBondColors provides colors) {
        MaterialTheme(colorScheme = scheme, typography = typography, content = content)
    }
}
