-- delete_account: permanently delete the caller's account and all their data.
-- Required for App Store Guideline 5.1.1(v) (in-app account deletion).
--
-- Deleting the auth.users row cascades through every owning FK:
--   auth.users -> profiles -> couples (solo OR paired) -> reminders /
--   milestones / reminder_events, plus subscriptions, invite_codes, ai_usage.
-- For a paired couple this dissolves the couple (same cascade as leave_couple),
-- so the shared couple data is removed. The partner keeps their own account.
--
-- SECURITY DEFINER so it can reach auth.users; the auth.uid() guard ensures a
-- caller can only ever delete themselves.

create or replace function public.delete_account(p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
    if p_user is null or p_user <> auth.uid() then
        raise exception 'unauthorized';
    end if;

    delete from auth.users where id = p_user;
end;
$$;

grant execute on function public.delete_account(uuid) to authenticated;
