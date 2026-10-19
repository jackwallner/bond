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
- Run directly on jmbp with JDK21 at `~/.jdk/jdk-21.0.12.1+1/Contents/Home`.
  Never run Android on the Air or dispatch from this fleet host.
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

Data safety preparation: do not copy an offline app's three-type form. Supabase
collects the automatic anonymous account ID, display name, reminders, completion
and reaction events, open-ended check-in answers and milestones. Existing iPhone
arrival reminders can be edited on Android; Codec.reminderJson sends their saved
geofence coordinates on upsert. Disclose that optional saved-place collection
even though Android requests no device-location permission. The policy already
explains this distinction. Keep account deletion and its public anchor available.
Google defines accounts and deletion at
https://support.google.com/googleplay/android-developer/answer/13327111
and collected data, optionality and user-directed transfers at
https://support.google.com/googleplay/android-developer/answer/10787469.
Confirm the current Console account-creation choices against the automatic
anonymous profile before saving the form. No declaration has been saved yet.

Play app created in E3 Apps on2026-10-18:4974262124670141532,
package com.jackwallner.bond, title Little Gestures: Couples Care, App/Free,
English US. Package availability verified. Default automatic protection stays
on. No artifact uploaded, products or Console declarations saved yet. No new
legal agreement, service account or grant. Current source remains WIP pending
Pro build/runtime acceptance; privacy/deletion page publication is pending main.

Console initial declarations saved: no ads, no government affiliation and no
advertising ID. Source has no AD_ID permission or identifier-collection call;
recheck the merged release manifest in the pending build. Financial-features
form saved with no financial features. No production review submitted.

Full two-step no-health-features declaration is saved. Audience form requires
Sign in details first. Reviewer details, adult audience and cloud-aware Data
safety are pending current build/device verification. Android privacy URL must
be published and verified after accepted main push. Do not claim setup complete.

Play category is saved as App, Lifestyle. No matchmaking/dating or health
category is used for this couple-reminder routine app.

Play price conversion preserves the configured US money value explicitly.
Google conversion can choose a different nearby US price point, so use its
conversion for other regions and keep the requested US ladder unchanged.
The offline product plan still passes; no Play product was changed here.

Full Pro build packaged release/QA and passed137JVM cases, then failed release
lint on three NonObservableLocale errors. Date/time chips and weekly labels now
read LocalLocale.current.platformLocale as recommended by Compose lint, so they
update with the configured locale. No lint suppression. Current fix remains WIP
until the new build/lint/runtime checks pass.178Play countries are saved.

Existing internal tester list saved. New locale-fix build uses
bond-locale-final-build.log; initial19m8s lint failure is preserved separately.
Run release lint early when changing Compose UI, before expensive R8 packaging.
No current artifact is accepted or uploaded until all new checks pass.

Sign in details for the upcoming artifact are saved. The saved private-code
SHA-256 matches the ignored build configuration. Instructions describe free
onboarding, long-press Settings Version, no-purchase/no-expiry unlock and optional
pairing with a second installation. Code unchanged, no secret captured. Current
new runtime checks still gate upload.178countries and tester list are saved.
