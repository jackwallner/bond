-- Hardening: entitlements come from RevenueCat, nothing in the app or the
-- database reads or writes public.subscriptions. Stop users from writing their
-- own tier / expires_at, and drop Supabase's default TRUNCATE grant.
-- SELECT-own stays; service_role keeps full access.

drop policy if exists "subscriptions_self_upsert" on public.subscriptions;
drop policy if exists "subscriptions_self_update" on public.subscriptions;

revoke insert, update, truncate on public.subscriptions from anon, authenticated;
