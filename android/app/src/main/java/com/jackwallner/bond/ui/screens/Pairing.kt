package com.jackwallner.bond.ui.screens

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddLink
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.QrCode2
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.jackwallner.bond.data.PairingService
import com.jackwallner.bond.ui.LocalGraph
import com.jackwallner.bond.ui.components.BarButton
import com.jackwallner.bond.ui.components.InlineError
import com.jackwallner.bond.ui.components.PrimaryButton
import com.jackwallner.bond.ui.components.ScreenHeader
import com.jackwallner.bond.ui.components.SheetScaffold
import com.jackwallner.bond.ui.components.TextLink
import com.jackwallner.bond.ui.components.BText
import com.jackwallner.bond.ui.shareText
import com.jackwallner.bond.ui.theme.Bond
import com.jackwallner.bond.ui.theme.BondType
import com.jackwallner.bond.ui.theme.Radius
import com.jackwallner.bond.ui.theme.Spacing
import com.jackwallner.bond.ui.theme.semibold
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class PairMode(val title: String) { SEND("Send"), RECEIVE("Receive") }

/**
 * `PairingView.swift`. Android pairs on the install's anonymous identity: no
 * Sign in with Apple gate (see `.claude/rules/android.md`).
 */
@Composable
fun PairingSheet(initialMode: PairMode = PairMode.SEND, onClose: () -> Unit) {
    val pairing = LocalGraph.current.pairing
    var mode by remember { mutableStateOf(initialMode) }
    LaunchedEffect(pairing.pendingInviteCode) {
        if (pairing.pendingInviteCode != null) pairing.waitForPartnerToPair()
    }
    LaunchedEffect(pairing.justPaired) { if (pairing.justPaired) onClose() }
    LaunchedEffect(Unit) { pairing.lastError = null }
    SheetScaffold("Pair", leading = { BarButton("Cancel", tag = "pair.cancel", onClick = onClose) }) {
        SegmentedControl(
            options = PairMode.entries.map { it.title },
            selected = mode.ordinal,
            onSelect = { mode = PairMode.entries[it]; pairing.lastError = null },
            modifier = Modifier.padding(horizontal = Spacing.base).padding(bottom = Spacing.base),
        )
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
            when (mode) {
                PairMode.SEND -> SendContent()
                PairMode.RECEIVE -> ReceiveContent()
            }
        }
    }
}

@Composable
fun SegmentedControl(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val colors = Bond.colors
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(colors.hairline.copy(alpha = 0.5f)).padding(2.dp),
    ) {
        options.forEachIndexed { index, title ->
            val isOn = index == selected
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(7.dp))
                    .background(if (isOn) colors.cardFill else Color.Transparent)
                    .clickable { onSelect(index) }
                    .padding(vertical = 7.dp)
                    .testTag("segment.$title"),
                contentAlignment = Alignment.Center,
            ) {
                BText(title, if (isOn) BondType.footnote.semibold else BondType.footnote, maxLines = 1)
            }
        }
    }
}

@Composable
private fun SendContent() {
    val pairing = LocalGraph.current.pairing
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var generating by remember { mutableStateOf(false) }
    var showQr by remember { mutableStateOf(false) }
    val generate: () -> Unit = {
        scope.launch {
            generating = true
            pairing.generateInviteCode()
            generating = false
        }
    }
    Column(Modifier.padding(vertical = Spacing.l), verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        ScreenHeader("Invite your partner", "Send them this link, or read them the code below.", Modifier.padding(horizontal = Spacing.base))
        CodeCard(pairing.pendingInviteCode ?: "------", Modifier.padding(horizontal = Spacing.base))
        pairing.pendingInviteExpiresAt?.let { ExpiryCaption(it, onRegenerate = generate) }
        val url = pairing.pendingInviteUrl
        if (url != null) {
            PrimaryButton("Share invite link", icon = Icons.Rounded.Share, modifier = Modifier.padding(horizontal = Spacing.base), tag = "pair.share") {
                shareText(
                    context,
                    "I'm using Little Gestures, a small app for sending each other little reminders. " +
                        "Tap the link to pair with me, or use the code: ${pairing.pendingInviteCode.orEmpty()}.\n$url",
                )
            }
            Column(Modifier.padding(horizontal = Spacing.base)) {
                Row(
                    Modifier.fillMaxWidth().clickable { showQr = !showQr }.padding(vertical = Spacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.QrCode2, null, tint = Bond.colors.inkSecondary, modifier = Modifier.size(20.dp))
                    BText("  Show QR code", BondType.subheadline, Bond.colors.inkSecondary, Modifier.weight(1f))
                    Icon(if (showQr) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null, tint = Bond.colors.accent)
                }
                if (showQr) {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                        QrCode(url)
                        BText("In the same room? Have them point their camera at this.", BondType.caption, Bond.colors.inkSecondary, align = TextAlign.Center)
                    }
                }
            }
        } else {
            PrimaryButton("Generate code", icon = Icons.Rounded.AddLink, isLoading = generating, modifier = Modifier.padding(horizontal = Spacing.base), tag = "pair.generate", onClick = generate)
        }
        pairing.lastError?.let { InlineError(it) }
    }
}

@Composable
private fun ReceiveContent() {
    val pairing = LocalGraph.current.pairing
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    Column(Modifier.padding(vertical = Spacing.l), verticalArrangement = Arrangement.spacedBy(Spacing.xl)) {
        ScreenHeader("Enter their code", "Six characters. Your partner can read it to you.", Modifier.padding(horizontal = Spacing.base))
        CodeEntryField(code, onChange = { code = it }, modifier = Modifier.padding(horizontal = Spacing.base))
        PrimaryButton(
            "Pair", enabled = code.length == 6, isLoading = pairing.isPairing,
            modifier = Modifier.padding(horizontal = Spacing.base), tag = "pair.submit",
        ) { scope.launch { pairing.consumeInviteCode(code.uppercase()) } }
        pairing.lastError?.let { InlineError(it) }
    }
}

@Composable
fun CodeCard(code: String, modifier: Modifier = Modifier, size: Int = 40) {
    val colors = Bond.colors
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.hero)).background(colors.surfaceElevated)
            .border(0.5.dp, colors.hairline, RoundedCornerShape(Radius.hero)).padding(vertical = Spacing.base)
            .semantics { contentDescription = "Pairing code: ${code.toList().joinToString(" ")}" }
            .testTag("pair.code"),
        horizontalArrangement = Arrangement.spacedBy(Spacing.s, Alignment.CenterHorizontally),
    ) {
        code.forEach { char ->
            Box(Modifier.size(width = (size + 4).dp, height = (size + 16).dp).clip(RoundedCornerShape(Radius.inline)).background(colors.cardFill), contentAlignment = Alignment.Center) {
                BText(char.toString(), TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = (size * 0.85).sp))
            }
        }
    }
}

@Composable
private fun ExpiryCaption(expiresAt: Instant, onRegenerate: () -> Unit) {
    val now by produceState(Instant.now(), expiresAt) {
        while (true) {
            value = Instant.now()
            delay(60_000)
        }
    }
    val remaining = Duration.between(now, expiresAt).seconds
    Column(Modifier.padding(horizontal = Spacing.base)) {
        if (remaining <= 0) {
            BText("This code has expired.", BondType.footnote, Bond.colors.inkSecondary)
            TextLink("Generate a new code", style = BondType.footnote.semibold, onClick = onRegenerate)
        } else {
            BText("Expires in ${remaining / 3600}h ${(remaining % 3600) / 60}m", BondType.footnote, Bond.colors.inkSecondary)
        }
    }
}

@Composable
private fun CodeEntryField(text: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val colors = Bond.colors
    val focus = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Box(modifier.fillMaxWidth().clickable { runCatching { focus.requestFocus() } }, contentAlignment = Alignment.Center) {
        BasicTextField(
            value = text,
            onValueChange = { raw ->
                onChange(raw.uppercase().filter { it in PairingService.INVITE_ALPHABET }.take(6))
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false,
                keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Done,
            ),
            modifier = Modifier.fillMaxWidth().alpha(0.02f).focusRequester(focus).onFocusChanged { focused = it.isFocused }
                .testTag("pair.codeEntry"),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
            for (i in 0 until 6) {
                val char = text.getOrNull(i)?.toString().orEmpty()
                val caret = i == text.length && focused
                Box(
                    Modifier.size(44.dp, 56.dp).clip(RoundedCornerShape(Radius.inline)).background(colors.cardFill)
                        .border(1.5.dp, if (caret) colors.accent else Color.Transparent, RoundedCornerShape(Radius.inline)),
                    contentAlignment = Alignment.Center,
                ) {
                    BText(char, TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 28.sp))
                }
            }
        }
    }
}

@Composable
private fun QrCode(content: String) {
    val bitmap = remember(content) {
        runCatching {
            val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 0, 0)
            val scale = 8
            val bmp = Bitmap.createBitmap(matrix.width * scale, matrix.height * scale, Bitmap.Config.ARGB_8888)
            for (x in 0 until matrix.width) for (y in 0 until matrix.height) {
                val color = if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
                for (dx in 0 until scale) for (dy in 0 until scale) bmp.setPixel(x * scale + dx, y * scale + dy, color)
            }
            bmp.asImageBitmap()
        }.getOrNull()
    } ?: return
    Box(Modifier.clip(RoundedCornerShape(Radius.card)).background(Color.White).padding(Spacing.base)) {
        Image(
            bitmap, contentDescription = "QR code containing your invite link", filterQuality = FilterQuality.None,
            modifier = Modifier.size(200.dp),
        )
    }
}
