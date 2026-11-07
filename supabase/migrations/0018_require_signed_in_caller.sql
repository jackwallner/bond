-- Every account RPC requires a signed in caller acting on themselves.

create or replace function public.consume_invite_code(p_code text, p_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_inviter        uuid;
    v_inviter_couple uuid;
    v_inviter_solo   boolean;
    v_invitee_couple uuid;
    v_invitee_solo   boolean;
    v_couple_id      uuid;
    v_stale_couple   uuid;
begin
    if auth.uid() is null or p_user is distinct from auth.uid() then
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
$function$;

create or replace function public.create_solo_couple(p_user text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_user uuid := p_user::uuid;
    v_couple_id uuid;
begin
    if auth.uid() is null or v_user is distinct from auth.uid() then
        raise exception 'unauthorized';
    end if;

    if exists (select 1 from public.couples
               where partner_a = v_user or partner_b = v_user) then
        raise exception 'already in a couple';
    end if;

    insert into public.couples (partner_a, partner_b, solo)
    values (v_user, v_user, true)
    returning id into v_couple_id;

    return v_couple_id;
end;
$function$;

create or replace function public.delete_account(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_couple_id uuid;
    v_a         uuid;
    v_b         uuid;
    v_solo      boolean;
    v_partner   uuid;
begin
    if auth.uid() is null or p_user is distinct from auth.uid() then
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
$function$;

create or replace function public.leave_couple(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_couple_id  uuid;
    v_a          uuid;
    v_b          uuid;
    v_solo       boolean;
    v_keeper     uuid;   -- stays on the existing (repurposed) couple
    v_mover      uuid;   -- gets a fresh solo couple + their own rows migrated
    v_new_couple uuid;
begin
    if auth.uid() is null or p_user is distinct from auth.uid() then
        raise exception 'unauthorized';
    end if;

    select id, partner_a, partner_b, solo
      into v_couple_id, v_a, v_b, v_solo
    from public.couples
    where partner_a = p_user or partner_b = p_user
    for update;

    if v_couple_id is null then
        return;                       -- not in a couple
    end if;
    if v_solo then
        return;                       -- nothing to split
    end if;

    v_keeper := v_a;
    v_mover  := v_b;

    -- 1. Repurpose the existing couple as the keeper's solo couple. Setting
    --    partner_b = keeper frees the mover from couples_partner_b_idx so the
    --    new couple below can claim them.
    update public.couples
       set partner_a = v_keeper,
           partner_b = v_keeper,
           solo      = true
     where id = v_couple_id;

    -- 2. Fresh solo couple for the mover.
    insert into public.couples (partner_a, partner_b, solo)
    values (v_mover, v_mover, true)
    returning id into v_new_couple;

    -- 3. Re-home the mover's own rows. Events follow their parent reminder's
    --    author so a partner's history travels with them. Match reminders by
    --    author_id (their couple_id has already moved by the time this runs,
    --    but author_id is stable).
    update public.reminders
       set couple_id = v_new_couple
     where couple_id = v_couple_id and author_id = v_mover;

    update public.reminder_events e
       set couple_id = v_new_couple
      from public.reminders r
     where e.reminder_id = r.id
       and r.author_id   = v_mover
       and e.couple_id   = v_couple_id;

    update public.question_responses
       set couple_id = v_new_couple
     where couple_id = v_couple_id and user_id = v_mover;

    -- 4. Copy the shared milestones so both partners keep them.
    insert into public.milestones (couple_id, kind, label, date, recur, created_at)
    select v_new_couple, kind, label, date, recur, created_at
      from public.milestones
     where couple_id = v_couple_id;
end;
$function$;

revoke all on function public.consume_invite_code(text, uuid) from public, anon;
grant execute on function public.consume_invite_code(text, uuid) to authenticated;
revoke all on function public.create_solo_couple(text) from public, anon;
grant execute on function public.create_solo_couple(text) to authenticated;
revoke all on function public.delete_account(uuid) from public, anon;
grant execute on function public.delete_account(uuid) to authenticated;
revoke all on function public.leave_couple(uuid) from public, anon;
grant execute on function public.leave_couple(uuid) to authenticated;
