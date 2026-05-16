# Bond — Design Handoff for Claude Design

You are designing screens for **Bond**, a SwiftUI iOS app for couples who want to send each other small love-language reminders. This folder is self-contained: everything you need to produce designs lives here.

## How to use this folder

1. Read `BRIEF.md` — what we're trying to accomplish.
2. Read `PRODUCT.md` — what the app does and who it's for.
3. Read `BRAND.md` — visual tokens (colors, type, motion, copy voice).
4. Read `INVENTORY.md` — every screen that exists today, with a one-line summary and the source file.
5. Pick from `screens-to-design/` — each file is one screen brief with goals, constraints, and current state.
6. Cross-reference `code-references/` for the actual SwiftUI source of the surrounding views — match component vocabulary and surfaces.
7. Produce deliverables per `DELIVERABLES.md` — what to send back and in what format.

## What's already designed

The app currently leans on **stock SwiftUI components** (`Form`, `List`, `ContentUnavailableView`, `Picker(.segmented)`, etc.) styled with system colors plus a single accent (`.pink`). Premium features get a consistent gate pattern: large SF Symbol, headline, subtitle, "Unlock Premium" prominent button. Reminder rows show a love-language symbol + tint per language.

We are **not** rebranding. We need design pass on:
- Onboarding & empty states (currently default)
- Premium paywall surface (currently RevenueCat default UI — leaves money on the table)
- Home / tab transitions
- Settings (does not exist yet — see brief)
- Daily Check-In reveal moment (currently a vertical Form)
- Stats / Insights presentation
- App Icon variants and the launch screen
- Notification body copy + (optional) rich notification UI

## Constraints (non-negotiable)

- **SwiftUI on iOS 18+, watchOS 11+, no UIKit.** All output must be expressible as native components or system-symbol illustrations.
- **No custom font files.** SF Pro only. Use the system text styles (`.largeTitle`, `.title2`, etc.).
- **SF Symbols only for iconography.** No raster or vector imports except App Icon + launch art.
- **Color palette is system + one accent.** Add tokens, do not add hues. Dark mode must work for everything.
- **No motion that conflicts with `Reduce Motion`.** Reasonable defaults; use `.transition` and `.animation` primitives we already use.
- **Privacy-first copy.** No tracking language, no "your data" cuteness, no emoji-laden marketing tone in product UI.

## Open questions to ask the user (Jack) if needed

- Is the MVP audience TestFlight friends/family or App Store launch? Changes how polished the design needs to feel.
- Do we want a marketing screen at first launch, or jump straight to sign-in?
- Should the Daily Check-In reveal be a "scratch-off" / hidden-until-both-answer moment, or always-visible?
