# 02 — Preference Choice (Just me / With someone)

**Current source:** `code-references/PreferenceChoiceView.swift`
**Priority:** P0 — branching decision
**Status today:** Two `Button` cards stacked vertically with `.regularMaterial` background. Functional, generic.

## Job
This is the first product decision the user makes. It sets the entire experience. Make it feel like a meaningful fork, not a settings choice.

## Options
- **Just me** — solo. Sets `solo = true` on the couple row, skips pairing.
- **With someone** — opens Pairing screen.

## Constraints
- Both options must remain top-level (no "advanced") because some users genuinely want solo.
- Tapping either is one tap to commit. No confirmation modal.
- After commit:
  - Solo → home tabs (we land directly on Reminders empty state)
  - With someone → Pairing screen

## Open questions to design around
1. Should there be a "you can change this later" affordance? (Today: no — there's no way to switch modes. We'd want that to live in Settings.)
2. Is the hero icon necessary here, or does the choice itself carry the screen?
3. Copy: "How will you use Bond?" — boring. Alternatives encouraged.

## Don't
- Don't gate "With someone" behind any premium pitch — pairing is core free.
- Don't auto-advance if they pause too long.
- Don't show the partner-flow as "the default."
