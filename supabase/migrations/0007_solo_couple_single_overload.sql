-- Fix PGRST203 on first-launch "Just me" setup.
--
-- Migration 0006 added a `(p_user text)` overload alongside the original
-- `(p_user uuid)` from 0002. With BOTH present, a client passing the UUID as
-- a JSON string (which the Swift app does) makes PostgREST unable to pick a
-- candidate:
--
--   PGRST203 "Could not choose the best candidate function between:
--             public.create_solo_couple(p_user => text),
--             public.create_solo_couple(p_user => uuid)"
--
-- Collapse to a SINGLE function taking `text` (self-contained, no delegation
-- to a second overload). A text param matches the client's JSON string exactly
-- with no implicit cast, so resolution is unambiguous and stable.

drop function if exists public.create_solo_couple(uuid);
drop function if exists public.create_solo_couple(text);

create or replace function public.create_solo_couple(p_user text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
    v_user uuid := p_user::uuid;
    v_couple_id uuid;
begin
    if v_user <> auth.uid() then
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
$$;

grant execute on function public.create_solo_couple(text) to authenticated;

notify pgrst, 'reload schema';
