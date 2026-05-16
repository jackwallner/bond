# 01 — Onboarding (Sign in with Apple)

**Current source:** `code-references/OnboardingView.swift`
**Priority:** P0 — first impression
**Status today:** Works, but the SIWA button is a transparent overlay (known bug — will be fixed in code). Visually: hero icon + "Bond" wordmark + tagline + SIWA button. Default.

## Job
Make the first screen feel like a small object you'd want to keep. Convey "this is a tool for two people who care about each other" without being saccharine.

## What must be on screen
- Sign in with Apple (the only sign-in method)
- App name "Bond"
- One-line value prop (current: "Small acts of love, on cue." — open to alternatives)
- No tab bar yet (full takeover)

## What we have
```
        ❤ (heart.text.square.fill, 72pt, pink gradient)

           Bond

      Small acts of love, on cue.



      [  Sign in with Apple  ]
```

## What we don't want
- Email/password fields. SIWA only.
- A scrolling "feature highlights" carousel.
- A "Sign in to continue" subtitle above the button.
- Animated hearts. Animated anything that isn't subtle.

## Constraints
- Button must be `SignInWithAppleButton(.signIn)` — Apple requires it.
- Must work in dark mode (button style auto-flips if we use `.black` today; consider `.whiteOutline` in dark).
- Must show inline error footer below button on failure (current pattern).
- Dynamic Type up to AX5.

## Questions to answer in your mockup
1. Should the tagline live above or below the wordmark? Try both.
2. Is the hero icon SF Symbol enough, or do we need an App-Icon-as-Image moment?
3. Where does the (currently nonexistent) Privacy / Terms link go? Below the button is conventional.
4. Do we want a tiny "What is Bond?" affordance for first-time users who don't recognize the name?
