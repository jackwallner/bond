# 10 — Daily Check-In (full redesign)

**Current source:** `code-references/DailyCheckInView.swift`
**Priority:** P0 (this is the "magic feature" — see BRIEF Job 3)
**Status today:** A vertical `ScrollView` with: question card (gray bg) → your answer card (blue bg) → partner answer card (pink bg) → or input field. It works. It doesn't feel.

## The four states

### 10a. Pre-answer (neither has answered today)
- Today's question, prominent
- Love-language tag if `question.loveLanguage != nil`
- A text input, multi-line, with "Submit answer" CTA
- Subtle hint: "Your partner answers theirs separately — you'll see both once you've both replied."
- Question category (e.g. "Reflection") as a small chip

### 10b. You answered, partner hasn't (the in-between moment)
- Your answer shown, but the partner half is **occluded** — not "Waiting for your partner to answer..." with a spinner.
- Visual: a small sealed-envelope / blurred card / "covered" surface where the partner answer will be.
- Copy: "Your answer is in. Theirs will appear here when they answer."
- A small timestamp ("Submitted 9:42 AM") under your answer.
- No editing your answer once submitted (?) — decide and document.

### 10c. The reveal moment
- Auto-triggered when both responses exist and the user opens the screen.
- A short animation (~1.2s) that "unwraps" the partner's answer card.
- This is THE moment of the feature. See `motion/CHECK_IN_REVEAL.md` deliverable for spec.

### 10d. Both answered (post-reveal, return visit)
- Question + both answers shown side-by-side or stacked
- Date stamp at top ("Wednesday, May 15")
- A small footer: "Tomorrow's question arrives at midnight" with a countdown.
- Subtle "Share this" affordance? *(open question — privacy implications)*

## Constraints
- All four states must render the *same* navigation chrome — no full-takeover.
- Must respect `solo` user: show a one-shot empty state ("This is for couples — pair up to use Check-In").
- Premium gate (`!store.isPremium`) takes precedence over all four — pattern from `screens-to-design/08_premium_gate.md`.
- Reveal animation must have a Reduce Motion fallback (instant show with a 0.2s opacity).
- The question selection itself is broken today (B5 in MVP_TRIAGE) — your design assumes it's fixed.

## Don't
- Don't make the reveal feel like a slot machine. No suspense music. No "rewards." This is intimate, not entertainment.
- Don't show your partner's typing in real-time. They submit, you see. No collaborative editor.
- Don't auto-advance to tomorrow's question — that's not how relationships work.
