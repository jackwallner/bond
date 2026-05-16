# Design Brief — Bond v1 (MVP polish pass)

## Why this exists
Bond is functionally complete enough for TestFlight, but every screen is stock SwiftUI with default styling. We want it to feel **warm, intentional, and quietly premium** — not "couples app stock photo" cute, not Material-y, not iOS 7 fragile. Think: **AirMail-era Letter.app meets Things 3 meets the Calm app's reverence**.

## The three jobs we need design help with, in order

### 1. Make the first 60 seconds feel intentional
Onboarding → Preference Choice → Pairing → first Reminder. These are the highest-stakes screens because they're where TestFlighters bounce. Currently they're system `Form`s.

**Goal:** When a tester opens this for their partner, the partner says "oh, this is nice" within 5 seconds.

**Deliverable:** mockups (ASCII or mermaid OK; Figma frames better) for:
- Splash / Onboarding (with SIWA button)
- Preference Choice (Just me / With someone)
- Pairing Generate (host)
- Pairing Accept (guest, via universal link)
- Pairing Success (we land on this and then transition to Home — give the moment some weight)
- First-run Reminders empty state with CTA chips for templates

### 2. Give premium real estate that's worth paying for
We're using RevenueCat's default `PaywallView` and four "this is locked" gate screens (Milestones, Stats, Daily Check-In, Templates) that all look identical and shout "GIVE US MONEY." We want:

**Goal:** The gate screens feel like a *preview* of the feature, not a wall. The paywall feels like a love letter, not a pricing chart.

**Deliverable:**
- New gate-screen pattern (replaces `PremiumGateView.swift`) that shows a blurred / shimmering preview of the locked feature with the unlock CTA at the bottom — not a full takeover.
- Custom RevenueCat paywall layout spec (RevenueCat now supports remote paywall configs; design the structure & copy)
- Trial messaging (assume 7-day trial)
- Restore Purchases placement

### 3. Make the Daily Check-In emotionally land
The current Check-In is a textfield → submit → see your answer → wait → see partner's answer. It's fine. We want it to feel like opening a small envelope.

**Goal:** The "reveal partner's answer" moment is the most-anticipated app interaction of the user's day.

**Deliverable:**
- Today's Question screen (pre-answer)
- Your-answer-saved screen ("waiting for partner")
- Reveal moment animation spec (no Lottie / no third-party — Core Animation / SwiftUI primitives only)
- Both-answered comparison screen
- Tomorrow countdown / "see you tomorrow" outro

## Things to deliberately NOT redesign

- ReminderEditorView (it's a form — let SwiftUI do its thing; just propose better section headers and copy)
- Watch app (separate scope)
- Widgets (separate scope, already minimal)
- App tab bar layout (the four tabs stay)

## Constraints that limit your fun

- Premium gate must be unlockable via the `paywallSheet(isPresented:)` modifier — keep that hook.
- All copy is plain text in views — no localization budget yet, so write copy that holds up but assume English-only.
- Surprise / "secret from partner" toggle on reminders must remain visible — don't bury it.
- The pink/love-language tint system is intentional (`LoveLanguage.tint`) — don't repaint it, but you may propose a softer set of hues if you justify it.

## Success criteria, ranked

1. A TestFlight tester sends an unprompted screenshot to a friend.
2. The "I just want to unpair" user can find Settings without help (today they can't — Settings doesn't exist).
3. The premium gate screens convert >2× the current rate (we'll measure).
4. Daily Check-In has higher day-2 retention than reminders alone.

If you can only deliver one of the three jobs, deliver Job 1.
