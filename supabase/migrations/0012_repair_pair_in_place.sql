-- Repair: production never actually received migration 0005's objects even
-- though it is recorded as applied (the file was rewritten after the original
-- 0005 ran). Prod was still running the pre-solo-mode consume_invite_code,
-- whose bare `insert into couples` collides with the partners' existing solo
-- couple rows on couples_partner_a_idx / couples_partner_b_idx — so every
-- real pairing attempt failed with a unique violation ("Pairing didn't
-- work."). profiles.love_language was missing for the same reason.
--
-- This migration re-applies 0005's content verbatim and idempotently.

alter table public.profiles
    add column if not exists love_language text;

create or replace function public.consume_invite_code(p_code text, p_user uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    v_inviter        uuid;
    v_inviter_couple uuid;
    v_inviter_solo   boolean;
    v_invitee_couple uuid;
    v_invitee_solo   boolean;
    v_couple_id      uuid;
    v_stale_couple   uuid;
begin
    if p_user <> auth.uid() then
        raise exception 'unauthorized';
    end if;

    select created_by into v_inviter
    from public.invite_codes
    where code = p_code and expires_at > now()
    for update;

    if v_inviter is null then
        raise exception 'invalid or expired code';
    end if;
    if v_inviter = p_user then
        raise exception 'cannot pair with yourself';
    end if;

    -- Each side may be uncoupled or in a SOLO couple. A real (paired) couple
    -- on either side is a hard stop.
    select id, solo into v_inviter_couple, v_inviter_solo
    from public.couples
    where partner_a = v_inviter or partner_b = v_inviter
    for update;
    if v_inviter_couple is not null and v_inviter_solo is false then
        raise exception 'inviter already in a couple';
    end if;

    select id, solo into v_invitee_couple, v_invitee_solo
    from public.couples
    where partner_a = p_user or partner_b = p_user
    for update;
    if v_invitee_couple is not null and v_invitee_solo is false then
        raise exception 'you are already in a couple';
    end if;

    -- Pick the surviving couple. The other solo couple (if any) is stale and
    -- gets merged in below.
    if v_inviter_couple is not null then
        v_couple_id    := v_inviter_couple;
        v_stale_couple := v_invitee_couple;
    elsif v_invitee_couple is not null then
        v_couple_id    := v_invitee_couple;
        v_stale_couple := null;
    else
        insert into public.couples (partner_a, partner_b, solo)
        values (v_inviter, p_user, false)
        returning id into v_couple_id;
        v_stale_couple := null;
    end if;

    -- Move the stale solo couple's content onto the survivor, then drop the
    -- empty shell. This MUST happen before we claim partner_b on the
    -- survivor: until the stale row is gone, p_user still occupies it and the
    -- couples_partner_b_idx unique index would reject the reassignment.
    if v_stale_couple is not null and v_stale_couple <> v_couple_id then
        update public.reminders       set couple_id = v_couple_id where couple_id = v_stale_couple;
        update public.milestones      set couple_id = v_couple_id where couple_id = v_stale_couple;
        update public.reminder_events set couple_id = v_couple_id where couple_id = v_stale_couple;
        delete from public.couples where id = v_stale_couple;
    end if;

    update public.couples
    set partner_a = v_inviter,
        partner_b = p_user,
        solo      = false
    where id = v_couple_id;

    delete from public.invite_codes where code = p_code;

    return v_couple_id;
end;
$$;

grant execute on function public.consume_invite_code(text, uuid) to authenticated;
