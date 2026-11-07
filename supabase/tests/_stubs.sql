-- Minimal Supabase stand-ins so the public migrations can be applied and the
-- RPC tests can run on a plain PostgreSQL (no Supabase platform). TEST-ONLY —
-- never applied to a real database.
--
--   * auth.users            : profiles.id FKs to it; delete_account deletes from it
--   * auth.uid()            : real Supabase reads the JWT; here it reads a GUC we
--                             set per-actor via set_config('test.uid', <uuid>, ...)
--   * role "authenticated"  : the migrations grant EXECUTE on the RPCs to it

create extension if not exists pgcrypto;

create schema if not exists auth;

create table if not exists auth.users (
    id                 uuid primary key default gen_random_uuid(),
    email              text,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at         timestamptz not null default now()
);

create or replace function auth.uid()
returns uuid
language sql stable
as $$
    select nullif(current_setting('test.uid', true), '')::uuid;
$$;

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role;
    end if;
end
$$;

-- Supabase grants every new public function to these roles by name, so a plain
-- "revoke from public" does not close it. Match that, or the tests pass while production is open.
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

