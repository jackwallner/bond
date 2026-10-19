---
paths:
  - android/**
---

# Android port (`android/`)

Native Kotlin + Jetpack Compose port of the iOS app, screen for screen. Package
`com.jackwallner.bond`, display name "Little Gestures", minSdk 26, target/compile
36. Built 2026-10-18 from the sheepshead template (Gradle, billing, scripts,
`MainActivity`, debug options, reviewer dialog) with sober's AlarmManager
notification scheduler.

## Build
- JDK 17: `export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`
- `./gradlew testDebugUnitTest assembleDebug assembleDebugAndroidTest assembleRelease bundleRelease assembleQa`
- `android/local.properties` (gitignored) holds `REVENUECAT_PLAY_KEY` (goog_),
  `REVENUECAT_TEST_KEY` (Test Store), `PLAY_UPLOAD_*` and
  `PLAY_REVIEW_CODE_SHA256`. `validateReleaseConfiguration` fails a release
  build that is missing any of them.
- Debug builds use the Test Store key; only release gets the goog_ key. Never
  put the production key in a test run. `qa` is a release build with debug
  signing and no RevenueCat key (`src/release/java` sources).
- Upload key: `~/.android/keystores/bond-upload.p12` (backup in
  `~/.android/keystores/backups/`), password in `~/.bond_credentials`.
- Bump `versionCode` in `app/build.gradle.kts` for every Play upload;
  `versionName` tracks the iOS marketing version.

## Backend and billing
- Same Supabase project and RLS contract as iOS, using the public anon key iOS
  ships (`SUPABASE_ANON_KEY` buildConfigField). Never add a service-role key.
  `data/SupabaseClient.kt` is a small PostgREST/GoTrue client (no SDK).
- RevenueCat project `proj4e53c2c5`, Play app `app27f458ac14`; products
  `com.jackwallner.bond.plus.monthly:monthly`, `.yearly:yearly`,
  `.plus.lifetime`; entitlement `Husband & Wife Reminder - Bond Pro`; offering
  `default`. The Test Store products have no trial and different prices from
  iOS, so the debug trial page always shows the no-trial variant.

## Debug launch extras (debug builds only)
`adb shell am start -n com.jackwallner.bond/.MainActivity --ez uiTest true
--ez screenshotSeed true [--ez seedFree true] [--ez forcePro true]
--es appearance light|dark|system --es tab REMINDERS|CHECK_IN|MILESTONES|INSIGHTS|SETTINGS`.
The seed is the iOS screenshot seed (Sam, three reminders, three milestones, a
check-in) and never touches the network. Test tags double as resource ids.

## Tests
- Unit (`app/src/test`): `IosParityTests.kt` mirrors BondTests; `PortTests.kt`
  pins Android-only logic, including check-in question and surprise-time
  fixtures computed from Swift so both platforms pick the same row and minute;
  `SupabaseClientTests.kt` checks the wire contract against a fake transport.
- Connected (`app/src/androidTest/AppFlowTest.kt`): seeded UI flows, a real
  first run that creates a solo couple and deletes the account, and a live
  two-install pairing test. Both live tests delete every identity they create.
- Run on the MacBook Pro only, on a temporary AVD, one method per
  `am instrument -e class com.jackwallner.bond.AppFlowTest#<method>` after
  `pm clear`. Grant `POST_NOTIFICATIONS` except for the first-run test, which
  covers the primer. The Pro is a dual-core Intel; with another emulator up,
  give the AVD 4 cores and 4 GB and wait for Play Services to finish its
  post-boot dexopt or every test dies at process start.
- Any fresh install signs in anonymously, so manual runs against the live
  project leave an anonymous user behind: delete it with `delete_account`
  using the session in `shared_prefs/bond.xml`.

## Deliberate differences from iOS
- Identity: anonymous only. No Sign in with Apple, and no Google sign-in.
- No realtime: couple, reminders and events refresh on resume and pull to
  refresh.
- Place (arrival) reminders are not offered for new reminders; an existing one
  made on iPhone stays editable and shows "Arrival alerts fire on iPhone."
  Editor footer and milestone copy drop the Location and widget mentions.
- Notifications are local AlarmManager alarms (`data/Notifications.kt`),
  re-armed on boot, package replace and time or zone change. Milestone pings
  copy the iOS 9 elapsed hours after midnight, so a DST day fires at 8:00 or
  10:00 exactly like iOS.
- The trial page says "free trial" only when Play reports intro eligibility
  (one trial per Google account).
- Play-specific: reviewer code dialog on a long press of the version line,
  "Rate on Google Play", Google Play wording in disclosures and Delete
  account, app data excluded from backup.

## Not ported
watchOS app, widgets, APNs remote push (partner actions arrive on the next
refresh), Sign in with Apple, location triggers. `https://jackwallner.com/pair/`
links need `assetlinks.json` with the Play app signing SHA-256 before they
verify; `bond://pair/` works now.

## Left for the Play Console session
Create the app and the three products with prices and the 1-week trials to
match iOS, upload the AAB to internal testing, add the Play app signing
SHA-256 to `assetlinks.json`, data safety form, and the RevenueCat service
credentials for the Play app.

RevenueCat integration check on2026-10-18: developer notifications plus two
transaction webhooks, with the same previously verified destination domains as
VO2 Max. Both disable paywall-event forwarding; no advertising integration is
listed. No credentials, grants or integration settings were changed. Data safety
must still disclose actual app-side collection, including purchase history and
anonymous identifiers, plus custom purchase-screen attributes where used.
RevenueCat's general guide is https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-plays-data-safety.

Pro queue validation: the masked reviewer field has a dedicated actual-dialog
case. It runs in free screenshot-seed mode, creates no backend identity, rejects
a wrong code and checks the private grant across refresh and reconstruction.
Build/device execution is pending after Sheepshead. Unaccepted changes stay on
wip/android-port. Existing BOND_PLAY_REVIEW_CODE is unchanged and private.
