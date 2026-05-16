# What to send back

Output structure — drop each artifact into the corresponding folder when responding. Match these filenames so I can wire them into the code without renaming.

```
output/
├── mockups/
│   ├── 01_onboarding.{md|png|svg}      ← screen mockups (ASCII/markdown/figma-exported)
│   ├── 02_preference_choice.*
│   ├── 03_pairing_generate.*
│   ├── 03_pairing_accept.*
│   ├── 04_pairing_success.*
│   ├── 05_reminders_empty.*
│   ├── 06_settings.*
│   ├── 08_premium_gate.*               ← the new "preview, not wall" pattern
│   ├── 09_paywall_spec.*               ← spec for RevenueCat remote config
│   ├── 10_check_in_pre.*
│   ├── 10_check_in_waiting.*
│   ├── 10_check_in_reveal.*
│   └── 10_check_in_compared.*
├── tokens/
│   ├── COLORS.md                       ← Swift color extensions + token names
│   ├── SPACING.md                      ← if you propose a scale
│   └── COMPONENTS.md                   ← reusable view specs
├── copy/
│   ├── ONBOARDING.md                   ← every string in the first-60s flow
│   ├── PREMIUM_GATES.md                ← per-feature gate headline + subtitle + bullets
│   ├── EMPTY_STATES.md                 ← Reminders/Milestones/Insights/Templates/Check-In
│   ├── NOTIFICATIONS.md                ← reminder body templates per love language
│   └── ERRORS.md                       ← user-facing strings for known failure modes
├── motion/
│   └── CHECK_IN_REVEAL.md              ← step-by-step timing spec (duration, curve, transition)
├── icon/
│   ├── APP_ICON_BRIEF.md               ← if you propose new icon direction
│   └── (variants if you produce them)
└── HANDOFF_NOTES.md                    ← anything I should know that doesn't fit a folder
```

## Format requirements per file type

### Mockups
**Preferred:** Markdown with ASCII layout sketches + annotated rationale. Easy for me to read and translate into SwiftUI.
**Also accepted:** SVG, PNG, Figma frame exports. If raster, include a markdown sibling with the rationale.

Each mockup file must include:
- Screen title and which `code-references/*.swift` file it replaces or augments.
- Layout sketch (ASCII or visual).
- Component breakdown — name the SwiftUI primitives you'd compose from (e.g. "VStack > Image(systemName:) > Text(.title2.bold) > Button(.borderedProminent)").
- States it must support: loading, empty, error, populated, dark mode notes.
- Specific copy strings (not lorem).
- Accessibility notes: VoiceOver order, hint strings, Dynamic Type behavior.

### Tokens
SwiftUI-ready. For colors, write the actual `extension Color { static let bondAccent = ... }` block I can paste in. Do not invent hex values without dark-mode pairs.

### Copy
One screen per heading. Every string the user might see. Variations welcome (max 3 per slot) — flag which is your recommendation.

### Motion
Step list with timing and curve names matching SwiftUI's `Animation` API: `.easeOut(duration:)`, `.spring(response:dampingFraction:)`, `.linear(duration:)`. Reduce-motion fallback specified.

## What NOT to send
- Pricing recommendations (out of scope; RevenueCat handles).
- Marketing landing-page mockups.
- App Store screenshots (different job).
- Mascots, illustration sets, or anything that needs a custom asset pipeline.
- Anything that requires UIKit, Lottie, or third-party UI dependencies.

## How I'll use it
Each mockup turns into a feature branch:
```
git checkout -b design/01-onboarding
# I implement the mockup in SwiftUI, matching component vocabulary
# Commit per screen, test, push, TestFlight
```
If something in your spec can't be expressed in stock SwiftUI on iOS 18, I'll come back with a question — don't pre-compromise. I'd rather hear your real vision and negotiate.
