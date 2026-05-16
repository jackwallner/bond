# Capturing current screenshots (optional)

If you want to see what the app actually looks like before redesigning, run the build and take screenshots in the iOS Simulator.

## One-time setup
```sh
xcodegen generate
xcodebuild -project Bond.xcodeproj -scheme Bond \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Run on simulator
```sh
xcrun simctl boot 'iPhone 17'
open -a Simulator
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Bond-*/Build/Products/Debug-iphonesimulator/Bond.app
xcrun simctl launch booted com.jackwallner.bond
```

## Capture each screen
```sh
mkdir -p claude-design/screenshots
xcrun simctl io booted screenshot claude-design/screenshots/01_onboarding.png
# tap through each tab and re-run as needed
```

## What you won't be able to capture without backend
- Pairing (needs a Supabase couple row — you can see the empty Pairing form, not the success state)
- Daily Check-In with two responses (needs the partner having answered)
- Stats with real data (needs reminders + events)

For those, treat the screen briefs as the source of truth and design from the spec rather than the screenshot.

## A note on the screenshots folder
This folder is empty in the handoff. We're not pre-capturing for you — the build is fast and screenshots taken at your end will be more current than anything we ship in the folder.
