// APNs sender — wired up in Phase 2.
//
// Triggered by a Postgres webhook on `public.reminders` (INSERT/UPDATE).
// Reads the target user's apns_token from profiles, signs a JWT with the
// APNs Auth Key, and POSTs to https://api.push.apple.com (or sandbox).
//
// Required Supabase secrets:
//   APNS_TEAM_ID, APNS_KEY_ID, APNS_AUTH_KEY (.p8 contents), APNS_TOPIC,
//   APNS_USE_SANDBOX ("true" | "false").

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (_req) => {
  return new Response(
    JSON.stringify({ ok: false, error: "not_implemented" }),
    { status: 501, headers: { "content-type": "application/json" } },
  );
});
