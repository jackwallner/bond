-- Defensive overload + cache reload for create_solo_couple.
--
-- Some clients have hit `PGRST202` ("Could not find the function
-- public.create_solo_couple(p_user) in the schema cache") on first-launch
-- "Just me" setup. The most common causes are:
--
--   1. PostgREST's schema cache went stale after the original 0002 migration
--      ran (no NOTIFY was sent), so the function exists in Postgres but the
--      gateway can't see it.
--   2. PostgREST tries to resolve overloads against the JSON value type
--      (string vs number), and there are environments where the implicit
--      text→uuid cast isn't picked up for RPC param matching.
--
-- Mitigations here:
--   - A `(p_user text)` overload that casts internally — so a Swift client
--     passing the UUID as a JSON string always resolves to *something*.
--   - `NOTIFY pgrst, 'reload schema'` at the bottom so the gateway picks up
--     both signatures immediately.

create or replace function public.create_solo_couple(p_user text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
begin
    return public.create_solo_couple(p_user::uuid);
end;
$$;

grant execute on function public.create_solo_couple(text) to authenticated;

notify pgrst, 'reload schema';
