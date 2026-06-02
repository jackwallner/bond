# Bond — Project Guide

See memory `project_bond.md` for app overview, stack, and phased plan.

## Scripts

- `scripts/testflight.sh` — push to TestFlight / ship a build
- `scripts/upload-testflight.sh` — upload existing binary (.ipa) to App Store Connect
- `scripts/pull-appstore-metadata.sh` — snapshots `fastlane/metadata/` to `metadata.bak.<timestamp>/`, then runs `fastlane deliver download_metadata`. ALWAYS run before editing `fastlane/metadata/*.txt` so ASC web-UI edits aren't clobbered. After pulling, diff against the snapshot to confirm what changed remotely.
- `scripts/upload-appstore-metadata.sh` — `fastlane upload_metadata` (screenshots + listing copy, no binary, no submit-for-review).

ASC API key (shared across apps): `~/.baseball_credentials` (`ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).

## Marketing site

- Pages: `docs/index.html`, `privacy-policy.html`, `terms.html`, `support.html` (+ `privacy/`, `terms/`, `support/` index routes for clean URLs)
- Production host: `https://jackwallner.com/bond/` via portfolio repo — run `./scripts/sync-site-to-portfolio.sh` then push `~/portfolio` `main`

**Review prompt:** See `docs/review-prompt.md` (5-star funnel; set `BondAppStoreID` in Info.plist before App Store launch).
