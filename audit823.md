# Bond audit823

Audit date: 2026-08-23

Audience: an implementation agent working on download growth, trial starts, conversion, user experience, release quality, and agent workspace hygiene.

Scope: repository-only audit of Bond at /Users/jackwallner/bond. I inspected the XcodeGen project, source, watch and widget targets, tests, StoreKit fixture, RevenueCat integration, paywall and onboarding code, review funnel, notification and pairing services, Supabase migrations and edge function, App Store metadata and upload scripts, landing site, legal and support pages, CI, CLAUDE.md/AGENTS.md/README.md, archive material, and Claude design handoffs.

Evidence standard:

- Evidence means a fact directly visible in the repository, with a path and line reference where practical.
- Inference means a likely product, conversion, operational, or review consequence of that evidence. It is not a live metric.
- Recommendation means work for the implementation agent. Recommendations are not claims that a production defect has been observed.
- No live App Store Connect, RevenueCat, crash, download, trial, rating, or revenue data was queried for this audit. The historical metric claim in commit 8760316 is labeled as historical and is not treated as current.
- Per the request, this audit intentionally omits inconsistencies about RevenueCat tracking or data-collection disclosure. It does cover RevenueCat purchase flow, attributes, events, offering configuration, and entitlement behavior.

## Executive decision summary

The highest-leverage work is to make the first paid decision trustworthy, make the advertised partner-reminder loop actually observable and reliable, then instrument the funnel so metadata and paywall experiments can be judged. The repository has strong visual direction, broad localized ASC copy, and thoughtful recovery UI in several places. It also has several states that can silently look successful while the underlying action failed.

| ID | Severity | Finding | Impact | Effort | Confidence |
|---|---|---|---|---|---|
| BOND-01 | P0 | Solo onboarding treats a RevenueCat purchase in the pending state as complete and calls finish | A user can reach home before Bond+ entitlement is active, with no pending recovery state | Small | High |
| BOND-02 | P0 | Partner-targeted reminders are excluded from local scheduling and APNs token registration is absent | The core promise of a reminder reaching the partner is not verified by the client path | Medium to large | High |
| BOND-03 | P0 | Prices and product set disagree between metadata, site JSON-LD, StoreKit fixture, and code | Price trust, QA, trial copy, and purchase validation can diverge | Small to medium | High |
| BOND-04 | P1 | Custom paywall is single-screen, fixed-height, English-only, and line-limited | Dynamic Type, localization, small devices, and long regional prices can clip or hide the purchase decision | Medium | High |
| BOND-05 | P1 | Trial copy is inferred by scanning an English label and onboarding disclosure is incomplete | Trial eligibility can look like a plain upgrade, or the legal reassurance can be weaker than the full paywall | Small | High |
| BOND-06 | P1 | Only custom paywall impressions are instrumented | Downloads, first value, trial starts, purchase failures, gates, and review outcomes cannot be attributed locally | Medium | High |
| BOND-07 | P1 | Canonical site, ASC URLs, legal URLs, pairing host, and repository instructions disagree | Search, support, pairing, and App Review trust signals are fragmented | Small | High |
| BOND-08 | P1 | Review funnel records a positive moment after a swallowed completion error and invokes native review after Maybe later | Users can be asked at the wrong time, and the funnel cannot explain outcomes | Small | High |
| BOND-09 | P1 | Important notification and database errors are swallowed; location is positioned as an arrival feature with only When In Use permission | A saved feature can fail without a user-visible or release-watchdog signal | Medium | High |
| BOND-10 | P1 | Deprecated Supabase realtime and StoreKit storefront APIs remain, and CI uses a named simulator | OS upgrades can break release flows while CI passes only in a stale environment | Small to medium | High |
| BOND-11 | P1 | Onboarding requires several inputs before first value, permits zero love-language selections, and schedules another paywall after the notification primer | The landing-page first-value promise is unproven and the first session can feel like stacked interruptions | Medium | Medium to high |
| BOND-12 | P1 | Support and sitemap dates are stale relative to legal pages, with duplicate page trees | Users and crawlers can receive different freshness signals and support can lag current behavior | Small | High |
| BOND-13 | P1 | ASC scripts silently truncate fields and contain a cross-app headache fallback | A future upload can silently corrupt copy or publish the wrong app's description | Small | High |
| BOND-14 | P1 | RevenueCat unlock fallback grants access on any active entitlement or active subscription | Dashboard mapping errors become invisible and revenue attribution can be wrong | Small | High |
| BOND-15 | P1 | No crash, hang, or production funnel telemetry is present in the app repository | A Mac watchdog cannot alert on live-user regressions without an external data source | Medium | High |

Recommended implementation order:

1. Fix BOND-01, BOND-02, and BOND-03 before using trial-start or revenue conclusions.
2. Add the funnel and entitlement instrumentation from BOND-06 and BOND-14.
3. Make paywall, onboarding, notification, and pairing states resilient at large text sizes and offline.
4. Consolidate URLs and stale docs, then run the scanner rules in this audit on every release.
5. Use live ASC, RevenueCat, App Store review, and crash data to choose ASO and native paywall experiments.

## Repository and runtime inventory

| Surface | Evidence | Audit implication |
|---|---|---|
| iOS app | Bond target, bundle ID com.jackwallner.bond, iOS 18.0, Swift 6.0 | Main acquisition, onboarding, purchase, reminders, review, and support surface |
| Watch app | BondWatch target, bundle ID com.jackwallner.bond.watch, watchOS 11.0 | Advertised differentiator and first-value shortcut |
| Widgets | BondWidgets app extension, two static widgets | Acquisition proof and retention surface, fed through the App Group snapshot |
| Backend | Supabase Auth, Postgres migrations, realtime, send-push edge function | Pairing, shared reminders, check-ins, partner delivery |
| Payments | RevenueCat 5.67.0 package, custom native paywall, StoreKit scheme fixture | Trial, subscription, lifetime support, and conversion |
| Metadata | 50 fastlane locale folders, 50 Deliverfile languages | Broad listing reach, but screenshot and in-app localization are narrower |
| Site | docs/index.html, legal pages, clean URL duplicate trees, portfolio sync workflow | Landing-page acquisition, legal trust, support, pairing links |
| Automation | fastlane metadata lane, ASC Python scripts, CI, landing-page sync | Release consistency and scanner insertion points |
| Tests | BondTests model and DTO tests | Useful model safety net, but no purchase, UI, notification, watch, widget, or service integration coverage |

Key project facts from project.yml:

- Marketing version 1.0.5, build 68 at project.yml:10-17.
- Run and test actions load Bond/Products.storekit at project.yml:27-42.
- Products.storekit is excluded from the shipping Bond target at project.yml:66-75.
- Bond depends on BondWidgets and embeds BondWatch at project.yml:84-94.
- RevenueCat and Supabase package lower bounds are 5.67.0 and 2.24.0 at project.yml:19-25.
- Bond/Info.plist carries App Store ID 6768514177, the Supabase URL and anon key, the URL scheme bond, and only NSLocationWhenInUseUsageDescription at Bond/Info.plist:17-54.

## Prioritized findings

### BOND-01: Pending solo purchase advances into the app

Severity: P0

Effort: Small

Confidence: High

Evidence:

- IntentSetupView.startTrialPurchase calls store.purchase at Bond/Features/Onboarding/IntentSetupView.swift:395-417.
- Both .purchased and .pending call await finish at Bond/Features/Onboarding/IntentSetupView.swift:407-413.
- PurchasesService can return .pending after syncing and polling for roughly nine seconds without an active entitlement at Bond/Services/PurchasesService.swift:219-245.
- finish creates the solo couple when one does not exist at Bond/Features/Onboarding/IntentSetupView.swift:559-571.
- The full PaywallView handles .pending separately, sets a status message, and calls restore at Bond/Features/Paywall/PaywallView.swift:378-390. The two purchase surfaces therefore have different safety behavior.

Inference:

An Apple payment can be accepted while RevenueCat entitlement propagation is delayed. The in-flow onboarding surface can then create the couple and route to home even though isPremium is false. The user may believe the trial or purchase succeeded, land behind free gates, and have no obvious recovery except Settings or a later restore. This is a conversion and support problem, not evidence of a current live failure.

Recommendation:

Use one purchase-result state machine for onboarding and the full paywall. On .pending, keep the user on a clearly labeled pending state, offer Restore purchases, refresh entitlement on foreground, and only call finish after isPremium becomes true. If the product decision is to let users continue on the free tier, make that an explicit user choice after the pending state, not an automatic completion. Record purchase source, product ID, and pending duration.

Validation:

1. StoreKit test a delayed or pending transaction on the solo onboarding trial step.
2. Confirm no couple creation or home transition occurs before the chosen completion condition.
3. Confirm a later entitlement update dismisses the pending state without duplicating the couple.
4. Cancel, network-fail, restore, and previously-ineligible-account cases must each have deterministic UI.

### BOND-02: Partner reminder delivery has no verified remote path

Severity: P0

Effort: Medium to large

Confidence: High

Evidence:

- NotificationScheduler.reschedule schedules only reminders where reminder.targetId == selfId at Bond/Services/NotificationScheduler.swift:27-51.
- Partner-targeted reminders therefore rely on the Supabase edge function.
- The edge function expects profiles.apns_token at SupabaseFunctions/send-push/index.ts:76-85, then sends to APNs at SupabaseFunctions/send-push/index.ts:87-130.
- ProfileDTO has an apnsToken field, but no client registration or write of an APNs token was found in Bond, Shared, BondWatch, or BondWidgets.
- No registerForRemoteNotifications or didRegisterForRemoteNotifications implementation was found.
- README.md:76-81 calls APNs Phase 2 and describes deployment as future work.
- docs/MVP_TRIAGE.md:54-58 independently documents the same missing registration and target filtering.

Inference:

Creating a reminder for a partner can write successfully while neither device schedules a notification locally and no remote delivery can occur if the partner has no stored token. The product can appear to save the gesture while failing at the moment that creates value. This is especially dangerous because the save UI has no end-to-end delivery confirmation.

Recommendation:

Choose one honest product state before the next growth experiment:

- Complete APNs registration, token persistence, webhook deployment, environment selection, token invalidation, delivery logging, and a server-side test.
- Or disable partner targeting until delivery exists.
- Or provide an explicitly labeled interim behavior that does not imply the partner was notified.

Do not use partner reminder completion or review prompts as success signals until delivery is measured.

Validation:

1. Two TestFlight devices, separate accounts, one paired couple.
2. Create self-targeted and partner-targeted reminders.
3. Verify local scheduling, token persistence, webhook invocation, APNs response, notification receipt, tap routing, and duplicate suppression.
4. Test token rotation, permission denied, offline save, app deleted, and APNs sandbox versus production.

### BOND-03: Price and product truth are not one source of truth

Severity: P0

Effort: Small to medium

Confidence: High

Evidence:

- All 50 local description files contain the subscription copy with $2.99 per month, $19.99 per year, and a 7-day trial. en-US is at fastlane/metadata/en-US/description.txt:19.
- The landing JSON-LD advertises $2.99 monthly, $19.99 yearly, and $39.99 lifetime at docs/index.html:30-54.
- The local StoreKit fixture uses $4.99 monthly and $29.99 yearly at Bond/Products.storekit:25-75.
- The StoreKit fixture contains two subscription products and no lifetime product at Bond/Products.storekit:1-82.
- PaywallPackage+Bond supports .lifetime, .yearly, and .monthly at Bond/Features/Paywall/PaywallPackage+Bond.swift:1-42.
- The site body and terms advertise monthly, yearly, and lifetime at docs/index.html:528-530 and docs/terms.html:104-117.
- Commit 8760316, dated 2026-07-31, says the metadata prices were changed to values taking effect on 2026-08-02. That commit text is historical and does not establish current ASC or RevenueCat prices.

Inference:

The development paywall, screenshots, UI tests, landing page, ASC metadata, and remote offering can be testing different commercial products. A developer can validate trial UX against $4.99/$29.99 while a user sees another price. The lifetime path may also be tested only against a live offering and not the scheme fixture. Do not infer which source is live from this repository.

Recommendation:

Create one checked-in product manifest for product IDs, product kinds, trial eligibility language, and test prices. Generate the StoreKit fixture, screenshot harness defaults, site structured data, and metadata price sentence from that manifest, or make all consumers fail when they diverge. Before changing copy, query live ASC and RevenueCat and record the verified regional source and effective date. Keep region-dependent prices dynamic in the app and avoid hardcoded prices in long-lived copy when possible.

Validation:

1. Compare live ASC product metadata, RevenueCat offering packages and entitlement mapping, StoreKit fixture, site JSON-LD, fastlane descriptions, and screenshot harness.
2. Test monthly, yearly, lifetime, eligible trial, ineligible trial, restore, and regional currency formatting.
3. Add a scanner failure for any price token not in the manifest.

### BOND-04: Native paywall layout is not safe for localization and accessibility

Severity: P1

Effort: Medium

Confidence: High

Evidence:

- PaywallView deliberately uses a fixed single-screen VStack and no ScrollView at Bond/Features/Paywall/PaywallView.swift:129-142.
- Header, benefit, plan, CTA, and legal copy use line limits at Bond/Features/Paywall/PaywallView.swift:145-175 and :203-285.
- TrialOfferSheet also uses line limits and minimum scale factors at Bond/Features/Paywall/TrialOfferSheet.swift:53-118.
- There are no .lproj, Localizable.strings, or Localizable.xcstrings resources in the repository.
- ASC has 50 localized listings, but the in-app paywall and onboarding strings are source-language literals.
- The paywall defaults to yearly at PaywallView.swift:349-366 and IntentSetupView.swift:367-369.
- The plan card combines multiple text elements into one accessibility element at PaywallView.swift:511-512, but no explicit accessibility value for price, trial eligibility, selected plan, or renewal period was found.

Inference:

The native paywall can work in the English reference size while clipping or truncating in German, French, Arabic, CJK, RTL, Dynamic Type, small iPhones, or a region with a longer formatted price. A line-limited purchase disclosure is a trust and review risk. A 50-locale ASC strategy can send a user to an English, less usable in-app purchase surface.

Recommendation:

Use structured localized strings and Product.SubscriptionOffer data, not display-label parsing. Make the paywall vertically scrollable or use a measured layout that guarantees the CTA and legal disclosure remain reachable. Remove line limits from legal and benefit copy unless the complete text is available elsewhere. Add accessibility labels and values for each plan, trial state, price, renewal period, restore, and selected state. Test RTL and all supported content sizes.

Validation:

Run the paywall screenshot harness and UI tests at:

- iPhone SE and the smallest supported iPhone.
- Extra Extra Large and accessibility content sizes.
- English, German, French, Arabic, Japanese, Simplified Chinese, and a long-price locale.
- RTL, VoiceOver, Reduce Motion, Increase Contrast, and bold text.
- Products loading, empty, failed, eligible trial, ineligible trial, pending, restored, and purchase error states.

### BOND-05: Trial display logic is derived from English text and is inconsistent

Severity: P1

Effort: Small

Confidence: High

Evidence:

- TrialOfferSheet.trialPeriodPhrase creates a Scanner from offerLabel and looks for an integer followed by a word at Bond/Features/Paywall/TrialOfferSheet.swift:15-23.
- PaywallPackage+Bond.bondIntroOfferLabel returns English strings such as 7-day free trial at Bond/Features/Paywall/PaywallPackage+Bond.swift:66-88.
- IntentSetupView.trialDisclosure has a trial branch and a nontrial fallback at Bond/Features/Onboarding/IntentSetupView.swift:386-393.
- The nontrial fallback says only the price and Auto-renews unless cancelled at IntentSetupView.swift:392. It does not include the full paywall's 24-hour timing or App Store settings guidance.
- PaywallView uses a different disclosure and pending handling at PaywallView.swift:329-390.

Inference:

An offer label that is localized, formatted differently, or missing a numeral can remove the trial badge and change the CTA to an unlock label. Separately, the solo onboarding purchase decision gives weaker renewal context than the full plan picker. Both cases can lower trial starts through uncertainty and create copy drift.

Recommendation:

Expose a typed offer model containing eligibility, period value, period unit, payment mode, formatted price, renewal period, and product ID. Render localized copy from that model. Share the same disclosure builder between onboarding, TrialOfferSheet, and PaywallView. Treat an unavailable eligibility response as loading or unknown, not as a permanent nontrial state, while still never promising a trial before Apple confirms eligibility.

Validation:

Unit test week, month, year, free, pay-up-front, pay-as-you-go, missing offer, localized label, and unknown eligibility. Snapshot the exact CTA and disclosure in every state.

### BOND-06: Funnel instrumentation cannot answer the growth questions

Severity: P1

Effort: Medium

Confidence: High

Evidence:

- PurchasesService only calls RevenueCat custom paywall impression tracking at Bond/Services/PurchasesService.swift:142-156.
- No setAttributes, setAttribute, custom purchase event, trial-start event, restore event, gate click event, onboarding step event, notification permission event, or first-value event was found.
- Purchase logging records local OSLog messages but does not provide a persisted or queryable event stream at PurchasesService.swift:159-245.
- ReviewPromptTracker stores local counters and outcomes but does not emit a product analytics event at Shared/Services/ReviewPromptTracker.swift:94-153.
- The app has several distinct paywall IDs: onboarding_personalized_plan, onboarding_trial_fallback, post_pairing, post_onboarding, and feature-gate surfaces. They are not joined to step, plan, eligibility, or outcome data.

Inference:

The team cannot distinguish an App Store impression problem from an onboarding completion problem, a paywall load problem, an Apple purchase problem, an entitlement mapping problem, or a product-value problem. A/B tests would be selected by intuition rather than conversion evidence.

Recommendation:

Instrument a privacy-safe funnel with stable non-PII dimensions:

1. app_launch, bootstrap_started, bootstrap_succeeded, bootstrap_failed
2. onboarding_step_viewed and onboarding_completed
3. first_value_viewed, first_reminder_started, first_reminder_saved, first_reminder_scheduled, first_reminder_completed
4. pairing_started, pairing_link_shared, pairing_consumed, pairing_failed
5. notification_primer_viewed, notification_permission_result
6. paywall_impression, plan_selected, trial_cta_tapped, purchase_started, purchase_cancelled, purchase_pending, purchase_succeeded, purchase_failed, restore_started, restore_succeeded, restore_failed
7. entitlement_active, entitlement_missing_after_purchase, product_fetch_empty, product_fetch_failed
8. feature_gate_viewed and feature_gate_cta_tapped
9. review_prompt_viewed, feedback_selected, write_review_opened, native_review_requested

Use a release version, build, source/paywall ID, onboarding path, product kind, trial eligibility, and app state as dimensions. Do not include partner names, reminder text, response text, location labels, or other content.

Validation:

Build an event sequence test for a new solo user and a paired user. Assert every event has an app version, build, source, timestamp, and outcome, and that duplicate screen re-renders do not duplicate impressions.

### BOND-07: URL, host, and canonical-site truth is fragmented

Severity: P1

Effort: Small

Confidence: High

Evidence:

- All 50 ASC metadata locales use marketing URL https://jackwallner.github.io/bond/, privacy URL https://jackwallner.github.io/bond/privacy/, and support URL https://jackwallner.github.io/bond/support/.
- The landing page canonical and og:url point to https://jackwallner.com/ios/bond/ at docs/index.html:10 and :16.
- The landing page image URLs still use the GitHub Pages host at docs/index.html:17 and :22.
- The landing page says pairing uses bond.jackwallner.com at docs/index.html:539.
- PairingService explicitly generates and accepts jackwallner.com links, and comments that bond.jackwallner.com has no DNS, at Bond/Services/PairingService.swift:31-37 and :151-184.
- PaywallLinks and Settings links use the GitHub Pages privacy and terms paths at Bond/Features/Paywall/PaywallView.swift:4-7 and Bond/Features/Settings/SettingsView.swift:192-195.
- The current mirror workflow pushes docs into the portfolio repository at .github/workflows/sync-landing-page.yml:1-56, while CLAUDE.md:6-9 and README.md:63-74 describe an older GitHub Pages ownership model.

Inference:

Search engines, App Store visitors, in-app paywall users, and pairing recipients can see different canonical hosts. A user who trusts the site pairing label can receive a link that does not match the real universal-link host. Duplicate URLs also make link checking and incident response less precise.

Recommendation:

Choose one public canonical host, one clean route scheme, and one source repository. Add explicit redirects from legacy paths. Generate ASC URL files, app URLs, legal links, pairing copy, JSON-LD, robots, sitemap, and image URLs from a single site configuration. Update CLAUDE.md and README.md in the implementation change. Do not report the RevenueCat disclosure wording issue as requested, but keep the URL and product claims aligned.

Validation:

Use a URL scanner to check every literal URL, redirect chain, canonical, og:url, sitemap loc, App Store link, paywall/legal link, and universal-link host. Test an invite link from Safari, Messages, and a cold app launch.

### BOND-08: Review funnel can trigger after a failed completion and has unclear native timing

Severity: P1

Effort: Small

Confidence: High

Evidence:

- completeReminder ignores the result of createEvent with try? at Bond/Features/ReminderList/ReminderListView.swift:466-480.
- The method records a positive moment and posts the review signal even if the event write failed at :477-480.
- Release thresholds are five launches, seven days since first open, three positive moments, and a 120-day cooldown at Shared/Services/ReviewPromptTracker.swift:26-37 and :117-129.
- ReviewPromptSheet sends an explicit App Store write-review link at Bond/Features/Review/ReviewPromptSheet.swift:144-155.
- The Maybe later branch calls markShown and finishes with enjoyedMaybeLater at ReviewPromptSheet.swift:157-163.
- RootView then invokes requestReview on sheet dismissal when pendingNativeReviewAfterDismiss is set at Bond/BondApp.swift:277-284.
- docs/review-prompt.md:16-22 documents this behavior and says native requestReview only fires on Maybe later.

Inference:

A failed completion can count as a successful emotional moment. Also, a user who says Maybe later in a review pitch can receive the system review prompt immediately after dismissal, which may feel like the same request repeating. The local tracker has no event-level evidence of whether the external page opened or the system prompt was shown.

Recommendation:

Record the positive moment only after the completion write succeeds. Separate the external write-review and native prompt strategies, or make native prompting follow an explicit delay and a separate eligibility decision. Add local outcome events and a server-side aggregate if available. Keep Settings as the manual route and do not prompt during onboarding, pairing, purchase, or an error recovery state.

Validation:

Force completion write failure, test duplicate taps, test all review choices, and assert no positive moment or review request follows a failed write. Verify cooldown and one-time outcomes using injected dates.

### BOND-09: Silent notification and data errors hide degraded UX

Severity: P1

Effort: Medium

Confidence: High

Evidence:

- NotificationScheduler ignores authorization errors and notification add errors at Bond/Services/NotificationScheduler.swift:11-16, :115-120, and :202-224.
- Location triggers are scheduled using UNLocationNotificationTrigger at :241-252.
- LocationService requests only When In Use authorization at Bond/Services/LocationService.swift:17-25 and :33-49.
- Bond/Info.plist declares only NSLocationWhenInUseUsageDescription at :40-41.
- ReminderEditorView exposes location as a premium trigger and says it triggers on arrival at Bond/Features/ReminderEditor/ReminderEditorView.swift:232-266.
- DailyCheckInService stores load errors at Bond/Services/DailyCheckInService.swift:67-70, but DailyCheckInView's top-level state branch at Bond/Features/CheckIn/DailyCheckInView.swift:16-35 does not visibly render lastError.

Inference:

A user can save a location reminder, leave the app, and never receive the intended background notification. A notification scheduling failure can be indistinguishable from success. A check-in load failure can fall through to an incomplete question or gate instead of a retryable error. These are release-watchdog candidates because they degrade value without a crash.

Recommendation:

Surface scheduling failure when the user saves, include a permission-specific recovery action, and record schedule success or failure. Decide whether location reminders are intended to work in the background and implement the correct authorization flow, or change the product copy and capability. Render check-in lastError with Retry and keep the prior successful question when refresh fails.

Validation:

Test notification denied, restricted, provisional, background location, authorization changes in Settings, no network, Supabase 500, malformed trigger, and a full device restart. Assert the app does not report a successful save when scheduling failed.

### BOND-10: Deprecated APIs and CI environment are release risks

Severity: P1

Effort: Small to medium

Confidence: High

Evidence:

- ios27Bond.md:20-28 records SKPaymentQueue.default().storefront?.countryCode as deprecated since iOS 18 and Supabase postgresChange/subscribe as deprecated.
- The StoreKit API remains at Shared/Utilities/AppStoreReviewLinks.swift:25-30.
- Supabase realtime remains at Bond/Services/ReminderRepository.swift:99-117.
- CI uses a named destination iPhone 16 Pro with OS 18.4 at .github/workflows/ci.yml:31-50.
- The repository's fleet simulator convention requires headless leased devices, not named destinations.
- CI has no UI tests, StoreKit purchase tests, watch build, widget validation, metadata lint, legal link check, or release-watchdog check.

Inference:

An OS or package update can break these paths after the current unit tests still pass. A named simulator can hide failures caused by the actual shared pool or current runtime. Realtime and review-link failures are not covered by the existing pure model tests.

Recommendation:

Replace deprecated APIs with the current StoreKit storefront and Supabase realtime APIs after checking the pinned package API. Make CI use a stable headless simulator strategy or a supported generic destination that matches the runner. Add a BondWatch build, metadata scanner, StoreKit fixture smoke test, critical UI flow tests, and deprecated-pattern scanning.

Validation:

Run a clean XcodeGen generation, build all targets, unit tests, StoreKit fixture smoke tests, and UI matrix on the current supported Xcode and iOS runtime. Treat warnings in touched surfaces as failures.

### BOND-11: First value is delayed and the first session can stack interruptions

Severity: P1

Effort: Medium

Confidence: Medium to high

Evidence:

- Solo intent setup captures partner name, commitment, love language, and focus areas before creating a solo couple, with the trial step after those inputs at Bond/Features/Onboarding/IntentSetupView.swift:131-159.
- Love-language selection is not required by canContinue at IntentSetupView.swift:318-323. Only the name and at least one focus area are required.
- The trial step can present a notification primer on first home arrival, then RootView waits 500 ms and presents a post-onboarding paywall at Bond/BondApp.swift:296-318.
- The landing page promises Under a minute to your first reminder at docs/index.html:478-500, but the actual path includes anonymous auth, several input screens, a network couple creation, and a purchase or free exit.
- Invitee onboarding begins at step 2 and bypasses the solo trial step at IntentSetupView.swift:152-159 and :341-347.

Inference:

The first-value claim may be true for a fast returning user but is not established for a cold, offline, or permission-sensitive user. The notification primer followed by a paywall can feel like two consecutive asks immediately after the user reaches home. A user who chooses no love language still receives a personalized-plan frame with a default primary language later.

Recommendation:

Define first value as a measurable event, preferably a saved and schedulable first reminder. Measure time from launch, setup start, first screen, and setup completion. Consider letting the user create the first self-targeted reminder before the trial ask, or make the trial ask clearly tied to the feature the user just attempted. Do not present two modal asks in a row without an explicit user value moment. Either require a love-language selection for the personalized path or clearly support a general path.

Validation:

Instrument and test cold launch, slow network, no notification permission, free exit, trial purchase, invitee path, and first reminder creation. Compare completion and time-to-first-value by path.

### BOND-12: Support and sitemap freshness are behind the legal pages

Severity: P1

Effort: Small

Confidence: High

Evidence:

- Terms and privacy pages say Last updated: August 17, 2026 at docs/terms.html:86-87 and docs/privacy-policy.html:86-87.
- Support says Last updated: May 26, 2026 at docs/support.html:17-20.
- Sitemap lastmod is 2026-05-26 for all URLs at docs/sitemap.xml:3-21.
- Root and clean-route copies exist for all three legal/support surfaces. They have different hashes, so they are not byte-identical.
- Support describes local notifications and location behavior at docs/support.html:36-48 but does not cover the lifetime purchase path present in terms and site.

Inference:

Users reaching support after a release can get older instructions than the legal pages, and crawlers can treat current legal pages as stale. Duplicate pages increase the chance that one copy is updated without the other.

Recommendation:

Choose one canonical source page per surface and generate or mirror the clean route. Update support when subscription products, pairing, notification delivery, or location behavior changes. Generate sitemap lastmod from source file dates or a release task, and add a link checker that compares all duplicate routes.

Validation:

Fetch root and clean routes in a production-like local server, compare title, canonical, update date, product claims, support email, legal links, and HTTP status. Include trailing-slash and non-trailing-slash URLs.

### BOND-13: ASC automation can silently change or cross-contaminate metadata

Severity: P1

Effort: Small

Confidence: High

Evidence:

- asc_lib.description_for_locale falls back to a hardcoded headache tracker sentence if the source description is too short at scripts/asc_lib.py:248-255.
- asc-upload-metadata.py slices descriptions, keywords, release notes, URLs, promotional text, names, and subtitles before upload at scripts/asc-upload-metadata.py:36-54 and :155-160.
- asc-add-missing-localizations.py uses the same truncating behavior and fallback keywords headache,tracker at scripts/asc-add-missing-localizations.py:120-132 and :225-241.
- The metadata currently passes measured hard limits, so this is a future automation risk rather than evidence of current bad ASC content.

Inference:

A typo, missing file, or overlong translation can be silently truncated or replaced with another app's content instead of failing before upload. This can erase a carefully written CTA or publish an irrelevant description.

Recommendation:

Make metadata lint fail before any API call. The uploader should reject overlong fields, missing required files, empty fields, unknown locales, cross-app fallback text, URL host drift, price drift, and duplicate unexpected values. Keep fallback values app-specific and explicit. Upload only after a report is reviewed.

Validation:

Run the scanner against intentionally missing, overlong, empty, non-Bond, and malformed metadata and assert a nonzero exit without network activity.

### BOND-14: RevenueCat entitlement fallback hides mapping errors

Severity: P1

Effort: Small

Confidence: High

Evidence:

- PurchasesService sets the intended entitlement ID to Husband & Wife Reminder - Bond Pro at Bond/Services/PurchasesService.swift:17-23.
- hasActivePremium returns true for the named entitlement, then any active entitlement, any active subscription, or a known non-subscription product at Bond/Services/PurchasesService.swift:363-389.
- The comments at :365-377 state that the broad fallback exists to cover dashboard mapping failures.
- knownProductIds is populated from the current offering at :97-110.

Inference:

The fallback can prevent a paying customer from being locked out, but it can also grant Bond+ when an unrelated entitlement or subscription is active on the same RevenueCat customer. It makes a broken dashboard mapping look healthy and weakens revenue, churn, and entitlement monitoring.

Recommendation:

Use the named entitlement as the production source of truth after verifying live configuration. If a compatibility fallback is temporarily needed, distinguish the resolution source, emit an entitlement_mismatch event, alert on it, and give the fallback an expiry date. Do not treat any active subscription as Bond+ without a verified product allowlist and offering context.

Validation:

Use fixture customer-info payloads for correct entitlement, wrong entitlement, unrelated subscription, known lifetime, expired entitlement, and unknown product. Assert access and mismatch telemetry separately.

### BOND-15: No production crash, hang, or degraded-UX telemetry exists locally

Severity: P1

Effort: Medium

Confidence: High

Evidence:

- Search of the app targets found OSLog categories in services, but no Crashlytics, Sentry, Bugsnag, Datadog, New Relic, MetricKit, signpost, analytics SDK, or server event collector.
- OSLog calls exist in SupabaseService, PurchasesService, ReminderRepository, PairingService, DailyCheckInService, MilestonesService, ReminderEventRepository, and watch connectivity, but local OSLog is not a live-user alert pipeline.
- No crash or hang upload configuration is present in project.yml, Info.plist, fastlane, or CI.

Inference:

A Mac script cannot notify about a live user's crash from this repository alone. It needs an external source such as App Store Connect diagnostics, MetricKit delivery to a backend, or an approved crash provider. Even with crash data, purchase pending, empty offerings, failed notification scheduling, pairing failures, and time-to-first-value need explicit product signals.

Recommendation:

Scaffold a configurable watchdog with these source adapters:

- App Store Connect or crash-provider crash and hang summaries.
- RevenueCat customer, offering, transaction, and entitlement health.
- Supabase function and database logs for pairing, reminder writes, and send-push.
- App-side aggregate events for funnel and degraded-UX states.
- Git release metadata for version, build, release time, and rollout window.

Use alert thresholds relative to a rolling baseline, alert only after a minimum user or device count, deduplicate by release and signal, and retain a local state file. Do not claim real-time crash detection if the source is delayed.

Validation:

Feed the watchdog fixture JSON with a crash spike, purchase-pending spike, empty offering response, pairing RPC errors, notification failures, and a normal baseline. Assert one alert per incident, cooldown behavior, release-window escalation, and useful links to the offending build.

## App Store growth and metadata analysis

### Exact local ASC field counts

Measured from stripped UTF-8 text in fastlane/metadata on 2026-08-23. The local iOS fleet convention used here is name 30, subtitle 30, keywords 100, description 4000, promotional text 170, and release notes 4000.

| Field | Locales | Min | Max | Over local limit |
|---|---:|---:|---:|---:|
| name | 50 | 24 | 30 | 0 |
| subtitle | 50 | 24 | 30 | 0 |
| keywords | 50 | 94 | 100 | 0 |
| description | 50 | 515 | 1883 | 0 |
| promotional_text | 50 | 133 | 133 | 0 |
| release_notes | 50 | 14 | 71 | 0 |

Exact en-US values:

| Field | Count | Value |
|---|---:|---|
| name | 29 | Bond: Love Language Reminders |
| subtitle | 26 | Love Language Reminder App |
| keywords | 97 | couple,partner,spouse,relationship,marriage,nudge,notes,date,anniversary,widget,questions,romance |
| description | 1484 | Good intentions are easy. Remembering at the right moment is harder. Bond turns what matters to your partner into simple reminders you can act on. It includes personalized reminders, ready-made packs, milestones, pairing, Apple Watch dictation, a free tier, Bond+ trial copy, subscription terms, and legal URLs. The exact file is fastlane/metadata/en-US/description.txt. |
| promotional_text | 133 | Turn good intentions into real gestures: personalized love-language reminders, ready-made ideas, milestones, and a 7-day Bond+ trial. |
| release_notes | 56 | Stability improvements and clearer subscription details. |
| support_url | 43 | https://jackwallner.github.io/bond/support/ |
| marketing_url | 35 | https://jackwallner.github.io/bond/ |
| privacy_url | 43 | https://jackwallner.github.io/bond/privacy/ |

Full locale count table:

| Locale | Name | Subtitle | Keywords | Description | Promo | Notes |
|---|---:|---:|---:|---:|---:|---:|
| ar-SA | 26 | 30 | 96 | 1361 | 133 | 41 |
| bn-BD | 30 | 30 | 96 | 1578 | 133 | 54 |
| ca | 29 | 30 | 97 | 1740 | 133 | 58 |
| cs | 29 | 30 | 100 | 1598 | 133 | 55 |
| da | 26 | 30 | 96 | 1680 | 133 | 58 |
| de-DE | 25 | 30 | 96 | 1421 | 133 | 50 |
| el | 26 | 29 | 98 | 1793 | 133 | 57 |
| en-AU | 29 | 26 | 97 | 1484 | 133 | 56 |
| en-CA | 29 | 26 | 97 | 1484 | 133 | 56 |
| en-GB | 29 | 26 | 97 | 1484 | 133 | 56 |
| en-US | 29 | 26 | 97 | 1484 | 133 | 56 |
| es-ES | 25 | 29 | 98 | 1219 | 133 | 60 |
| es-MX | 25 | 28 | 98 | 1726 | 133 | 60 |
| fi | 24 | 25 | 100 | 1688 | 133 | 45 |
| fr-CA | 26 | 30 | 99 | 1883 | 133 | 66 |
| fr-FR | 26 | 30 | 97 | 1268 | 133 | 66 |
| gu-IN | 27 | 30 | 98 | 1501 | 133 | 52 |
| he | 24 | 27 | 100 | 1304 | 133 | 37 |
| hi | 26 | 30 | 95 | 1589 | 133 | 52 |
| hr | 24 | 29 | 98 | 1675 | 133 | 53 |
| hu | 29 | 24 | 99 | 1659 | 133 | 65 |
| id | 30 | 30 | 99 | 1704 | 133 | 61 |
| it | 27 | 30 | 97 | 1753 | 133 | 66 |
| ja | 24 | 26 | 100 | 623 | 133 | 29 |
| kn-IN | 29 | 30 | 96 | 1608 | 133 | 54 |
| ko | 24 | 24 | 99 | 876 | 133 | 22 |
| ml-IN | 28 | 30 | 98 | 1789 | 133 | 71 |
| mr-IN | 24 | 30 | 96 | 1524 | 133 | 47 |
| ms | 30 | 30 | 97 | 1749 | 133 | 65 |
| nl-NL | 25 | 24 | 98 | 1752 | 133 | 62 |
| no | 25 | 30 | 100 | 1688 | 133 | 55 |
| or-IN | 26 | 26 | 98 | 1560 | 133 | 50 |
| pa-IN | 27 | 30 | 100 | 1527 | 133 | 52 |
| pl | 26 | 30 | 100 | 1742 | 133 | 59 |
| pt-BR | 24 | 28 | 95 | 1717 | 133 | 63 |
| pt-PT | 24 | 28 | 100 | 1729 | 133 | 63 |
| ro | 25 | 25 | 96 | 1769 | 133 | 62 |
| ru | 27 | 30 | 94 | 1709 | 133 | 57 |
| sk | 26 | 30 | 97 | 1631 | 133 | 57 |
| sl-SI | 25 | 30 | 99 | 1636 | 133 | 55 |
| sv | 28 | 30 | 97 | 1697 | 133 | 65 |
| ta-IN | 25 | 27 | 99 | 1784 | 133 | 56 |
| te-IN | 26 | 30 | 99 | 1626 | 133 | 66 |
| th | 25 | 30 | 99 | 1457 | 133 | 58 |
| tr | 30 | 30 | 98 | 1644 | 133 | 60 |
| uk | 28 | 30 | 98 | 1698 | 133 | 56 |
| ur-PK | 29 | 30 | 100 | 1581 | 133 | 49 |
| vi | 28 | 30 | 100 | 1617 | 133 | 54 |
| zh-Hans | 24 | 24 | 100 | 515 | 133 | 14 |
| zh-Hant | 24 | 24 | 100 | 653 | 133 | 14 |

### Metadata consistency and growth opportunities

Evidence:

- All 50 promotional text files are identical English copy.
- All 50 support, marketing, and privacy URL files are identical.
- Name has 44 unique values, subtitle 45, keywords 46, description 47, and release notes 45.
- The four English locales duplicate the en-US fields. French, Spanish, and Portuguese regional pairs share selected fields, which is reasonable when the copy is intentionally shared.
- Commit 8760316 says 41 of 50 locales previously had translated title, subtitle, and keywords but English description, and all 50 had English release notes. The commit says the listing's non-US impression share was 87% and download rate per impression was 0.78%. This is a historical commit claim, not a current metric and not independently verified.
- There are no localized screenshot folders. Only fastlane/screenshots/en-US exists.

Recommendations:

1. Use ASC data to rank locales by impressions, product-page views, downloads, trial starts, and revenue, then prioritize screenshots and copy for the highest opportunity locales. Do not allocate based on the historical 87% claim alone.
2. Test the English subtitle and keyword strategy against a positioning variant focused on reminders and love-language nudges. aso-plan.md:9-13 proposes Daily Love Language Nudges, but the current subtitle remains Love Language Reminder App. Verify current ASC state before using that plan.
3. Test promotional text variants around the first-value promise, daily check-in, partner delivery, and 7-day trial. Keep pricing dynamic or generated from the verified manifest.
4. Add localized screenshot sets for high-opportunity locales. The current English screenshot text makes localized listing traffic land on an English visual.
5. Keep keywords within the measured limit but fail on overlength instead of truncating. Avoid repeating name and subtitle tokens when the target locale does not need them.

## Screenshots, video, icon, and localization quality

### Evidence

- fastlane/screenshots/en-US contains five iPhone PNGs at 1320 x 2868 and one Watch PNG at 410 x 502.
- The first five docs/appstore-screenshot-01.png through 05.png are byte-identical copies of the first five English fastlane screenshots.
- All screenshot files are RGBA containers but have alpha minimum and maximum 255, so they are fully opaque.
- No mp4, mov, m4v, webm, or gif marketing video asset was found.
- Bond/Assets.xcassets/AppIcon.appiconset/AppIcon.png and BondWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png are 1024 x 1024 RGB PNGs with identical MD5 hashes. docs/icon_256.png is a separate 256 x 256 RGB copy.
- Visual review found a coherent warm cream, terracotta, blush, and black system. The five iPhone concepts clearly cover reminders, check-in, milestones, widgets, and templates. The product's core loop is legible without relying on a live account.
- The Watch screenshot is a partial dictation screen. It ends while the Language control is entering view, shows no send or saved state, and has a dark low-contrast presentation. It is not a complete proof of the Watch value.

### Recommendations

- Replace the Watch shot with a complete, readable sequence showing dictation, target, language, send, and confirmed handoff. Capture at the actual ASC-supported Watch family and verify safe-area cropping.
- Add localized screenshots only after choosing target locales from live ASC performance. Do not translate overlay text without matching in-app behavior.
- Consider a short App Preview only if there is a supported production capture path. The repository currently has no video artifact or automated video validation.
- Validate every screenshot for dimensions, opaque pixels, no clipped overlay text, no accidental personal data, and the current feature and price claims.
- Include a screenshot about the first reminder and partner delivery, not only polished destination screens. A user should understand the first successful action.

## Install to first value to trial flow

### Flow map

| Stage | Code path | Current behavior | Conversion risk |
|---|---|---|---|
| Bootstrap | Bond/BondApp.swift:236-247 and SupabaseService | Restores or creates an anonymous session, identifies RevenueCat on device, loads couple | Slow or offline first launch waits for auth and network |
| No invite | Bond/BondApp.swift:398-418 | Routes to IntentSetupView solo mode | Several questions precede the first reminder |
| Invite deep link | PairingService.swift:272-295 and InviteWelcomeView.swift:38-124 | Holds code for anonymous user, asks Sign in with Apple, consumes invite | Abandoning Set up on my own clears the deferred code with no recovery affordance |
| Solo setup | IntentSetupView.swift:131-159 and :420-557 | Name, commitment, love language, focus areas | Love language can be empty; focus area is required |
| Trial step | IntentSetupView.swift:222-417 | Yearly-first direct purchase, free Bond path, restore, terms, privacy | Pending purchase is treated as complete; copy is less complete than full paywall |
| Solo finish | IntentSetupView.swift:559-571 and PairingService.swift:107-142 | Creates solo couple through RPC, retries schema-cache error once | A backend error appears late after the user invested in setup |
| First home | ReminderListView.swift:28-105 | Empty state has starter chips and template entry; notification primer may appear | Primer plus post-onboarding paywall can stack |
| Pairing | PairingView.swift and PairingService.swift:151-234 | Six-character invite code, share link, polling, manual entry, success screen | Landing page host label differs from generated host; partner delivery still incomplete |
| Gate | DailyCheckInView, StatsView, ReminderTemplatesView, ReminderEditorView | Teasers or paywall sheets for premium features | Multiple gate sources have different copy and state handling |

### Positive conversion foundations

- EmptyRemindersView has starter chips tailored to focus areas and a Browse templates entry at Bond/Features/ReminderList/EmptyRemindersView.swift:41-110.
- PairingSuccessView is dismissible and gives a readable emotional success moment at Bond/Features/Pairing/PairingSuccessView.swift:12-61.
- The trial step offers a free Bond path, Restore Purchases, and legal links at IntentSetupView.swift:250-306.
- Premium gates use sample content instead of a blank wall in Bond/DesignSystem/PremiumGate.swift and Bond/DesignSystem/GateSampleContent.swift.
- Daily Check-In gives paired free users the real question before gating the answer flow at Bond/Features/CheckIn/DailyCheckInView.swift:39-55. This is a strong value-preview pattern to test against a full lock.

### Detours and bad states to test

1. Offline or slow bootstrap: RootView has a retry state at Bond/BondApp.swift:181-195 and :326-340, but the delay to that state should be measured.
2. Product fetch empty: PaywallView has loading and empty states at Bond/Features/Paywall/PaywallView.swift:49-126, but IntentSetup can fall into a fallback paywall and finish on dismissal at IntentSetupView.swift:211-218.
3. Pending purchase: BOND-01.
4. Ineligible trial: verify CTA, disclosure, and price never promise a trial.
5. Notification primer: verify the system permission result is reflected and that the following paywall is not shown as a second interruption without a value event.
6. Check-in request failure: DailyCheckInService sets lastError, but DailyCheckInView does not render a retry state. Add a visible retry test.
7. Location denied: ReminderEditorView shows an inline localized error from LocationService, but scheduling errors are ignored afterward.
8. Partner target with profile unavailable: ReminderEditorView falls back to me when partnerProfile is missing at Bond/Features/ReminderEditor/ReminderEditorView.swift:368-372. A visible partner picker combined with a silent self-target is a data and trust risk.
9. Template bulk insert failure: the detail view does show an error at ReminderTemplatesView.swift:188-246, but end-to-end notification scheduling after bulk insert should be verified.
10. Watch queued state: WatchConnectivitySender distinguishes confirmed, queued, and failed at BondWatch/WatchConnectivitySender.swift:14-21 and DictateView.swift:51-67. The queued state must eventually confirm or expire, and the one-hour self or partner behavior must be explicit.
11. Sign out and unpair: Settings clears notifications and widget snapshots at SettingsView.swift:221-267. Verify no previous-account data remains in widgets, cached views, realtime, or purchase state.
12. Review prompt after an error: BOND-08.

## Paywalls, native knobs, and A/B test plan

### Current paywall surfaces

| Surface | Impression ID or entry | Evidence | Notes |
|---|---|---|---|
| Solo in-flow trial | onboarding_personalized_plan | IntentSetupView.swift:353-363 | One-tap yearly-first purchase |
| Solo fallback | onboarding_trial_fallback | IntentSetupView.swift:211-218 | Full flow appears if offering is unavailable |
| Post-onboarding | post_onboarding | BondApp.swift:296-318 | Queued behind notification primer |
| Post-pairing | post_pairing | BondApp.swift:163-176 and :286-290 | High-intent pairing success |
| Feature gates | gate-specific or caller-supplied | PaywallModifier.swift, PremiumGate.swift, feature views | Entry point varies by feature |
| Full native plan picker | custom native PaywallView | PaywallView.swift:49-429 | Yearly, monthly, lifetime if live offering contains it |

### Available native and remote knobs

- The selected offering is identifier default, then current, at Bond/Features/Paywall/PaywallPackage+Bond.swift:173-178.
- Package ordering uses lifetime, yearly, monthly classification at PaywallPackage+Bond.swift:1-42 and :93-170.
- Yearly is preselected in PaywallView and the onboarding trial package at PaywallView.swift:349-366 and IntentSetupView.swift:367-369.
- RevenueCat intro eligibility is checked only for products with an introductory discount at PurchasesService.swift:120-140.
- The compact TrialOfferSheet can transition to the full PaywallView when the selected trial package is ineligible or absent at PaywallFlowSheet.swift:43-58.
- BondPlusBenefits has separate solo and paired benefit inputs. This supports audience-specific paywall copy.
- PaywallScreenshotMode supports trial, monthly, yearly, and lifetime preview states at Bond/Utilities/PaywallScreenshotMode.swift:1-12.

### Experiment backlog

Do not run these until BOND-01, BOND-03, and BOND-06 are fixed.

1. Timing: in-flow trial page versus compact sheet after first reminder versus post-pairing sheet.
2. Interruption: notification primer followed by a value action versus notification primer followed by paywall.
3. Default plan: yearly first versus monthly first versus a lifetime anchor, with equivalent legal copy.
4. Trial framing: one-tap trial CTA versus See all plans first. Separate eligible and ineligible cohorts.
5. Benefit order: personalized reminders first, partner check-in first, or notifications and delivery first.
6. Gate design: preview content plus unlock card versus blurred preview plus unlock card. The current Daily Check-In preview is a good control.
7. CTA language: Try Bond+ Free, Start your 7-day trial, or Unlock your plan. Use typed eligibility and never show trial language to ineligible users.
8. Paywall entry context: feature-specific headline versus generic Bond+ headline.
9. Legal reassurance: full renewal timing and Store settings copy in the compact sheet versus short copy with a details link.
10. Native plan card: selected state, savings explanation, and price-per-period presentation.
11. Pairing: immediate paywall after pairing versus first shared reminder creation.
12. App Store product page: first screenshot hero about reminders versus check-in or partner delivery, and promo text trial framing versus daily ritual framing.

Required experiment fields: assignment, source, product ID, package kind, trial eligibility, paywall version, app version, build, onboarding path, paired state, locale, exposure timestamp, CTA tap, purchase result, entitlement result, and seven-day trial activation if available. Avoid interpreting a paywall impression without a denominator.

## RevenueCat integration, custom attributes, and events

### Current behavior

- Device builds configure the production RevenueCat public key, while simulator builds return before RevenueCat calls at PurchasesService.swift:49-64.
- Bootstrap refreshes customer info, fetches offerings, checks intro eligibility, and starts the customer-info stream at PurchasesService.swift:66-81.
- The only RevenueCat custom tracking call is trackCustomPaywallImpression at PurchasesService.swift:142-156.
- identify logs in the Supabase user UUID at PurchasesService.swift:312-325. This is an account identifier, not a recommended custom attribute value to duplicate without a clear operational need.
- Purchase and restore behavior is at PurchasesService.swift:159-356.
- The broad premium resolution is at PurchasesService.swift:363-400 and is covered by BOND-14.

### Recommended attributes and exact insertion points

Only set non-PII, low-cardinality values. Never send partner names, reminder titles, reminder bodies, check-in answers, precise locations, or free-form user content.

| Attribute | Value | Insert after or near | Why |
|---|---|---|---|
| app_version | CFBundleShortVersionString | PurchasesService.identify success, around :317-319 | Segment entitlement issues by release |
| build | CFBundleVersion | same location | Pin regressions to an exact build |
| onboarding_path | solo or invitee | When IntentSetupView is initialized, around :156-159, or before first paywall impression at :353-363 | Compare conversion paths |
| pairing_status | solo, paired, or pending | After RootView pairing load at BondApp.swift:242-247 and after pairing success | Explain paired versus solo value |
| focus_area_count | integer 0 to 4 | On leaving focusAreasStep at IntentSetupView.swift:326-350 | Compare personalization depth |
| love_language_count | integer 0 to 5 | On leaving loveLanguageStep at IntentSetupView.swift:326-350 | Detect zero-selection path |
| notification_permission_status | not_determined, authorized, denied, provisional | After primer result at ReminderListView.swift:70-83 | Relate reminders to permission outcomes |
| first_value_state | none, started, saved, scheduled, completed | At ReminderEditorView.swift:470-478 and ReminderListView.swift:477-480 | Measure activation |
| paywall_source | the existing impression ID | In trackPaywallImpression at PurchasesService.swift:142-156 | Join exposure to purchase |
| selected_package_kind | monthly, yearly, lifetime | Immediately before purchase at PurchasesService.swift:159-173 | Compare plan choice |
| trial_eligibility | eligible, ineligible, unknown | After refreshIntroEligibility at PurchasesService.swift:120-140 | Explain CTA variants |
| entitlement_resolution | named, other_entitlement, active_subscription, known_product, none | In apply and hasActivePremium at PurchasesService.swift:378-399 | Detect mapping fallbacks |

Verify the exact RevenueCat 5.67.0 attribute API before implementation. If custom attributes are not the right reporting surface for event-level data, keep attributes for the stable dimensions and send event aggregates through the project's chosen analytics or backend event table.

### Recommended event insertion points

| Event | Exact insertion point | Required fields |
|---|---|---|
| paywall_impression | Existing trackPaywallImpression at PurchasesService.swift:142-156 | source, version, build, paired state |
| product_fetch_started/succeeded/empty/failed | fetchProducts at PurchasesService.swift:97-118 | offering identifier, count, error class |
| intro_eligibility_resolved | refreshIntroEligibility at :120-132 | product ID, status |
| purchase_started | Immediately before Purchases.shared.purchase at :168-173 | source, product ID, kind, eligibility |
| purchase_cancelled/failed | Purchase error and result branches at :174-209 and :211-217 | source, product ID, error class |
| purchase_pending | Before return .pending at :234-245 | pending duration, product ID |
| entitlement_active | apply at :391-400 | resolution source, active entitlement count |
| restore_started/succeeded/failed | restore at :342-355 | source, result |
| entitlement_mismatch | hasActivePremium when the named entitlement is not the source | named entitlement state, fallback source |
| gate_viewed/gate_tapped | BondUnlockCard and PaywallModifier entry points | feature, source, paired state |

## Ratings and review funnel

Current funnel:

1. BondApp records app launch at Bond/BondApp.swift:29-30.
2. Reminder completion records a positive moment and posts a signal at ReminderListView.swift:466-480.
3. ReviewPromptTracker gates on setup, launch count, first-open age, three positive moments, and cooldown at Shared/Services/ReviewPromptTracker.swift:110-138.
4. The enjoyment sheet asks whether the user is enjoying Bond at ReviewPromptSheet.swift:94-127.
5. Positive users see an external App Store write-review link at ReviewPromptSheet.swift:129-155.
6. Negative users get a feedback mail draft at ReviewPromptSheet.swift:170-227.
7. Settings exposes Rate or Send Feedback at SettingsView.swift:181-190.

What is good:

- The prompt avoids cold launch, onboarding, pairing, and paywall contexts in the documented design at docs/review-prompt.md:11-22.
- The threshold is conservative in release builds.
- The external link is storefront-aware, subject to the deprecated API in BOND-10.
- There is a feedback route for users who are not enjoying the product.

What to improve:

- Fix BOND-08 before optimizing timing.
- Add a completion-success condition before recording a positive moment.
- Track prompt exposure, selected branch, external link open attempt, feedback draft attempt, and native prompt request. Treat the actual star rating as unavailable unless a permitted reporting source provides it.
- Consider prompting after the first successful reminder completion and after the user has received or completed a partner-delivered reminder, not only after a local tap. Use the measured first-value event.
- Do not invoke native requestReview as an immediate follow-up to Maybe later without a separate timing rationale and test.
- Keep the manual Settings route, but make the copy distinguish rating from private feedback.

## Feature and UX detail

### Reminders

- EmptyRemindersView gives tailored starter chips and a template route, which is a good first-value affordance.
- ReminderEditorView supports one-time, recurring, location, and random-window triggers. Premium gating happens when the picker changes and again on save at ReminderEditorView.swift:72-95 and :361-377.
- Partner selection falls back to self if partnerProfile is missing at :368-372. Fail closed with a pairing retry rather than silently changing recipient.
- Scheduler only schedules self-targeted reminders at NotificationScheduler.swift:46-51.
- Scheduler ignores add failures at :202-224. Add an observable scheduling result.
- The watch can create one-time reminders with a default one-hour offset at BondWatch/WatchConnectivitySender.swift:31-41. This is useful for activation but should be labeled as a shortcut, not a full reminder editor.

### Daily Check-In

- Solo users see a clear For Couples Only state at DailyCheckInView.swift:57-63.
- Paired nonpremium users see the real question and a gate at :39-55.
- Premium users get answer entry and reveal with Reduce Motion handling at :65-100 and :146-185.
- DailyQuestionService uses a deterministic UUID seed and stable ordering at DailyCheckInService.swift:34-50. This fixes the older archive/MVP_TRIAGE issue that claimed random String.hashValue behavior. The old report should be marked resolved, not reused as current evidence.
- Error handling remains weak because lastError is not surfaced by the view.

### Milestones and Insights

- Milestones are currently a free visible tab with empty state, list, editor, and local notifications at MilestonesView.swift:8-75 and MilestoneEditorView.swift:18-80.
- Stats/Insights is premium-gated, but free users see a streak teaser and an unlock card at StatsView.swift:14-56.
- claude-design/PRODUCT.md:18-26 still calls Milestones premium. docs/index.html:525 and the current app position milestones in the free tier. Resolve the product decision and align copy.
- Stats uses Charts and includes loading-by-absence rather than a dedicated request error state. Add retry and an empty-data explanation after a failed refresh.

### Templates

- Free users see the complete group list as a teaser and a Bond+ unlock card at ReminderTemplatesView.swift:8-65.
- Premium users can add a staggered pack at ReminderTemplatesView.swift:188-246.
- Validate that bulk inserts trigger a fresh notification schedule and widget snapshot. The current detail view reports insert failure, which is a good baseline.

### Pairing

- Pairing uses a six-character code, share link, QR, manual entry, expiry, and polling at PairingService.swift:151-234 and PairingView.swift.
- Universal link generation uses jackwallner.com, while site copy says bond.jackwallner.com. This is BOND-07.
- PairingSuccessView gives a readable explicit Continue button and accessibility announcement. Keep the success moment, but measure whether the subsequent paywall or a first shared reminder converts better.

## Website, legal, support, and product consistency

| Claim or surface | Evidence | Current issue or action |
|---|---|---|
| Canonical landing page | docs/index.html:8-22 | Uses jackwallner.com canonical but GitHub Pages image URLs; choose one public source |
| App Store link | docs/index.html:58 and :65 | Correct app ID 6768514177; test every locale link if region-specific links are desired |
| Software version | docs/index.html:60 | 1.0.5 matches project.yml marketing version |
| Price JSON-LD | docs/index.html:30-54 | $2.99, $19.99, $39.99; align with verified live and fixture products |
| Lifetime | docs/index.html:50-53, docs/terms.html:104-117 | Site and terms advertise lifetime; StoreKit fixture lacks it |
| Free tier | docs/index.html:524-530 | Site says core reminders and milestones are free; current MilestonesView is free, while stale design docs say premium |
| Pairing | docs/index.html:539 and PairingService.swift:31-37 | Site host is wrong; generated host is jackwallner.com |
| First value | docs/index.html:478-500 | Under a minute is a testable claim, not a measured result in this repository |
| Support | docs/support.html:17-48 | Date is older and lifetime purchase is not explained |
| Legal dates | docs/privacy-policy.html:86-87, docs/terms.html:86-87 | Updated Aug 17, 2026 |
| Sitemap | docs/sitemap.xml:3-21 | All lastmod values are May 26, 2026 |
| Duplicate routes | docs/privacy-policy.html plus docs/privacy/index.html, same for terms and support | Hashes differ; use one generated source or compare at build time |
| Release sync | .github/workflows/sync-landing-page.yml:1-56 | Portfolio mirror is current process, contrary to older README and CLAUDE instructions |

The requested RevenueCat data-collection disclosure comparison is intentionally omitted.

## Agent workspace and documentation hygiene

### Current state

- AGENTS.md is a symlink to CLAUDE.md. Preserve the symlink relationship rather than creating a second contradictory instruction file.
- CLAUDE.md:3 references memory project_bond.md, which is not present in the repository.
- CLAUDE.md:6-13 describes GitHub Pages ownership and says the App Store ID must be set before launch, but the app has an ID and the current workflow mirrors to the portfolio site.
- README.md:8 and :37-43 says Supabase, reminder editor, APNs, Watch dictation, StoreKit, and premium gates are not wired, but current source contains all of these except client APNs registration.
- README.md:20-24 uses a generic named simulator command that does not match the headless fleet convention.
- README.md:63-81 describes an old site publish script not present under scripts and labels APNs future work.
- docs/MVP_TRIAGE.md is a useful historical audit, but it says there is no Settings screen, standard RevenueCat paywall, unstable Daily Check-In, and no notification primer. Current code has Settings, a custom paywall, deterministic questions, and a notification primer. Its push findings remain relevant.
- ios27Bond.md is a useful dated compatibility audit. Its deprecated API findings remain current until migrated.
- docs/review-prompt.md is current enough to keep, but should be updated when review timing changes.
- archive/README.md correctly says archive files are historical. README and CLAUDE must become accurate before they can be the current source of truth.
- claude-design and claude-design-handoff contain source snapshots that disagree with current app structure, fonts, settings, paywall, and screenshot count.
- .git/cursor contains internal Cursor index data, not a human-maintained Cursor ruleset. No .cursor/rules directory was found.

### Keep, update, archive, and move classification

| Classification | Files or folders | Action for implementation agent |
|---|---|---|
| Keep as current and enforce | project.yml, fastlane/Fastfile, fastlane/Deliverfile, scripts, Bond source, Shared source, BondWatch, BondWidgets, BondTests | Keep as executable source; add scanner and test ownership |
| Keep with update | CLAUDE.md, AGENTS.md symlink, README.md, docs/review-prompt.md, ios27Bond.md | Remove stale claims, add current build/version, canonical URLs, release-watch commands, and links to this audit |
| Keep as generated site source, consolidate | docs/index.html, legal pages, support pages, clean-route copies, robots.txt, sitemap.xml | Choose a single source and generate or verify copies |
| Archive after status review | docs/MVP_TRIAGE.md, archive/PLAN.md, archive/VIDEO_DEBUG_NOTES.md, archive/c521.md, archive/g521.md, archive/uc528.md, archive/v516.md | Preserve dates and mark resolved versus open findings; do not let agents treat them as current |
| Move to dated ASO archive or convert to an active plan | aso-plan.md, docs/localization-aso.md, docs/astro-aso-setup.md | Add status, last verified ASC version, and a link to the current metadata report. Move completed May and June plans under docs/archive/aso/ |
| Archive as design snapshots | claude-design, claude-design-handoff | Add snapshot date and source commit if retained. Do not expose code-references as current source |
| Move or delete from agent-visible workspace | .DS_Store files and stale design snapshot source copies | Keep only if needed for a visual handoff. Otherwise remove from agent context in a separate cleanup change |
| Create one canonical agent state document | Recommended docs/agent/current-state.md | Record targets, bundle IDs, current version, services, product IDs, feature gates, release commands, site source, known issues, and last verification date |

### Recommended canonical Cursor, Claude, and Codex layout

Use one factual source and thin tool-specific adapters:

    bond/
      AGENTS.md                         canonical project instructions
      CLAUDE.md -> AGENTS.md            Claude and Codex compatibility symlink
      .cursor/
        rules/
          00-bond-project.md            short Cursor rule or generated link
      docs/
        agent/
          current-state.md              factual source of truth
          release-checklist.md
          scanner-rules.md
          archive/
            YYYY-MM-DD-<topic>.md
      audit823.md

The canonical instructions should state:

- What is current, with version and date.
- Which file is authoritative for product, metadata, site, legal, and release facts.
- How to run XcodeGen, the headless simulator pool, unit tests, StoreKit fixture tests, and the static scanner.
- How to avoid production RevenueCat configuration on simulators.
- How to validate pending, restore, notification, pairing, and offline states.
- Which docs are historical and should not be used for implementation decisions.

The Cursor rule should be concise and point to current-state.md, not duplicate the whole project guide. Claude and Codex should load AGENTS.md and use the same factual document. Any generated adapter must fail or visibly warn when the source date is stale.

## Release regression and deprecated UX signals

### Static signals already visible

| Signal | Path | Why it matters |
|---|---|---|
| Supabase realtime deprecation | Bond/Services/ReminderRepository.swift:99-117 | Partner reminder refresh can break after package or OS update |
| StoreKit storefront deprecation | Shared/Utilities/AppStoreReviewLinks.swift:25-30 | Review link can fall back to an incorrect storefront |
| Purchase pending | Bond/Services/PurchasesService.swift:219-245 and IntentSetupView.swift:407-413 | User-facing entitlement state can diverge |
| Empty offerings | PurchasesService.swift:97-118, PaywallView.swift:49-126 | Trial and revenue path can disappear |
| Silent schedule errors | NotificationScheduler.swift:115-120 and :202-224 | App can claim a saved reminder without a scheduled notification |
| Missing APNs client path | Bond app search plus SupabaseFunctions/send-push | Partner delivery can fail without a visible app error |
| Realtime child task not retained | ReminderRepository.swift:113-117 | Subscription task has no stored cancellation handle |
| Silent completion write | ReminderListView.swift:477-480 | Review and completion metrics can count failed writes |
| Stale product fallback | scripts/asc_lib.py:248-255 | Upload automation can inject unrelated copy |
| Named CI simulator | .github/workflows/ci.yml:31-50 | CI may not represent the fleet runtime |
| Fixed paywall layout | PaywallView.swift:129-175 | Large text and localized price states can clip |
| No in-app localization resources | repository-wide file search | ASC localization does not localize runtime UI |

### Release-watchdog signals

The future Mac watchdog should support configurable source adapters and thresholds. Suggested defaults are starting points, not measured fleet baselines:

| Signal | Trigger | Urgency | Minimum context |
|---|---|---|---|
| Crash spike | Current release crash-free users or sessions drops below a configured floor, or crash count is at least 2x the rolling baseline with at least 3 affected devices | Immediate | version, build, OS, model, symbolicated top frames |
| Hang or launch stall | Launch or bootstrap exceeds 15 seconds, or a hang sample appears on at least 3 devices in a release window | Immediate | stage, duration, OS, build |
| Trial purchase pending | More than 3 pending purchases or pending rate above a configured percentage over 30 minutes | Immediate | source, product ID, eligibility, entitlement delay |
| Entitlement mismatch | Any fallback unlock source appears after the named entitlement is absent | Immediate | RC customer hash, product, offering, resolution source |
| Empty offering | Product fetch empty or failed for at least 3 users or for a configured duration | Immediate | offering, region, version, error class |
| Purchase failure | Rate exceeds baseline by 2x, separated by cancellation, network, store, and mapping error | High | source, product, error code |
| Pairing failure | RPC schema, invalid, expired, or consumption failures exceed baseline | High | host, app version, error class |
| Reminder save without schedule | Saved reminder count exceeds schedule success count or local add error count is nonzero | High | trigger, target class, permission |
| APNs delivery | Webhook failure, missing token, APNs 4xx/5xx, or delivery lag exceeds threshold | High | target token hash, environment, response |
| Notification permission | Denied rate increases after a release or primer-to-authorized conversion drops | Medium | primer version, locale, OS |
| Realtime | Channel subscribe failure or reconnect loop occurs | High | couple state, package version |
| Watch | queued messages expire without phone confirmation or send failure rises | Medium | reachability, watchOS, phone build |
| First value | Median or p90 launch-to-first-scheduled-reminder regresses beyond a configured percentage | High | onboarding path, locale, network class |
| Review funnel | Positive moment count rises but prompt eligibility, external open, or feedback events disappear | Medium | threshold state and app version |
| Site and metadata | URL returns non-2xx, canonical drift, stale legal date, or metadata file count/limit mismatch | High before release | path, locale, field |

The watchdog should have a release-window mode covering the first 24 to 72 hours after a build or metadata release, with lower thresholds and more frequent polling. It should send at most one email per incident fingerprint during a cooldown and write all raw observations to a local JSONL or SQLite file for later review. Notification delivery itself is only scaffolded by this audit; no notification system is deployed here.

## Concrete static scanner rules

The fleet scanner requested by the parent workflow can implement these rules without AI. Each result should include rule ID, severity, path, line, observed value, expected value, and remediation hint.

| Rule ID | Check | Failure condition |
|---|---|---|
| META-001 | Required files | Any Deliverfile locale lacks name, subtitle, keywords, description, release_notes, promotional_text, support_url, marketing_url, or privacy_url |
| META-002 | Limits | Name, subtitle, keywords, description, promo, or release notes exceed the configured limit |
| META-003 | No silent truncation | Uploader source contains field slicing without a preceding validation failure |
| META-004 | Locale coverage | Deliverfile languages and metadata directories differ |
| META-005 | Cross-app fallback | Metadata or scripts contain another app name, category, or known fallback string |
| META-006 | Price manifest | Price tokens in metadata, site, StoreKit fixture, screenshot harness, or product docs differ from the checked-in manifest |
| META-007 | Product parity | Product IDs and package kinds differ between code, StoreKit fixture, and optional live ASC/RevenueCat export |
| META-008 | Trial parity | Trial period and eligibility wording differ between onboarding, TrialOfferSheet, PaywallView, site, and ASC copy |
| URL-001 | Canonical host | canonical, og:url, sitemap, robots, ASC URL files, app links, and paywall legal links disagree without an explicit legacy redirect |
| URL-002 | Link health | Any URL returns non-2xx, has an unexpected redirect chain, or has a missing trailing-slash route |
| URL-003 | Pairing host | Generated invite host, AASA host, landing-page copy, and site configuration differ |
| SITE-001 | Duplicate routes | Root and clean-route copies differ in title, canonical, update date, product claims, or legal sections |
| SITE-002 | Freshness | Support or sitemap dates are older than legal source dates or the current release by a configured age |
| SITE-003 | Feature claims | Site, metadata, and screenshots claim a feature whose target is absent or whose known delivery path is disabled |
| PAY-001 | Paywall layout | Paywall contains fixed-height, line-limited purchase or legal text without a tested overflow path |
| PAY-002 | Offer parsing | Trial behavior depends on parsing a formatted display string rather than typed offer data |
| PAY-003 | Pending safety | Any purchase surface routes home or creates account state on pending without entitlement confirmation |
| PAY-004 | Restore | Every purchase surface lacks a visible restore path or a pending recovery path |
| PAY-005 | Impression join | Paywall impression IDs are not attached to plan selection and purchase result |
| RC-001 | Entitlement source | Any broad fallback unlock exists without resolution-source telemetry and an expiry |
| RC-002 | Attribute schema | Required low-cardinality release and funnel dimensions are not set at identify or purchase boundaries |
| NOTIF-001 | Remote path | Partner target exists but no APNs registration and token persistence path is found |
| NOTIF-002 | Silent scheduling | Notification add or authorization errors are swallowed without a user-visible or event-level result |
| NOTIF-003 | Location claim | Location feature copy says arrival or background behavior without a matching authorization and test |
| API-001 | Deprecated APIs | Scan for SKPaymentQueue storefront, old Supabase postgresChange, old subscribe, and compiler deprecation warnings |
| API-002 | Async cancellation | Long-lived Task or realtime stream is created without stored cancellation or view lifecycle ownership |
| DOC-001 | Stale guide | README, CLAUDE, AGENTS, design snapshots, or plans claim missing features that exist in source |
| DOC-002 | Missing references | Any guide links a file, script, host, or memory document that does not exist |
| DOC-003 | Agent source of truth | More than one current instruction document has conflicting commands or product facts |
| ASSET-001 | Screenshot dimensions | Any screenshot is outside the target device dimensions or appears only in an unlisted locale |
| ASSET-002 | Screenshot quality | Transparency, clipped overlay, unreadable text, duplicate frame, or stale price/feature claim |
| ASSET-003 | Video inventory | App Store metadata expects a video but no validated video artifact exists |
| TEST-001 | Critical coverage | No test for purchase pending, restore, onboarding, paywall empty, notification permission, pairing, or offline bootstrap |
| CI-001 | Release targets | CI does not build the app, watch, widget, tests, and metadata scanner from a clean generated project |
| CI-002 | Runtime target | CI uses an unsupported named simulator or runtime that differs from the fleet standard |
| REVIEW-001 | Positive moment | Review signal can be emitted after a failed product action |
| REVIEW-002 | Timing | Native review request occurs immediately after a user declines or postpones an external request |

Suggested non-AI scanner output:

    {
      "app": "bond",
      "release": "1.0.5 (68)",
      "rule": "PAY-003",
      "severity": "P0",
      "path": "Bond/Features/Onboarding/IntentSetupView.swift",
      "line": 409,
      "observed": "pending calls finish",
      "expected": "pending waits for entitlement or explicit recovery",
      "status": "open"
    }

## Validation plan for the implementation agent

### Static preflight

1. Run XcodeGen and fail if the generated project changes unexpectedly.
2. Run the metadata, product manifest, URL, docs freshness, deprecation, screenshot, and scanner rules.
3. Confirm only intended source, docs, and test files are changed.
4. Confirm no production RevenueCat key is used in simulator or StoreKit fixture runs.

### Build and test

1. Build Bond, BondWatch, BondWidgets, and BondTests from a clean generated project.
2. Run existing BondTests and add service tests for PurchasesService, PairingService, DailyCheckInService, NotificationScheduler, and review tracker.
3. Run the StoreKit fixture with monthly, yearly, lifetime, eligible trial, ineligible trial, cancel, pending, and restore cases.
4. Run UI flows on a leased headless simulator from the fleet pool, not a named destination.
5. Run the watch connectivity flow with phone setup missing, phone reachable, phone queued, partner paired, and solo cases.

### Critical user journey matrix

| Journey | Required assertions |
|---|---|
| Cold online solo install | Time to setup, first value, notification primer, free exit, trial offer |
| Cold offline install | Human retry, no infinite spinner, no lost inputs |
| Eligible trial | Correct typed period, Apple sheet, entitlement, home transition |
| Ineligible account | No trial promise, accurate price, full plan choice |
| Pending transaction | Visible pending state, no false completion, later restore |
| Product outage | Retry and free path where intended, no empty dead-end |
| Partner invite | Correct host, sign-in, consume, success, paired data |
| Partner reminder | Server token, webhook, APNs response, receipt, tap route |
| Location reminder | Permission, save, background arrival or explicit limitation |
| Check-in outage | Visible error and retry, no empty gate masquerading as content |
| Dynamic Type | Paywall, onboarding, review, editor, settings, watch |
| Accessibility | VoiceOver plan values and selected states, logical focus, Reduce Motion |
| RTL and localization | Arabic, CJK, German, French, long price and legal copy |
| Release regression | Old account, restore, sign out, unpair, delete, widget clearing |

### Live verification required before decisions

- ASC current version, locale presence, screenshots, product page performance, product page optimization results, downloads, trial starts, and ratings.
- RevenueCat current offering, product IDs, entitlements, intro eligibility behavior, trial conversions, purchase failures, and customer support events.
- App Store crash and hang reports or an approved crash provider.
- Supabase send-push deployment, webhook logs, APNs environment, token freshness, and delivery responses.

## Findings that are already resolved in current source but stale in docs

These are important to prevent an implementation agent from redoing old work:

- Daily Check-In now uses a stable UUID seed and ordered query at DailyCheckInService.swift:34-50. The unstable String.hashValue report in docs/MVP_TRIAGE.md:63-69 is historical.
- Settings exists with account, restore, privacy, terms, support, notification, unpair, and delete controls at Bond/Features/Settings/SettingsView.swift:1-285. The no-settings claims in docs/MVP_TRIAGE.md:74-75 and claude-design/INVENTORY.md:25-36 are stale.
- The custom PaywallView and TrialOfferSheet replace the old RevenueCatUI default description. claude-design/README.md:17-27 and INVENTORY.md:19-20 are stale.
- NotificationPrimerSheet exists and is integrated at ReminderListView.swift:63-105. Older no-primer claims in docs/MVP_TRIAGE.md:104-106 are stale.
- Watch connectivity now returns confirmed, queued, or failed and has a background application-context handler at BondWatch/WatchConnectivitySender.swift:14-21 and Bond/Services/WatchConnectivityBridge.swift:136-156. Old silent-drop claims should be re-tested, not assumed current.
- Template creation now staggers reminder dates and reports bulk insert errors at ReminderTemplatesView.swift:188-246. The old all-at-once claim in docs/MVP_TRIAGE.md:60-61 is stale.
- The current code contains Supabase, StoreKit, premium gates, watch dictation, widgets, and a full reminder editor. README.md:8 and :37-43 is not a current project status.

## Evidence limitations and handoff boundaries

- This is a local repository audit. It does not establish live downloads, conversion, revenue, rating, crash, trial, ASC, RevenueCat, APNs, or site uptime values.
- Historical git commit text is useful context but is not a current metric source.
- Static inspection cannot prove background notification delivery, universal-link association, purchase entitlement propagation, or the correctness of translated copy. Those require the validation matrix and live service checks.
- The app's public RevenueCat disclosure wording was intentionally excluded from this audit per request.
- No source code, configuration, metadata, site page, test, commit, upload, notification, or external service was changed by this audit. The only intended repository artifact is this audit file.

## Implementation handoff

Start with BOND-01, BOND-02, and BOND-03. Then implement the event schema and scanner before selecting an A/B test. Use the scanner as the release gate, and use the watchdog only after each signal has a real source, a baseline, a minimum-count threshold, a cooldown, and a runbook link.

## Activity and success context, 2026-08-23

Classification: **traffic without monetization**. Confidence: **medium**. Trend: **no ASC comparison displayed**.

ASC release state: `iOS 1.0.5 Ready for Distribution`. ASC evidence: [Analytics Overview](https://appstoreconnect.apple.com/apps/6768514177/analytics/overview?dateSpec=d90), selected range `dateSpec=d90`.
RevenueCat evidence: [Project Overview](https://app.revenuecat.com/projects/4e53c2c5/overview), production mode, selected range `Last 28 days, 2026-07-27 through 2026-08-23`.

### Observed activity

| Source | Metric | Value | Window or comparison |
| --- | --- | ---: | --- |
| ASC | first-time downloads | 34 | 90-day Analytics Overview |
| ASC | redownloads | 1 | 90-day Analytics Overview |
| ASC | conversion rate | 0.8% | comparison not displayed |
| ASC | proceeds | not available | 90-day Analytics Overview |
| ASC | in-app purchases | not available | 90-day Analytics Overview |
| RevenueCat | new customers | 24 | last 28 days |
| RevenueCat | active customers | 47 | last 28 days |
| RevenueCat | active trials | 0 | current total |
| RevenueCat | active subscriptions | 0 | current total |
| RevenueCat | MRR | $0 | current total |
| RevenueCat | revenue | $0 | last 28 days |

A missing value above means the source did not expose that metric in this read-only snapshot. It is not a zero.

### Interpretation and implementation focus

Bond has real traffic, 34 ASC first-time downloads and 24 RevenueCat new customers, but no active trials, subscriptions, MRR, or RevenueCat revenue in the current window. That is evidence of an activation or offer problem, not evidence that the app is dead. The first implementation pass should make the first relationship value moment measurable, confirm that the native paywall loads with an eligible product, and test a free-first path before changing price.

The deterministic classifier recommends: Treat this as an activation and offer problem until a mature paid cohort appears. Verify the free-to-trial path and product loading.

- Join ASC first-time download, first launch, first value, paywall shown, offer loaded, trial started, trial canceled, trial converted, entitlement active, restore, and purchase failure events with the app version and build.
- Keep ASC's 90-day acquisition and proceeds window separate from RevenueCat's 28-day customer and revenue window. Do not calculate a conversion rate by dividing values from different windows.
- Use a mature trial cohort and a minimum sample before choosing a native paywall or onboarding A/B winner. Record the offering identifier, package, placement, experiment variant, and build.
- Put the app's classification and the next baseline date in the release handoff so Cursor, Claude, and Codex do not optimize from an old qualitative audit.

### Boundary on success or death

This snapshot supports the label **traffic without monetization**, not a lifetime verdict. The app has downloads or new customers, but no current paid signal was supplied. A later decision should include a clean 28-day RevenueCat trend, ASC acquisition and conversion trend, ratings and review count, crash and hang evidence, and a release-specific cohort.
This dated section supersedes earlier statements in this file that per-app ASC or RevenueCat activity was unavailable as of 2026-08-23. Earlier statements remain historical evidence boundaries for their original audit pass.
