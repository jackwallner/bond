# Release gate: bond-ship 63045884dbd0

Verdict: **BLOCK** (2026-11-01T17:26:49+00:00)

Every finding blocks except legacy backlog. `qa-gate fix <repo>` fixes them. Motion candidates need a judgement in the ledger: `qa-gate ledger <repo> accept` for an intended change, or `add` a P1 when it is a real glitch.

## Blocking (8)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P1 | overlap | newcomer | test02EveryTabOnSeededData / reminders | button "Book dinner at Lucia's, Sam's been wanting to try it., in 3 days, for partner" overlaps "bell.fill" by 60% | `overlap|test02EveryTabOnSeededData|reminders|book dinner at lucia's, sam's been wanting to try it., in # ` |
| P1 | truncated | newcomer | test02EveryTabOnSeededData / insights | text drawn as "¡ell sam one tning you a..." but reads "Tell Sam one thing you appreciate" | `truncated|test02EveryTabOnSeededData|insights|tell sam one thing you appreciate` |
| P1 | overlap | newcomer | test03ReturnVisitWithInterruption / reminders-after-relaunch | button "Book dinner at Lucia's, Sam's been wanting to try it., in 3 days, for partner" overlaps "bell.fill" by 60% | `overlap|test03ReturnVisitWithInterruption|reminders-after-relaunch|book dinner at lucia's, sam's been wanting to try it., in # ` |
| P1 | overlap | newcomer | testCoreLoopAddThenMarkGestureDone / core-home | button "Book dinner at Lucia's, Sam's been wanting to try it., in 3 days, for partner" overlaps "bell.fill" by 60% | `overlap|testCoreLoopAddThenMarkGestureDone|core-home|book dinner at lucia's, sam's been wanting to try it., in # ` |
| P1 | clipped | newcomer | testCoreLoopAddThenMarkGestureDone / core-added | text drawn as "Wh" but reads "When", cut off with no ellipsis | `clipped|testCoreLoopAddThenMarkGestureDone|core-added|when` |
| P0 | journey-broken | accessibility | testCoreLoopAddThenMarkGestureDone /  | XCTAssertTrue failed - saved reminder is not listed | `journey-broken|testCoreLoopAddThenMarkGestureDone` |
| P0 | journey-broken | duo | test02EveryTabOnSeededData /  | Failed to tap "Insights" Button: No matches found for Elements matching predicate '"Insights" IN identifiers' from input {(
    Button, identifier: 'bell.fill', label: 'Reminders',
    Button, identifier: 'questionmark.bubble.fill', label: 'Check-In',
    Button, identifier: 'calendar', label: 'Milestones', Selected,
    Button, identifier: 'gearshape.fill', label: 'Settings'
)} | `journey-broken|test02EveryTabOnSeededData` |
| P0 | journey-broken | duo | testCoreLoopAddThenMarkGestureDone /  | XCTAssertTrue failed | `journey-broken|testCoreLoopAddThenMarkGestureDone` |

## Needs a judgement (0)

None.

## Legacy backlog, warns until fixed (109)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / partner-name | Contrast failed (measured 2.6:1): "Continue" | `a11y-contrast|test01OnboardingToTrialAndHome|partner-name|continue` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / partner-name | Contrast nearly passed (measured 3.7:1): "Have an invite from your partner?" | `a11y-contrast|test01OnboardingToTrialAndHome|partner-name|have an invite from your partner?` |
| P3 | a11y-element-description |  | test01OnboardingToTrialAndHome / partner-name | Element has no description | `a11y-element-description|test01OnboardingToTrialAndHome|partner-name|` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / focus-areas | Contrast failed (measured 3.2:1): "Pick what matters. You can change any of this later." | `a11y-contrast|test01OnboardingToTrialAndHome|focus-areas|pick what matters. you can change any of this later.` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / focus-areas | Contrast failed (measured 3.5:1): "Day-to-day ways to show up." | `a11y-contrast|test01OnboardingToTrialAndHome|focus-areas|day-to-day ways to show up.` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / focus-areas | Contrast failed (measured 3.5:1): "Anniversaries, birthdays, plans." | `a11y-contrast|test01OnboardingToTrialAndHome|focus-areas|anniversaries, birthdays, plans.` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / focus-areas | Contrast failed (measured 3.6:1): "Favorites, hobbies, what they care about." | `a11y-contrast|test01OnboardingToTrialAndHome|focus-areas|favorites, hobbies, what they care about.` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / focus-areas | Contrast failed (measured 3.5:1): "Topics, days, or things that hurt." | `a11y-contrast|test01OnboardingToTrialAndHome|focus-areas|topics, days, or things that hurt.` |
| P2 | a11y-hit-region |  | test01OnboardingToTrialAndHome / onboarding-trial | Hit area is too small: "Continue for free" | `a11y-hit-region|test01OnboardingToTrialAndHome|onboarding-trial|continue for free` |
| P2 | a11y-hit-region |  | test01OnboardingToTrialAndHome / onboarding-trial | Hit area is too small: "Restore Purchases" | `a11y-hit-region|test01OnboardingToTrialAndHome|onboarding-trial|restore purchases` |
| P2 | a11y-hit-region |  | test01OnboardingToTrialAndHome / onboarding-trial | Hit area is too small: "Terms" | `a11y-hit-region|test01OnboardingToTrialAndHome|onboarding-trial|terms` |
| P2 | a11y-hit-region |  | test01OnboardingToTrialAndHome / onboarding-trial | Hit area is too small: "Privacy" | `a11y-hit-region|test01OnboardingToTrialAndHome|onboarding-trial|privacy` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast failed (measured 1.8:1): "$79.99 / year. Auto-renews unless cancelled." | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|$# / year. auto-renews unless cancelled.` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast failed (measured 3.4:1): "Continue for free" | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|continue for free` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast failed (measured 3.3:1): "Restore Purchases" | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|restore purchases` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast failed (measured 1.8:1): "Terms" | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|terms` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast failed (measured 1.8:1): "·" | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|·` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast failed (measured 1.8:1): "Privacy" | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|privacy` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast nearly passed (measured 3.7:1): "Chosen for your setup" | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|chosen for your setup` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast nearly passed (measured 3.5:1): "Start with prompts based on what matters to them." | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|start with prompts based on what matters to them.` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / onboarding-trial | Contrast nearly passed (measured 3.5:1): "See which love languages you act on over time." | `a11y-contrast|test01OnboardingToTrialAndHome|onboarding-trial|see which love languages you act on over time.` |
| P2 | a11y-hit-region |  | test01OnboardingToTrialAndHome / first-home | Hit area is too small: "Maybe later" | `a11y-hit-region|test01OnboardingToTrialAndHome|first-home|maybe later` |
| P3 | a11y-element-detection |  | test01OnboardingToTrialAndHome / first-home | Potentially inaccessible text | `a11y-element-detection|test01OnboardingToTrialAndHome|first-home|` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast nearly passed (measured 3.0:1): "Sam answered" | `a11y-contrast|test02EveryTabOnSeededData|reminders|sam answered` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast failed (measured 2.6:1): "Tap to reveal both answers." | `a11y-contrast|test02EveryTabOnSeededData|reminders|tap to reveal both answers.` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast failed (measured 4.2:1): "The little details count." | `a11y-contrast|test02EveryTabOnSeededData|reminders|the little details count.` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast failed (measured 4.2:1): "Nov 8, 2026 at 5:30 PM" | `a11y-contrast|test02EveryTabOnSeededData|reminders|nov #, # at #:# pm` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast failed (measured 2.2:1): "A small note goes a long way." | `a11y-contrast|test02EveryTabOnSeededData|reminders|a small note goes a long way.` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|test02EveryTabOnSeededData|reminders|done today` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast nearly passed (measured 4.2:1): "in 22 hours" | `a11y-contrast|test02EveryTabOnSeededData|reminders|in # hours` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / reminders | Contrast nearly passed (measured 4.2:1): "Sam's been wanting to try it." | `a11y-contrast|test02EveryTabOnSeededData|reminders|sam's been wanting to try it.` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / check-in | Contrast failed (measured 3.1:1): "Quality Time" | `a11y-contrast|test02EveryTabOnSeededData|check-in|quality time` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / check-in | Contrast nearly passed (measured 3.5:1): "Tap to reveal" | `a11y-contrast|test02EveryTabOnSeededData|check-in|tap to reveal` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / milestones | Contrast nearly passed (measured 4.2:1): "6d" | `a11y-contrast|test02EveryTabOnSeededData|milestones|#d` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / milestones | Contrast nearly passed (measured 4.2:1): "November 8, 2026" | `a11y-contrast|test02EveryTabOnSeededData|milestones|november #, #` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / milestones | Contrast nearly passed (measured 4.2:1): "December 6, 2026" | `a11y-contrast|test02EveryTabOnSeededData|milestones|december #, #` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast failed (measured 2.3:1): "15" | `a11y-contrast|test02EveryTabOnSeededData|insights|#` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast failed (measured 2.2:1): "75%" | `a11y-contrast|test02EveryTabOnSeededData|insights|#%` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast nearly passed (measured 4.2:1): "day streak" | `a11y-contrast|test02EveryTabOnSeededData|insights|day streak` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast nearly passed (measured 4.2:1): "best streak" | `a11y-contrast|test02EveryTabOnSeededData|insights|best streak` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast nearly passed (measured 4.2:1): "done this week" | `a11y-contrast|test02EveryTabOnSeededData|insights|done this week` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast nearly passed (measured 4.2:1): "Most: " | `a11y-contrast|test02EveryTabOnSeededData|insights|most:` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast nearly passed (measured 4.2:1): "Needs attention: " | `a11y-contrast|test02EveryTabOnSeededData|insights|needs attention:` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / insights | Contrast failed (measured 1.8:1): "How evenly your reminders cover the five love languages. 100 means a perfectly even spread; a low score means most of your reminders lean on one or two languages." | `a11y-contrast|test02EveryTabOnSeededData|insights|how evenly your reminders cover the five love languages. # m` |
| P2 | a11y-contrast |  | test02EveryTabOnSeededData / settings | Contrast nearly passed (measured 4.2:1): "Paired" | `a11y-contrast|test02EveryTabOnSeededData|settings|paired` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / milestones-before-interruption | Contrast nearly passed (measured 4.2:1): "6d" | `a11y-contrast|test03ReturnVisitWithInterruption|milestones-before-interruption|#d` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / milestones-before-interruption | Contrast nearly passed (measured 4.2:1): "November 8, 2026" | `a11y-contrast|test03ReturnVisitWithInterruption|milestones-before-interruption|november #, #` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / milestones-before-interruption | Contrast nearly passed (measured 4.2:1): "December 6, 2026" | `a11y-contrast|test03ReturnVisitWithInterruption|milestones-before-interruption|december #, #` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / milestones-after-interruption | Contrast nearly passed (measured 4.2:1): "6d" | `a11y-contrast|test03ReturnVisitWithInterruption|milestones-after-interruption|#d` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / milestones-after-interruption | Contrast nearly passed (measured 4.2:1): "November 8, 2026" | `a11y-contrast|test03ReturnVisitWithInterruption|milestones-after-interruption|november #, #` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / milestones-after-interruption | Contrast nearly passed (measured 4.2:1): "December 6, 2026" | `a11y-contrast|test03ReturnVisitWithInterruption|milestones-after-interruption|december #, #` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast nearly passed (measured 3.0:1): "Sam answered" | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|sam answered` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast failed (measured 2.6:1): "Tap to reveal both answers." | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|tap to reveal both answers.` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast failed (measured 4.2:1): "The little details count." | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|the little details count.` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast failed (measured 4.2:1): "Nov 8, 2026 at 5:30 PM" | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|nov #, # at #:# pm` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast failed (measured 2.2:1): "A small note goes a long way." | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|a small note goes a long way.` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|done today` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast nearly passed (measured 4.2:1): "in 22 hours" | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|in # hours` |
| P2 | a11y-contrast |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | Contrast nearly passed (measured 4.2:1): "Sam's been wanting to try it." | `a11y-contrast|test03ReturnVisitWithInterruption|reminders-after-relaunch|sam's been wanting to try it.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast nearly passed (measured 3.0:1): "Sam answered" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|sam answered` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast failed (measured 2.6:1): "Tap to reveal both answers." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|tap to reveal both answers.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast failed (measured 4.2:1): "The little details count." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|the little details count.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast failed (measured 4.2:1): "Nov 8, 2026 at 5:30 PM" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|nov #, # at #:# pm` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast failed (measured 2.2:1): "A small note goes a long way." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|a small note goes a long way.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|done today` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast nearly passed (measured 4.2:1): "in 22 hours" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|in # hours` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-home | Contrast nearly passed (measured 4.2:1): "Sam's been wanting to try it." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-home|sam's been wanting to try it.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-editor | Contrast nearly passed (measured 3.7:1): "Words of Affirmation" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-editor|words of affirmation` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-editor | Contrast failed (measured 2.0:1): "Acts of Service" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-editor|acts of service` |
| P3 | a11y-audit |  | testCoreLoopAddThenMarkGestureDone / core-added | audit could not run: Invalid target app 30695 | `a11y-audit|testCoreLoopAddThenMarkGestureDone|core-added|` |
| P3 | a11y-audit |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | audit could not run: Invalid target app 30958 | `a11y-audit|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done|done today` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done | Contrast nearly passed (measured 4.2:1): "Sam's been wanting to try it." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done|sam's been wanting to try it.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done | Contrast nearly passed (measured 4.2:1): "in 3 days" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done|in # days` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done | Contrast nearly passed (measured 4.2:1): "in 1 week" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done|in # week` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done | Contrast nearly passed (measured 4.2:1): "1" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done|#` |
| P3 | a11y-element-description |  | testCoreLoopAddThenMarkGestureDone / core-done | Element has no description | `a11y-element-description|testCoreLoopAddThenMarkGestureDone|core-done|` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done-after-relaunch | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done-after-relaunch|done today` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done-after-relaunch | Contrast nearly passed (measured 4.2:1): "Sam's been wanting to try it." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done-after-relaunch|sam's been wanting to try it.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done-after-relaunch | Contrast nearly passed (measured 4.2:1): "in 3 days" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done-after-relaunch|in # days` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done-after-relaunch | Contrast nearly passed (measured 4.2:1): "in 1 week" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done-after-relaunch|in # week` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-done-after-relaunch | Contrast nearly passed (measured 4.2:1): "1" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-done-after-relaunch|#` |
| P3 | a11y-element-description |  | testCoreLoopAddThenMarkGestureDone / core-done-after-relaunch | Element has no description | `a11y-element-description|testCoreLoopAddThenMarkGestureDone|core-done-after-relaunch|` |
| P2 | truncated |  | test01OnboardingToTrialAndHome / commit | button drawn as "I commit to showing up fo..." but reads "I commit to showing up for Sam" (AX3 text only) | `truncated|test01OnboardingToTrialAndHome|commit|i commit to showing up for sam` |
| P2 | truncated |  | test01OnboardingToTrialAndHome / first-home | text drawn as "Little Gestures is s..." but reads "Little Gestures is silent without your permission." (AX3 text only) | `truncated|test01OnboardingToTrialAndHome|first-home|little gestures is silent without your permission.` |
| P2 | truncated |  | test01OnboardingToTrialAndHome / first-home | text drawn as "notifications. No noti..." but reads "Reminders fire as notifications. No notifications, no reminders. That's the whole app." (AX3 text only) | `truncated|test01OnboardingToTrialAndHome|first-home|reminders fire as notifications. no notifications, no remind` |
| P2 | blank-launch |  | test02EveryTabOnSeededData / reminders | blank screen for 1.5s after the springboard zoom (simulator timing; a device is faster, the order of events is the same) | `blank-launch|test02EveryTabOnSeededData|reminders|` |
| P2 | blank-launch |  | test03ReturnVisitWithInterruption / reminders-after-relaunch | blank screen for 1.6s after the springboard zoom (simulator timing; a device is faster, the order of events is the same) | `blank-launch|test03ReturnVisitWithInterruption|reminders-after-relaunch|` |
| P2 | blank-launch |  | testCoreLoopAddThenMarkGestureDone / core-home | blank screen for 1.6s after the springboard zoom (simulator timing; a device is faster, the order of events is the same) | `blank-launch|testCoreLoopAddThenMarkGestureDone|core-home|` |
| P3 | a11y-audit |  | test01OnboardingToTrialAndHome / partner-name | audit could not run: Invalid target app 38094 | `a11y-audit|test01OnboardingToTrialAndHome|partner-name|` |
| P2 | a11y-hit-region |  | test01OnboardingToTrialAndHome / first-home | Hit area is too small: "Browse templates" | `a11y-hit-region|test01OnboardingToTrialAndHome|first-home|browse templates` |
| P2 | a11y-contrast |  | test01OnboardingToTrialAndHome / first-home | Contrast nearly passed (measured 3.4:1): "Add one with the + button, or start with these." | `a11y-contrast|test01OnboardingToTrialAndHome|first-home|add one with the + button, or start with these.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast nearly passed (measured 3.0:1): "Sam answered" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|sam answered` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast failed (measured 2.6:1): "Tap to reveal both answers." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|tap to reveal both answers.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast failed (measured 4.2:1): "The little details count." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|the little details count.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast failed (measured 4.2:1): "Nov 8, 2026 at 5:30 PM" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|nov #, # at #:# pm` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast nearly passed (measured 4.2:1): "in 59 minutes" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|in # minutes` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast failed (measured 2.2:1): "A small note goes a long way." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|a small note goes a long way.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|done today` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added | Contrast nearly passed (measured 4.2:1): "in 22 hours" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added|in # hours` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast nearly passed (measured 3.0:1): "Sam answered" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|sam answered` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast failed (measured 2.6:1): "Tap to reveal both answers." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|tap to reveal both answers.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast failed (measured 4.2:1): "The little details count." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|the little details count.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast failed (measured 4.2:1): "Nov 8, 2026 at 5:30 PM" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|nov #, # at #:# pm` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast nearly passed (measured 4.2:1): "in 59 minutes" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|in # minutes` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast failed (measured 2.2:1): "A small note goes a long way." | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|a small note goes a long way.` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast failed (measured 1.7:1): "Done today" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|done today` |
| P2 | a11y-contrast |  | testCoreLoopAddThenMarkGestureDone / core-added-after-relaunch | Contrast nearly passed (measured 4.2:1): "in 22 hours" | `a11y-contrast|testCoreLoopAddThenMarkGestureDone|core-added-after-relaunch|in # hours` |
| P3 | a11y-element-description |  | testCoreLoopAddThenMarkGestureDone / core-editor | Element has no description | `a11y-element-description|testCoreLoopAddThenMarkGestureDone|core-editor|` |

## Journeys

| Persona | Journey | Result | Seconds |
|---|---|---|---|
| newcomer | test01OnboardingToTrialAndHome | Passed | 65.31430900096893 |
| newcomer | test02EveryTabOnSeededData | Passed | 51.27858793735504 |
| newcomer | test03ReturnVisitWithInterruption | Passed | 40.40732502937317 |
| newcomer | testCoreLoopAddThenMarkGestureDone | Passed | 82.28521394729614 |
| accessibility | test01OnboardingToTrialAndHome | Passed | 58.571995973587036 |
| accessibility | test02EveryTabOnSeededData | Passed | 39.71914994716644 |
| accessibility | test03ReturnVisitWithInterruption | Passed | 34.274353981018066 |
| accessibility | testCoreLoopAddThenMarkGestureDone | Failed | 46.46766400337219 |
| reduce-motion | test01OnboardingToTrialAndHome | Passed | 67.54622006416321 |
| reduce-motion | test02EveryTabOnSeededData | Passed | 55.55756103992462 |
| reduce-motion | test03ReturnVisitWithInterruption | Passed | 45.00755798816681 |
| reduce-motion | testCoreLoopAddThenMarkGestureDone | Passed | 92.52609598636627 |
| duo | test01OnboardingToTrialAndHome | Passed | 56.72323393821716 |
| duo | test02EveryTabOnSeededData | Failed | 30.014995098114014 |
| duo | test03ReturnVisitWithInterruption | Passed | 39.95308995246887 |
| duo | testCoreLoopAddThenMarkGestureDone | Failed | 34.41820299625397 |

## Motion

| Persona | Motion s | Windows | Candidates | Gaps > 25 ms | 60 fps |
|---|---|---|---|---|---|
| newcomer | 50.866 | 71 | 13 | 383 | True |
| accessibility | 54.302 | 54 | 7 | 596 | True |
| reduce-motion | 38.138 | 67 | 8 | 236 | True |

## Launch entrances to look at

Each launch's frames after the springboard zoom, left to right then down, 4 frames per
row at the recorded rate. A blank stretch, text that reflows, or content that arrives and
pushes the layout is a finding: `qa-gate ledger <repo> add`.

- [entrance-01-test01onboardingtotrialandhome.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/newcomer/entrance-01-test01onboardingtotrialandhome.png)
- [entrance-08-launchseeded.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/newcomer/entrance-08-launchseeded.png)
- [entrance-14-launchseeded.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/newcomer/entrance-14-launchseeded.png)
- [entrance-18-test03returnvisitwithinterruption.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/newcomer/entrance-18-test03returnvisitwithinterruption.png)
- [entrance-20-testcoreloopaddthenmarkgesturedone.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/newcomer/entrance-20-testcoreloopaddthenmarkgesturedone.png)
- [entrance-27-testcoreloopaddthenmarkgesturedone.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/newcomer/entrance-27-testcoreloopaddthenmarkgesturedone.png)
- [entrance-01-test01onboardingtotrialandhome.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/accessibility/entrance-01-test01onboardingtotrialandhome.png)
- [entrance-08-launchseeded.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/accessibility/entrance-08-launchseeded.png)
- [entrance-14-launchseeded.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/accessibility/entrance-14-launchseeded.png)
- [entrance-18-test03returnvisitwithinterruption.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/accessibility/entrance-18-test03returnvisitwithinterruption.png)
- [entrance-20-testcoreloopaddthenmarkgesturedone.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/accessibility/entrance-20-testcoreloopaddthenmarkgesturedone.png)
- [entrance-01-test01onboardingtotrialandhome.png](/Users/jackwallner/bond-ship/build/qa/63045884dbd0/reduce-motion/entrance-01-test01onboardingtotrialandhome.png)

Skipped personas: german (app not localized).
