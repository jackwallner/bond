# Prompt for Claude Design

Paste everything below into Claude Design after uploading the handoff folder.

---

You're designing for **Bond**, an iOS app for couples. Read `README.md` for product context, `source/Features/` for current screen structure, and `current/` for the existing design system. Reference `icon-style-reference.png` for the icon direction.

I want a tightly scoped output. **Do not** redesign screens, propose marketing visuals, or write a brand strategy doc. Stick to the two deliverables below.

## Deliverable 1 — App Icon

Generate **3-5 app icon concepts** at 1024×1024 PNG, in the style of `icon-style-reference.png` (soft 3D-rendered, friendly, slightly tactile, the Imagen-2-style iOS icon look — think the icons in that reference grid).

Constraints:
- Must read clearly at 60×60 (home-screen size). Test by mentally squinting.
- App is about *two people connected* — visual metaphors that work: linked rings, two hands, a tied knot, two hearts overlapping, a thread between two points, two birds, a shared moon, etc. Avoid: chat bubbles (this is not a messaging app), generic hearts (too cliché alone), calendar/checklist imagery (it's not a to-do app).
- Warm palette (terracotta, blush, cream, soft golds) — the current accent is a warm coral/pink. Feel free to propose a refined palette as part of this.
- Output: PNG files + one short paragraph per concept explaining the metaphor and why it works for couples specifically.

## Deliverable 2 — Visual System

**Stage A (lightweight — do this first, then stop and let me pick):**

Propose **2-3 directions** for the in-app visual system. Each direction = 1 paragraph (mood, type pairing, palette logic, surface treatment) + **1 sample PNG** showing the same component (a Reminder card with title, sender avatar, "Handled" button) rendered in that direction. That's it — don't build out the full system yet.

Directions should be *meaningfully different* (e.g. "editorial / serif-led / paper textures" vs. "modern minimal / sans / lots of whitespace" vs. "soft maximalist / rounded / gradient accents") — not three flavors of the same idea.

The in-app aesthetic should *feel coherent* with the 3D icon style (warm, soft, tactile, friendly) without literally being 3D.

**Stage B (only after I pick a direction):**

For the picked direction, produce:

1. **Design tokens as Swift code** — drop-in replacements/extensions for `current/BondStyle.swift` and `current/BondTheme.swift`. Include:
   - Color palette (semantic names: `bondAccent`, `bondSurface`, `bondSurfaceElevated`, `bondCardFill`, `bondHairline`, plus any new semantic colors you introduce) with light + dark variants as RGB tuples.
   - Type scale (Swift `Font` extensions — e.g. `Font.bondTitle`, `Font.bondBody`, etc.) noting the SF/system font weights or any custom font.
   - Spacing + radius scale (extending existing `BondSpacing` / `BondRadius` enums if your scale differs).
2. **4-6 component PNGs** at iPhone 15 Pro width (393pt @ 3x) showing:
   - Reminder card (title, sender, timestamp, Handled button)
   - Empty state (illustration + headline + body + CTA)
   - Primary button + secondary button + destructive button (states: rest, pressed, disabled)
   - Text field + selected chip group
   - Daily check-in "sealed" card (the locked/before-reveal state)
   - Settings row (label + value + chevron)
3. **Rationale doc** (1-2 pages max) — for each token group, one sentence on *why*. Especially: what makes this system feel "Bond" specifically, so I can extend it to new screens without you.

## Format of your reply

Organize as:
```
/icon/
  concept-01.png
  concept-02.png
  ...
  concept-notes.md
/visual-system/
  stage-a/
    direction-01-sample.png
    direction-02-sample.png
    direction-03-sample.png
    directions.md
  (stop here, wait for me to pick)
```

Then after I pick:
```
/visual-system/stage-b/
  tokens/
    BondTheme.swift
    BondStyle.swift
  components/
    *.png
  rationale.md
```
