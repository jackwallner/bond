package com.jackwallner.bond.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.bold

enum class Detent { MEDIUM, LARGE }

/** One presented sheet. Content gets a `dismiss` that runs the sheet's onDismiss once. */
class SheetEntry(
    val id: String,
    val detent: Detent,
    val onDismiss: () -> Unit,
    val content: @Composable (dismiss: () -> Unit) -> Unit,
) {
    internal val visibility = MutableTransitionState(false).apply { targetState = true }
    internal var closing = false
}

/**
 * iOS sheets as in-window overlays, stacked: a paywall can rise over the
 * editor that opened it. In-tree (not dialogs) so UI tests and screenshots see
 * one window.
 */
@Stable
class SheetController {
    internal val stack = mutableStateListOf<SheetEntry>()

    fun present(
        id: String,
        detent: Detent = Detent.LARGE,
        onDismiss: () -> Unit = {},
        content: @Composable (dismiss: () -> Unit) -> Unit,
    ) {
        if (stack.any { it.id == id && !it.closing }) return
        stack.removeAll { it.id == id }
        stack.add(SheetEntry(id, detent, onDismiss, content))
    }

    fun isPresented(id: String): Boolean = stack.any { it.id == id && !it.closing }

    fun dismiss(id: String) {
        val entry = stack.lastOrNull { it.id == id && !it.closing } ?: return
        close(entry)
    }

    fun dismissAll() = stack.filter { !it.closing }.reversed().forEach(::close)

    internal fun close(entry: SheetEntry) {
        if (entry.closing) return
        entry.closing = true
        entry.visibility.targetState = false
        entry.onDismiss()
    }

    internal fun remove(entry: SheetEntry) {
        stack.remove(entry)
    }
}

val LocalSheets = staticCompositionLocalOf<SheetController> { error("No sheet controller") }

@Composable
fun SheetHost(controller: SheetController, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalSheets provides controller) {
        Box(Modifier.fillMaxSize()) {
            content()
            controller.stack.toList().forEach { entry -> SheetLayer(controller, entry) }
        }
    }
}

@Composable
private fun SheetLayer(controller: SheetController, entry: SheetEntry) {
    val dismiss = { controller.close(entry) }
    BackHandler(enabled = !entry.closing && controller.stack.lastOrNull() == entry) { dismiss() }
    LaunchedEffect(entry.visibility.isIdle, entry.visibility.currentState) {
        if (entry.visibility.isIdle && !entry.visibility.currentState && entry.closing) controller.remove(entry)
    }
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(entry.visibility, enter = fadeIn(tween(220)), exit = fadeOut(tween(200))) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.32f))
                    .clickable(remember { MutableInteractionSource() }, indication = null) { dismiss() },
            )
        }
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding()) {
            val maxHeight = maxHeight
            AnimatedVisibility(
                entry.visibility,
                modifier = Modifier.align(Alignment.BottomCenter),
                enter = slideInVertically(tween(300)) { it },
                exit = slideOutVertically(tween(240)) { it },
            ) {
                val shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
                val height = if (entry.detent == Detent.LARGE) Modifier.height(maxHeight - 10.dp) else Modifier.heightIn(max = maxHeight - 10.dp)
                Column(
                    Modifier.fillMaxWidth().then(height).clip(shape)
                        .background(Bond.colors.backgroundGradient)
                        // Swallow taps so they never reach the scrim, without a clickable that
                        // would merge the whole sheet into one accessibility node.
                        .pointerInput(Unit) { detectTapGestures { } }
                        .testTag("sheet.${entry.id}"),
                ) {
                    Box(Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(36.dp, 5.dp).clip(RoundedCornerShape(3.dp)).background(Bond.colors.inkTertiary.copy(alpha = 0.4f)))
                    }
                    Box(Modifier.weight(1f, fill = entry.detent == Detent.LARGE).navigationBarsPadding().imePadding()) {
                        entry.content(dismiss)
                    }
                }
            }
        }
    }
}

/**
 * Navigation bar in the iOS shape: a title (inline, or large under the bar)
 * with leading and trailing slots.
 */
@Composable
fun TopBar(
    title: String,
    large: Boolean = false,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    statusBarPadding: Boolean = true,
) {
    Column(Modifier.fillMaxWidth().then(if (statusBarPadding) Modifier.statusBarsPadding() else Modifier)) {
        Box(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 4.dp)) {
            Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically) { leading?.invoke() }
            if (!large) {
                BText(
                    title, BondType.headline.bold, modifier = Modifier.align(Alignment.Center).padding(horizontal = 72.dp),
                    align = TextAlign.Center, maxLines = 1,
                )
            }
            Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically) { trailing?.invoke() }
        }
        if (large) {
            BText(title, BondType.largeTitle.bold, modifier = Modifier.padding(start = Spacing.base, end = Spacing.base, bottom = Spacing.s))
        }
    }
}

@Composable
fun BackButton(onBack: () -> Unit) {
    IconButton(onClick = onBack, modifier = Modifier.semantics { contentDescription = "Back" }.testTag("nav.back")) {
        Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = Bond.colors.accent)
    }
}

/** The bar button in a sheet ("Cancel", "Done", "Save"). */
@Composable
fun BarButton(title: String, enabled: Boolean = true, bold: Boolean = false, tag: String? = null, onClick: () -> Unit) {
    TextLink(
        title,
        style = if (bold) BondType.body.bold else BondType.body,
        enabled = enabled,
        tag = tag,
        onClick = onClick,
    )
}

/** Sheet chrome: a bar with Cancel / title / confirm, then the content. */
@Composable
fun SheetScaffold(
    title: String,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        TopBar(title, leading = leading, trailing = trailing, statusBarPadding = false)
        content()
    }
}

@Composable
fun VSpace(height: androidx.compose.ui.unit.Dp) = Spacer(Modifier.height(height))

@Composable
fun HSpace(width: androidx.compose.ui.unit.Dp) = Spacer(Modifier.width(width))
