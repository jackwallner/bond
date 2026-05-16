# 09 — Paywall Layout Spec (RevenueCat remote config)

**Current source:** `code-references/PaywallView.swift` (wraps `RevenueCatUI.PaywallView`)
**Priority:** P0 (revenue)
**Status today:** RevenueCat's default templated paywall. Bland.

## Job
A paywall configured remotely via RevenueCat Dashboard. We don't write custom paywall SwiftUI — RevenueCat lets us pick a template + supply images, headlines, bullet copy, and footer links. **You design the inputs to that template**, not the SwiftUI.

## Deliverable
A single markdown spec describing the paywall:
- Recommended template family (RevenueCat offers: "default", "minimalist", "list", "feature-list", "image-only" — pick one and justify)
- Hero image direction (we can use SF Symbols composed into one image, or a single rendered image we add as an asset — keep it minimal)
- Headline (max ~6 words)
- Subhead (max ~12 words)
- Feature bullets (4 bullets max, with SF Symbol per bullet)
- Trial messaging
- Pricing display ($X.XX/mo with strike-through annual savings if both products exist)
- Restore Purchases placement
- T&C / Privacy footer

## Constraints
- Two product offerings will be live: monthly + annual (assume 40% savings on annual).
- 7-day free trial on both.
- App Store guidelines require visible "Restore Purchases" and accessible T&C / Privacy links.
- No urgency/scarcity copy ("Limited time!"). Apple frowns on it; we frown on it more.

## Tone reminder
We are not selling a "couples app subscription." We're selling a quiet tool that helps two people stay tuned to each other. Lean *under*-promise.

## Don't
- Don't propose seasonal variants for MVP.
- Don't recommend localized variants — English only for now.
- Don't propose a "lifetime" tier — we want recurring revenue.
