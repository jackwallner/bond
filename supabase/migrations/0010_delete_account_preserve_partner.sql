-- delete_account (v2): deleting your account must NOT destroy your partner's
-- data.
--
-- The previous version (0008) ran `delete from auth.users` for the caller and
-- relied on FK cascades. For a paired couple that cascade ran:
--   auth.users -> profiles -> couples (the SHARED row) -> couple_id cascade on
--   reminders / milestones / reminder_events / question_responses.
-- Because the deleted couple was the one shared with the partner, the partner's
-- reminders, milestones, check-ins and event history were wiped too. One user
-- could permanently destroy another user's data — a trust and App Store review
-- problem, not just a UX wart.
--
-- Fix: if the caller is in a paired couple, first hand that couple to the
-- partner as their solo couple (removing the caller from it) so it is NOT
-- cascade-deleted, then delete the caller. With the couple no longer
-- referencing the caller, deleting the caller's profile cascades away only the
-- caller's OWN rows (via the author_id / user_id / target_id FKs); the partner
-- and everything hanging off the surviving couple stay intact.
--
-- Solo or uncoupled callers have nothing to preserve, so they just get deleted.
--
-- SECURITY DEFINER so it can reach auth.users; the auth.uid() guard ensures a
-- caller can only ever delete themselves.

create or replace function public.delete_account(p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_couple_id uuid;
    v_a         uuid;
    v_b         uuid;
    v_solo      boolean;
    v_partner   uuid;
begin
    if p_user is null or p_user <> auth.uid() then
        raise exception 'unauthorized';
    end if;

    select id, partner_a, partner_b, solo
      into v_couple_id, v_a, v_b, v_solo
    from public.couples
    where partner_a = p_user or partner_b = p_user
    for update;

    if v_couple_id is not null and not v_solo then
        v_partner := case when v_a = p_user then v_b else v_a end;

        -- reminders.target_id cascades when the leaver's profile is deleted.
        -- Re-point the partner's reminders that targeted the leaver back to the
        -- partner (self) so they survive as the partner's own solo reminders.
        update public.reminders
           set target_id = v_partner
         where couple_id = v_couple_id
           and author_id = v_partner
           and target_id = p_user;

        -- Hand the shared couple to the partner as their solo couple, removing
        -- the leaver from it so it is not cascade-deleted below.
        update public.couples
           set partner_a = v_partner,
               partner_b = v_partner,
               solo      = true
         where id = v_couple_id;
    end if;

    -- Cascades remove the leaver's profile and everything keyed to them.
    -- For a paired caller the couple no longer references the leaver, so only
    -- the leaver's own rows go; the partner's data is preserved above.
    delete from auth.users where id = p_user;
end;
$$;

grant execute on function public.delete_account(uuid) to authenticated;

notify pgrst, 'reload schema';
