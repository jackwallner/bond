# 04 — Pairing Success (new screen)

**Current source:** doesn't exist — today's flow goes straight from `PairingView` → `HomeTabs` once `pairing.coupleId` flips non-nil.
**Priority:** P1 — easy win
**Status today:** No celebration moment. The transition is a SwiftUI `.opacity` cross-fade.

## Job
The two halves just connected for the first time. This is the only moment they'll ever have it. Give it 1.5 seconds of weight before dropping them into the tab bar.

## Suggested structure
- Both names (or "You + [Partner Display Name]")
- An understated visual that signals connection (two hearts, two rings, a knot — no glitter)
- Auto-dismiss after ~1.8s into `HomeTabs`, OR a single "Get started" button if you'd rather make it explicit.

## Constraints
- Must use the `partnerProfile.displayName` if available (Supabase `profiles.display_name`). Fall back gracefully if nil — Apple SIWA often returns nil for `fullName` after the first sign-in attempt.
- If only one name available, show "You're paired with someone." (intentionally warm-vague)
- Must respect Reduce Motion: in that mode, no auto-dismiss; show a button instead.

## Don't
- Confetti. Sparkles. Particle effects.
- A "Send your first reminder!" CTA — that pressure belongs to the next screen, not this moment.
- A tour.
