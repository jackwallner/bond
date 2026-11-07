-- Supabase grants new public functions to anon, authenticated and service_role by
-- name, so the "revoke from public" in 0014 and 0015 left them callable with the app's
-- public key. claim_due_reminder_pushes would hand out device tokens and reminder text
-- and use up the delivery; delete_push_device would remove anyone's device.

revoke all on function public.claim_due_reminder_pushes(int) from public, anon, authenticated;
revoke all on function public.delete_push_device(text) from public, anon, authenticated;

revoke all on function public.reminder_next_push_at(public.reminders, timestamptz, text) from public, anon, authenticated;
revoke all on function public.reminder_done_now(public.reminders, text) from public, anon, authenticated;
revoke all on function public.reminder_pair_intact(public.reminders) from public, anon, authenticated;
revoke all on function public.push_timezone(uuid) from public, anon, authenticated;
revoke all on function public.refresh_reminder_push(public.reminders) from public, anon, authenticated;
revoke all on function public.reminders_sync_push_queue() from public, anon, authenticated;
revoke all on function public.couples_sync_push_queue() from public, anon, authenticated;

revoke all on function public.register_push_device(text, text, text) from public, anon;
revoke all on function public.unregister_push_device(text) from public, anon;
revoke all on function public.reschedule_reminder(uuid, text, timestamptz, text, jsonb, timestamptz, timestamptz) from public, anon;
