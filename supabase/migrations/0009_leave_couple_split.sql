-- leave_couple (v2): UNPAIR by splitting the couple into two solo couples,
-- preserving each partner's own data.
--
-- The previous version (0004) did `delete from public.couples`, which cascades
-- couple_id on reminders / milestones / reminder_events / question_responses
-- and so destroyed BOTH partners' data. That directly contradicts the function
-- header ("each partner keeps their own reminders/milestones") and the in-app
-- Unpair dialog ("You'll keep your reminders. Your partner will keep theirs.").
-- This makes the promise true.
--
-- Strategy for a paired couple C = (partner_a = A, partner_b = B):
--   1. Repurpose C in place into A's solo couple: set partner_b = A, solo = true.
--      This also frees B from the couples_partner_b unique index.
--   2. Create a fresh solo couple D for B.
--   3. Re-home B's OWN rows from C to D, keyed by ownership:
--        - reminders          by author_id
--        - reminder_events    by their parent reminder's author_id
--        - question_responses by user_id
--      A's rows simply stay on C, which is now A's solo couple.
--   4. Milestones have no per-user owner (anniversaries/birthdays are shared),
--      so copy them onto D — both partners keep them.
--
-- Roles are assigned deterministically (partner_a keeps the existing row), so
-- the outcome does not depend on which partner pressed Unpair.
--
-- A solo couple has nothing to split from, so leaving one is a no-op. (The UI
-- only offers Unpair for real paired couples anyway.)

create or replace function public.leave_couple(p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_couple_id  uuid;
    v_a          uuid;
    v_b          uuid;
    v_solo       boolean;
    v_keeper     uuid;   -- stays on the existing (repurposed) couple
    v_mover      uuid;   -- gets a fresh solo couple + their own rows migrated
    v_new_couple uuid;
begin
    if p_user <> auth.uid() then
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
$$;

grant execute on function public.leave_couple(uuid) to authenticated;

notify pgrst, 'reload schema';
