# 03 — Pairing (Generate + Accept)

**Current source:** `code-references/PairingView.swift`
**Priority:** P0 — single highest-friction moment in MVP
**Status today:** SwiftUI `Form` with three `Section`s — explainer / generate / accept. The generated URL is shown as monospaced text plus a ShareLink. The code is shown as a separate monospaced `Text`.

## Job
Two people are physically apart and need to connect their accounts in under 30 seconds. The generator screen must produce something instantly shareable. The acceptor screen must work both via universal link (no UI seen — just lands deep in the app) **and** via manual code entry (some couples are in the same room and just type it).

## Two distinct surfaces
### 3a. Generate (host)
- Big code (6 chars, monospaced) — the headline element
- A "Share" affordance — universal link via `ShareLink`
- Clear instruction: "Send this to your partner. They tap the link or type the code."
- Show expiry ("expires in 24h") because it does

### 3b. Accept (guest)
- A code-entry text field — 6 boxes, segmented look, auto-uppercase, autocorrect off
- A "Pair" button — disabled until 6 chars
- A "I got a link instead" affordance? Optional — the link path bypasses this view.

Today these are stacked on one screen. We could split into two screens behind a `Picker` ("I'll send / I'll receive") at the top.

## Constraints
- Code alphabet excludes ambiguous chars (no `I O 0 1`). Don't change the alphabet.
- 6 chars, all caps. Don't redesign to 8.
- Universal link host `bond.jackwallner.com` — don't redesign the URL.
- Manual entry must support paste.

## Failure states
- "Code expired." (60s after 24h elapses)
- "Code invalid." (typo)
- "You're already paired." (both halves were already in a couple)
- "Pair with yourself? Choose Solo instead." (entering your own code)

All of these today surface as red footnote text. Design something that doesn't feel like a form-validation error.

## Questions
1. Big code centered vs left-aligned?
2. QR code option? Would simplify same-room pairing but is more SF Symbols can't render — we'd need `CoreImage.CIFilter("CIQRCodeGenerator")` (acceptable, stock framework). Propose if you think it's worth the screen real estate.
3. Should the share message be designer-specified copy? Today it's "Someone special wants to pair up with you on Bond! 💌"
