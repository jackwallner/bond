# Background context for Claude Design

This file gives you everything I (the implementing engineer) know about Bond that doesn't fit neatly into BRIEF or PRODUCT. Skim it before you start.

## The team
- Jack Wallner — solo developer + designer. iOS engineer by day, building Bond on the side.
- No design team. You are the design team.
- Implementation is being done by another Claude instance reading your output as source of truth.

## Where the code is
Project root: `/Users/jackwallner/bond`
- `Bond/` — iOS app
- `BondWatch/` — watch companion (out of scope for design pass)
- `BondWidgets/` — widget extension
- `Shared/` — DTOs and models compiled into every target
- `supabase/migrations/` — Postgres schema
- `claude-design/` — this folder

The relevant code is mirrored in `code-references/` at handoff time. If a file looks out of date, ask.

## Where Bond sits today (snapshot 2026-05-15)
- 56 unit tests passing
- 0 build warnings on a clean build (after a small dead-code cleanup we're doing)
- 6 weeks pre-TestFlight
- `MVP_TRIAGE.md` in `docs/` outlines 12 P0/P1 bugs that will be fixed in parallel with your design work — they should not affect your scope

## Constraints worth re-stating
- **SwiftUI primitives only.** No `UIKit`. No `UIViewRepresentable` unless absolutely necessary.
- **SF Symbols only.** If you need an icon not in the library, you don't get the icon.
- **System fonts only.** SF Pro.
- **No third-party UI libs.** No Lottie, no SwiftUIX, no Pow.
- **iOS 18 minimum.** You can use everything in iOS 18 (e.g. `@Observable`, `.symbolEffect`, `.scrollTargetBehavior`).
- **Dark mode is mandatory.** Every screen.
- **Accessibility is mandatory.** VoiceOver labels, Dynamic Type to AX5, Reduce Motion fallbacks.

## What I won't do based on your designs
- Add custom fonts.
- Add raster image assets bigger than the App Icon set.
- Replace `Form` with hand-rolled `ScrollView`-of-`HStack`s unless you have a strong reason — `Form` is what users expect for settings/editors.
- Build motion that breaks the 60fps budget on iPhone 12.
- Implement screens that aren't in the priority list without asking first.

## How to send revisions
If after I implement your design you say "actually no, like this" — drop a revised file with the same name in `output/mockups/` and I'll regenerate. Keep filenames stable so git diffs are clean.

## A note on aesthetic taste
I want Bond to feel like a small, well-made object. Reference points I keep coming back to:
- **Things 3** — the discipline of restraint
- **Streaks (Crunchy Bagel)** — clean metric presentation, no gamification rot
- **Day One** — quiet reverence for the personal moment
- **Letterboxd's mobile app** — opinionated typography in a stock-feeling shell
- **AirMail / Letter.app of yore** — confidence in white space

Reference points I want to avoid:
- Calm/Headspace (too soft, too pastel-illustration)
- Couples app stock photo aesthetic
- Hinge/Tinder visual language
- Any "wellness journal" with watercolor backgrounds
- iOS Reminders default (functional but featureless)

When in doubt, choose the colder, more confident option. We earn warmth with copy, not with hearts.
