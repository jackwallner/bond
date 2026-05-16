# 08 — Premium Gate Pattern (redesign)

**Current source:** `code-references/PremiumGateView.swift` and the four feature views (`MilestonesView`, `StatsView`, `DailyCheckInView`, `ReminderTemplatesView`).
**Priority:** P0 (revenue surface — every customer sees this)
**Status today:** Identical SF Symbol + headline + subtitle + "Unlock Premium" button on every locked feature. Functional. Forgettable.

## Job
Replace the gate-takeover with a **partially-blurred preview**: the user can see *what they'd get* but can't interact with it. The CTA lives in a clean affordance at the bottom — sticky, not modal.

## Pattern spec (per-feature)
```
┌─────────────────────────────┐
│  [navigation bar — title]   │
├─────────────────────────────┤
│                             │
│  [Feature preview — soft    │
│   blurred, non-interactive, │
│   real data if available]   │
│                             │
│                             │
│                             │
│                             │
│                             │
├─────────────────────────────┤
│  Premium • $X.XX/mo · trial │
│  [    Unlock Premium    ]   │
└─────────────────────────────┘
```

The preview is the actual feature view, rendered with synthetic / blurred data and `.allowsHitTesting(false)`. A subtle gradient fades the top half into view from below the nav bar.

## Per-feature preview content (deliver each)

### Milestones gate
Preview: 3 fake milestone rows with countdown chips. Names like "Our anniversary", "Sarah's birthday", "Move-in day."

### Insights gate
Preview: balance score circle + the bar chart from `StatsView`, populated with sample data showing a slight imbalance. Insights list shows 1 example: "Quality Time is your least expressed love language."

### Daily Check-In gate
Preview: the question card with sample question ("What is one thing you appreciated about your partner today?"), plus a "Sarah answered" hint that the user can't read.

### Templates gate
Preview: 3 of the 6 template group cards visible (Daily Affirmations, Date Night, Long Distance) with the "Add N reminders" CTA visible but disabled.

## Constraints
- The CTA bar must remain accessible (not hidden by the home-indicator) — use `.safeAreaInset(edge: .bottom)`.
- Pricing string comes from RevenueCat — don't hardcode. Format: `"7-day trial · then $X.XX/mo"` or similar.
- "Restore Purchases" small text link below the primary CTA.
- Must work in dark mode (blur looks different).
- The previewed content must NOT be real partner data — use SAMPLE labeled content only.

## Don't
- Don't redirect to a full takeover paywall. The RevenueCat paywall opens via the existing `.paywallSheet(isPresented:)` modifier.
- Don't gamify or guilt-trip ("Your relationship deserves...").
- Don't show "Premium" with a crown icon.
