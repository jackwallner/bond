# send-push

Delivers partner-written reminders, and the silent pushes that make a phone
rebuild what it armed, over APNs. pg_cron calls it each minute that something is
due (`supabase/migrations/0014_partner_delivery.sql`, `0019_reliable_delivery.sql`).

Since 0019 the claim leases each occurrence for 2 minutes. `send.ts` sends it to
every device in chunks of 50 and calls `ack_reminder_push` when no device failed
for a passing reason (a dead token does not count); anything else is claimed
again when the lease runs out, until it is an hour late. The function also
handles the claim's pre-0019 rows, so it can be deployed before the migration.

## Deploy

The CLI expects `supabase/functions`, so deploy from a temporary link:

```sh
mkdir -p supabase/functions && ln -s ../../SupabaseFunctions/send-push supabase/functions/send-push
supabase functions deploy send-push --no-verify-jwt --project-ref rmtkpokdsyfvrisfygta
rm -r supabase/functions
```

`--no-verify-jwt` because the caller is pg_cron with `PUSH_CRON_SECRET`, not a user.

## Secrets

`supabase secrets set`: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_TOPIC`
(`com.jackwallner.bond`), `APNS_PRIVATE_KEY`, `PUSH_CRON_SECRET`. The key is the
fleet APNs key, not an App Store Connect key: both are `.p8` files and the wrong
one answers `InvalidProviderToken`.

The Vault holds `send_push_url` and `send_push_secret` (the same value as
`PUSH_CRON_SECRET`).

## Tests

```sh
deno test SupabaseFunctions/send-push
```

Each device row says which APNs environment its build uses, so a debug build's
sandbox token cannot be refused by production and deleted.
