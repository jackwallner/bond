# Bond — Project Guide

See memory `project_bond.md` for app overview, stack, and phased plan.
XcodeGen project/scheme: `Bond`, simulator device `agent-bond`.

## Marketing site

- Pages: `docs/index.html`, `privacy-policy.html`, `terms.html`, `support.html` (+ `privacy/`, `terms/`, `support/` index routes for clean URLs).
- Host: `https://jackwallner.github.io/bond/` — served by this repo's own GitHub Pages (main branch, `/docs`); push `main` to publish. (GitHub Pages hosting pattern is documented in the `ios-dev` skill.)

## Review prompt

See `docs/review-prompt.md` (5-star funnel). Set `BondAppStoreID` in Info.plist before App Store launch.

---
Shared iOS conventions (build, simulator, release scripts, ASC key, signing, gotchas):
always-loaded global CLAUDE.md + the `ios-dev` skill.
