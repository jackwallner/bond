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

## Simulator — dedicated, headless (required)

This project owns the simulator device `agent-bond`. Multiple agents work in
parallel on this machine: NEVER build/test against a shared named destination
(e.g. `name=iPhone 17 Pro`) and NEVER open Simulator.app — it steals Jack's
mouse/keyboard. Everything runs headless. Full guide: `~/docs/ios-agent-simulators.md`

```bash
UDID=$(agent-sim boot bond)        # create if needed + boot headless; prints UDID
xcodebuild -project Bond.xcodeproj -scheme Bond -destination "id=$UDID" build
xcodebuild test -project Bond.xcodeproj -scheme Bond -destination "id=$UDID"
APP=$(find ~/Library/Developer/Xcode/DerivedData/Bond-*/Build/Products -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
xcrun simctl install "$UDID" "$APP" && xcrun simctl launch "$UDID" "$(defaults read "$APP/Info" CFBundleIdentifier)"
axe describe-ui --udid "$UDID"        # inspect UI via accessibility tree
axe tap --label "Continue" --udid "$UDID"   # interact without mouse/keyboard
agent-sim screenshot bond          # PNG at /tmp/agent-bond.png
agent-sim shutdown bond            # free resources when done
```

## TestFlight on every update

After finishing a change and pushing to git, ALWAYS upload a new TestFlight build by
running `./scripts/testflight.sh` — do this unprompted on every push that changes app
code. Jack tests every update on his device and shouldn't have to ask.
