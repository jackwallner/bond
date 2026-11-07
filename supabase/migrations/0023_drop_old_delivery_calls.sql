-- Applied after the send-push that uses 0022 is deployed.
drop function public.ack_reminder_push(uuid, timestamptz, uuid);
drop function public.delete_push_device(text, uuid, timestamptz);

notify pgrst, 'reload schema';
