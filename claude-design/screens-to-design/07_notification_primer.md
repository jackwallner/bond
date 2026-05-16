# 07 — Notification Permission Primer (new screen)

**Current source:** doesn't exist
**Priority:** P1 (improves opt-in rate dramatically)
**Status today:** `NotificationScheduler.requestAuthorizationIfNeeded()` is called inside `reschedule()` — the system prompt appears the first time the user saves a reminder. No context.

## Job
A pre-system-prompt screen explaining *why* the app needs notifications, shown right before the system sheet. Convert the implicit "this is a reminder app, of course" into an explicit "I want this to ping me."

## Suggested flow
1. After Pairing Success → first time landing on Reminders empty state, show this primer as a `.sheet` (not a full takeover).
2. Primer has illustrative copy + a "Turn on notifications" primary CTA + "Maybe later" secondary.
3. Primary CTA triggers `UNUserNotificationCenter.requestAuthorization`.
4. Sheet dismisses regardless of choice.

## Constraints
- Don't re-show if user already accepted or denied — gate on `notificationSettings().authorizationStatus`.
- "Maybe later" must be available — never trap the user.
- If denied, future "Settings" tab should show a "Notifications are off — Open Settings" inline card.

## Copy starting point (open to revision)
> ### Don't miss the moment.
> Bond's reminders are silent unless we can send a notification. The whole app stops working without them.
>
> [Turn on notifications]    [Maybe later]

## Don't
- Don't pre-empt with this screen *before* sign-in or pairing. Permission asks belong to the moment they're useful.
- Don't show this for Solo mode users who haven't created a reminder — they may genuinely not want any.
