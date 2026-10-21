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
- On jmbp/jmbp2 (fleet runs), from `android/`:
  `JAVA_HOME=~/jdks/temurin-17 ./gradlew testDebugUnitTest assembleDebug assembleDebugAndroidTest lintDebug assembleQa`.
  From the Air, `fm-gradle <tasks>` runs the same on jmbp and copies outputs back.
- Signed release stays on the Air (upload keystore never leaves it), JDK 17:
  `export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`,
  then `./gradlew assembleRelease bundleRelease`
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
- Connected tests on jmbp/jmbp2: lease an idle `agent-emu-1`/`agent-emu-2`, boot it
  headless on its own port, then run `connectedDebugAndroidTest` with
  `ANDROID_SERIAL` set. The orchestrator clears data per test and the seed
  suppresses the primer, so no manual `pm clear` or permission grant is needed.
  The reviewer case needs `reviewCode`: pass it through the environment
  (`ORG_GRADLE_PROJECT_android.testInstrumentationRunnerArguments.reviewCode`)
  from `~/.bond_credentials`, never on the command line.
- The emulator forces 1 vCPU on hosts with fewer than 6 logical cores (both
  Pros). Start it with `-memory 3584` (runtime flag, AVD config untouched) or
  the 2 GB guest swaps, and run `cmd package compile -m speed -f
  com.jackwallner.bond` after a debug install: an uncompiled debug build on a
  starved guest raises Input-dispatch ANRs whose main-thread stack is runnable
  Compose work, not a hang. If `/sdcard` reports "Transport endpoint is not
  connected", use `/data/local/tmp` for dumps and recordings.
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

Adult18+ target audience is saved after reviewer details. Data safety remains
pending the cloud-account/content/location declarations and public policy page.

Locale-fix rebuild has a fresh137JVM pass, zero failures/errors/skips.
Release packaging passed; current QA R8 and final lint/runtime gates remain.

Final staging readback: managed publishing off, no submission. App content
shows exactly3pending declarations: privacy policy, content ratings and Data
safety. Reviewer details/adult audience are saved, current runtime not accepted.

Corrected full Pro build and release lint pass15m51s,189tasks. Fresh137JVM pass,
zero failures/errors/skips. Current release APK/AAB and QA key/digest isolation
checks pass, no private reviewer code embedded. Artifact signatures/alignment
verification and owned-device runtime are next. Source remains WIP until those
runtime/capture gates pass, no AAB uploaded or main acceptance.

Current signed vc1/1.0.7 target36 APK/AAB signatures, APK ZIP/AAB config and
all4native ELF16KB alignments pass. Owned sol-bond5580 boots for the actual
reviewer case. No current runtime or capture acceptance yet.

Actual reviewer-access case passes60.135s on current debug build: masked field,
wrong-code rejection, valid unlock, customer-info refresh and reconstruction.
Initial process-start ANR was under99percent guest CPU pressure; precompiling
app/test packages and retrying warm resolved it. No source workaround or new
backend identity. Paid boundary, locale surfaces, captures and QA remain.

Current free paid-boundary/store-price case passes46.058s. The two seeded
locale-surface cases (date editor and tab/Insights coverage) run next because
those composables changed. All use Test Store/seed data, no backend identity.

Current seeded date-editor case passes32.805s and all-tabs/Insights case44.705s,
covering the changed locale reads. Four real free captures are being generated
with screenshotSeed and seedFree, no backend identity or paid unlock. QA remains.

Capture inspection found unconditional "Try Little Gestures+ free" labels in
Settings and feature gates, even when no trial is known to be available. These
entry points now say "Explore Little Gestures+". The paywall still uses live
eligibility for trial copy. Refresh Check-In/Insights captures after rebuilding;
old captures are archived outside the repo. Reminders/Milestones captures remain
valid. This copy fix is WIP and requires its new build and optimized QA gates.

## Current state, 2026-10-20 (fleet run shift-android-bond-2 on jmbp)

Source: `wip/android-port` f3c832c merged onto main 63d5ff3 (iOS alternate icons
kept; they are App Store PPO icons, nothing to port). The CTA copy change
(b234885, "Explore Little Gestures+") is now built and verified:
- `./gradlew testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest assembleQa`
  passes; 137 JVM tests, 0 failures; lint 0 errors (warnings only).
- `connectedDebugAndroidTest` on agent-emu-2 (API 36): 11/11 pass, including
  the live first-run/delete-account and two-install pairing cases (both delete
  their identities) and the masked reviewer-code case.
- Inspected captures: free Check-In/Insights/Settings/paywall (Test Store
  plans, no trial), Pro Check-In/Insights, dark Reminders. `play-assets/screenshots`
  now has all four 1080x1920 free captures.
- QA APK: no Test Store, goog_ or reviewer code in dex; debug extras ignored
  (seed, forcePro, tab, appearance); offline first run shows "Couldn't
  connect" with Try again and creates no backend identity.
- Interaction video of a real task (mark Sam's request Handled, scroll, tab
  through) recorded with screenrecord. Native cadence on the 1-vCPU
  swiftshader emulator is not representative (median frame 450 ms in
  gfxinfo); a real 60 fps cadence check needs the Air motion task
  (`fleet-record60.py`) or a physical device.

Remaining, in order: signed release APK/AAB on the Air (bump nothing, vc1
1.0.7 not yet uploaded), publish `docs/android/` privacy page via main, then in
Play Console: privacy policy URL, IARC content rating, Data safety (cloud
account, display name, reminders, events, check-in answers, milestones,
optional saved place, purchase history), listing text/art/four captures,
products via `scripts/play-products.py` (preserve US ladder), RevenueCat Play
credentials and package mappings, register the Play app with rc-clean,
internal track upload and opt-in, Play app signing SHA-256 in `assetlinks.json`,
production draft. No production review is sent; it waits for its pacing slot.

## Play staging, 2026-10-20

Staged one click from review, nothing sent. Listing, graphics, signed vc1 AAB
(drafts on internal and production), three products active, RevenueCat
credentials and every App content form except the IARC content rating are
saved. The permission classifier refused the IARC terms tick; Jack completes
the rating. Then Jack sends for review from
Publishing overview with managed publishing off.
