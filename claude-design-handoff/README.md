# Bond — Claude Design Handoff

## What this app is
Bond is an iOS app for couples in long-distance / committed relationships. Two people pair their accounts and use the app to:

- **Send reminders to each other** ("pick up the dry cleaning", "grateful you called your mom") — the partner gets a push, marks it "Handled."
- **Daily check-in** — one shared prompt per day; both partners answer, then both reveal at once.
- **Milestones** — shared dates that matter (anniversaries, trips, things you're looking forward to).
- **Templates** — quick-pick reminder phrases for love-language flavors (acts of service, words of affirmation, etc.).
- **Apple Watch companion** — dictate a reminder from the wrist.

The user is the *sender*, not a productivity nerd. Tone is warm, intimate, low-stakes — closer to a love letter than a to-do app. Not childish, not corporate.

## What's in this folder
- `current/` — current design system (`BondTheme.swift`, `BondStyle.swift`, `BondComponents.swift`), accent color JSON, and current `AppIcon.png` so you can see what we're starting from.
- `source/Features/` — every feature's SwiftUI views, so you can see screen structure and existing component usage. Read these to understand visual density, common patterns (cards, chips, sheets), and where the design system is and isn't applied consistently.
- `icon-style-reference.png` — visual reference for the icon style we want (soft 3D-rendered, Imagen-2-style iOS icons).

## What we want back
See `PROMPT.md` for the full brief. TL;DR:

1. **App icon** — 3-5 concepts at 1024×1024 PNG in the reference style.
2. **Visual system** — 2-3 *lightly-sketched* directions (1 paragraph each + 1 sample component PNG per direction) so we can pick one before you go deep. Then for the picked one: full token set as Swift code + 4-6 component PNGs.
3. **Written rationale** — short notes explaining the picks so we can extend the system to new screens later.

## What we do NOT want
- Full screen redesigns (out of scope).
- Heavy proposals across all 3 directions — keep exploration lightweight; we pick first, then you build out.
- Generic mood boards / brand personality decks.
- Marketing site, onboarding flow rework, etc.
