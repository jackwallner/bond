# Bond

Couples' love-language reminder app for iOS + Apple Watch.

## Stack
- Swift 6, iOS 18, watchOS 11
- XcodeGen for the project (`project.yml`)
- Supabase backend (Postgres + Auth + Edge Functions) — wiring deferred
- Three targets: `Bond` (iOS), `BondWatch` (watchOS), `BondWidgets` (WidgetKit)

## Generate the Xcode project

```sh
xcodegen generate
open Bond.xcodeproj
```

## Build from CLI

```sh
xcodebuild -project Bond.xcodeproj -scheme Bond \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Phase 1 status (current)

Done:
- XcodeGen scaffold, 3 targets, entitlements, asset catalogs
- Shared models: `LoveLanguage`, `ReminderTrigger`, DTOs for Profile / Couple / Reminder
- Sign in with Apple (`AppleSignInHelper`) → `SupabaseService`
- Pairing flow: generate invite code → universal link → `consume_invite_code` RPC
- Supabase migration `supabase/migrations/0001_init.sql` (schema + RLS + helper RPCs)
- Widget stub (UpcomingReminderWidget)
- Watch app stub

Not yet wired:
- Supabase project (skipped at user request — see "Backend setup" below)
- Reminder list / editor (Phase 2)
- APNs Edge Function (Phase 2)
- Watch dictation + complication (Phase 3)
- StoreKit + premium gates (Phase 4)
- AI features (Phase 5)

## Backend setup (when ready)

1. Create a Supabase project (free tier is fine).
2. Apply the migration:
   ```sh
   supabase db push           # via CLI, after linking the project
   # OR copy supabase/migrations/0001_init.sql into the SQL editor
   ```
3. In **Authentication → Providers**, enable **Apple** and set the bundle ID `com.jackwallner.bond`.
4. Inject credentials into the iOS build. Add to `Bond/Info.plist` (use Xcode build settings / xcconfig in real life — don't commit secrets):
   ```xml
   <key>SUPABASE_URL</key>
   <string>https://<ref>.supabase.co</string>
   <key>SUPABASE_ANON_KEY</key>
   <string>eyJ...</string>
   ```
5. Universal links use `jackwallner.com` (the portfolio site). The AASA file is hosted at `https://jackwallner.com/.well-known/apple-app-site-association` (committed in the portfolio repo under `docs/.well-known/`).

## APNs (Phase 2)

Requires a **paid** Apple Developer Program account. When ready:
- Create an APNs Auth Key in Apple Developer portal.
- Store key + Team ID + Key ID as Supabase secrets.
- Deploy `SupabaseFunctions/send-push` and attach a Postgres webhook on `reminders` insert/update.

## Directory layout

```
Bond/             # iOS app
  BondApp.swift
  Features/
    Onboarding/   # Sign in with Apple
    Pairing/      # Invite code + universal link
  Services/
    SupabaseService.swift
    SupabaseConfig.swift
    AppleSignInHelper.swift
    PairingService.swift
BondWatch/        # watchOS app stub
BondWidgets/      # WidgetKit extension
Shared/           # Compiled into every target
  Models/         # LoveLanguage, ReminderTrigger
  DTOs/           # Codable shapes for Supabase tables
  Utilities/      # AppGroup
SupabaseFunctions/
  send-push/      # Phase 2 — APNs sender
  ai-suggest/     # Phase 5 — Claude proxy
supabase/
  migrations/0001_init.sql
```
