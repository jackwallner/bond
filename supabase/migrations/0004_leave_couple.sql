-- leave_couple: dissolve the caller's couple. Each partner keeps their own
-- reminders/milestones (they remain owned by the authoring user); only the
-- couple row is removed so both can re-pair or go solo.

create or replace function public.leave_couple(p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_couple_id uuid;
begin
    if p_user <> auth.uid() then
        raise exception 'unauthorized';
    end if;

    select id into v_couple_id
    from public.couples
    where partner_a = p_user or partner_b = p_user
    for update;

    if v_couple_id is null then
        return;
    end if;

    delete from public.couples where id = v_couple_id;
end;
$$;

grant execute on function public.leave_couple(uuid) to authenticated;
