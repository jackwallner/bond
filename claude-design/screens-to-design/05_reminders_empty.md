# 05 — Reminders Empty State (first run)

**Current source:** `code-references/ReminderListView.swift` (the `ContentUnavailableView` block)
**Priority:** P1
**Status today:**
```
        ❤
   No reminders yet
Tap + to add your first reminder
   for your partner or yourself.
```

## Job
The first thing every paired user sees after the success interstitial. Convert "huh, what do I do" into "oh, let me try this one."

## What we'd like to add
- Two-to-four "Start here" example chips:
  - "Tell them they're beautiful" (Words)
  - "Bring home flowers" (Gifts)
  - "10-min walk together" (Time)
  - "Surprise hug" (Touch)
- Tapping a chip opens the editor pre-filled with that title + love-language.
- A subtle "Browse templates →" link below the chips for users who want a kit.

## Constraints
- The toolbar still has the existing `square.grid.2x2` (templates) and `+` buttons — design must coexist with them.
- The chips must not show on subsequent visits (only when `repo.reminders.isEmpty`).
- If filter is "For Me" but `repo.reminders` has rows targeted to partner, we need a *different* empty state (see 05b).

## 05b — Filtered empty state
A user with reminders, but the "For Me" filter is empty.
Suggested copy: *"Nothing for you right now. Your partner's the lucky one."* (open to alternatives)
A "Switch to All" button.

## Don't
- Don't recommend a specific person's name in the example chips ("Tell Sarah she's...").
- Don't show 8 chips. Four max — paralysis hurts here.
