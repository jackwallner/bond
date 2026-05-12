-- Allow solo (self) couples: a user can use Bond alone for self-reminders.

alter table public.couples
    add column if not exists solo boolean not null default false;

alter table public.couples
    drop constraint if exists couples_partners_distinct;

-- Solo couples have partner_a = partner_b. The existing unique indexes
-- (couples_partner_a_idx, couples_partner_b_idx) already enforce that a
-- user cannot appear in more than one couple, even when partners are equal.

-- Create a solo couple for a user who wants to use Bond independently.
create or replace function public.create_solo_couple(p_user uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    v_couple_id uuid;
begin
    if p_user <> auth.uid() then
        raise exception 'unauthorized';
    end if;

    if exists (select 1 from public.couples
               where partner_a = p_user or partner_b = p_user) then
        raise exception 'already in a couple';
    end if;

    insert into public.couples (partner_a, partner_b, solo)
    values (p_user, p_user, true)
    returning id into v_couple_id;

    return v_couple_id;
end;
$$;

grant execute on function public.create_solo_couple(uuid) to authenticated;
