# send-push

APNs sender. Triggered by a Supabase Postgres webhook on inserts/updates to `public.reminders`.

## Deploy

```sh
supabase functions deploy send-push --project-ref rmtkpokdsyfvrisfygta
```

## Secrets

```sh
supabase secrets set \
  APNS_TEAM_ID=YXG4MP6W39 \
  APNS_KEY_ID=ABCD123456 \
  APNS_AUTH_KEY="$(cat AuthKey_ABCD123456.p8)" \
  APNS_TOPIC=com.jackwallner.bond \
  APNS_USE_SANDBOX=true \
  --project-ref rmtkpokdsyfvrisfygta
```

`APNS_AUTH_KEY` is the full PEM contents of the `.p8` file downloaded from the Apple Developer portal (Certificates, Identifiers & Profiles → Keys → register an APNs Auth Key, copy the Key ID, download the file once).

## Wire the webhook

Dashboard → Database → Webhooks → "Create a new hook":
- Name: `reminder-push`
- Table: `public.reminders`
- Events: Insert, Update
- HTTP method: POST
- URL: `https://rmtkpokdsyfvrisfygta.supabase.co/functions/v1/send-push`
- HTTP headers: `Authorization: Bearer <service_role_key>` (Supabase auto-includes it for webhooks targeting your project — verify in UI)

## Blocker

Requires a paid Apple Developer Program account ($99/yr) to create the APNs Auth Key. Without that, this function will 401 from APNs.
