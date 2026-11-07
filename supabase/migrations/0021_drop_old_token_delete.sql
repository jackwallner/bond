-- Applied after the send-push that passes p_seen is deployed (see 0020).
drop function public.delete_push_device(text);
drop function public.delete_push_device(text, uuid);

notify pgrst, 'reload schema';
