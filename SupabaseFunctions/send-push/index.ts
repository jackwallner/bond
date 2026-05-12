// APNs sender — invoked by Supabase Postgres webhook on inserts into public.reminders.
//
// Required Supabase secrets (set via `supabase secrets set`):
//   APNS_TEAM_ID      – Apple Developer Team ID (10 chars)
//   APNS_KEY_ID       – APNs Auth Key ID (10 chars)
//   APNS_AUTH_KEY     – contents of the .p8 file (PEM)
//   APNS_TOPIC        – bundle ID, e.g. com.jackwallner.bond
//   APNS_USE_SANDBOX  – "true" while developing on Xcode-built builds, "false" in TestFlight/App Store
//   SUPABASE_URL      – auto-provided
//   SUPABASE_SERVICE_ROLE_KEY – auto-provided
//
// Postgres webhook payload shape (Supabase Database Webhooks):
//   { type: "INSERT" | "UPDATE", record: {...reminder row...}, old_record: {...} | null, schema: "public", table: "reminders" }

import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TEAM_ID = mustEnv("APNS_TEAM_ID");
const KEY_ID = mustEnv("APNS_KEY_ID");
const AUTH_KEY_PEM = mustEnv("APNS_AUTH_KEY");
const TOPIC = mustEnv("APNS_TOPIC");
const USE_SANDBOX = (Deno.env.get("APNS_USE_SANDBOX") ?? "true") === "true";
const APNS_HOST = USE_SANDBOX
  ? "https://api.sandbox.push.apple.com"
  : "https://api.push.apple.com";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

interface ReminderRow {
  id: string;
  couple_id: string;
  author_id: string;
  target_id: string;
  title: string;
  body: string | null;
  love_language: string;
  trigger_type: string;
  surprise_hidden_from_partner: boolean;
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  record: ReminderRow | null;
  old_record: ReminderRow | null;
  schema: string;
  table: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const payload = (await req.json()) as WebhookPayload;
  if (payload.type === "DELETE" || !payload.record) {
    return jsonOK({ skipped: "delete or empty record" });
  }
  const reminder = payload.record;

  // Only push when the target is the partner (i.e. not the author).
  // Self-targeted reminders are handled locally on the author's device.
  if (reminder.target_id === reminder.author_id) {
    return jsonOK({ skipped: "self-targeted" });
  }

  // Fetch the target's APNs token.
  const { data: profile, error: profileErr } = await supabase
    .from("profiles")
    .select("apns_token")
    .eq("id", reminder.target_id)
    .single();

  if (profileErr || !profile?.apns_token) {
    return jsonOK({ skipped: "no apns_token for target", error: profileErr?.message });
  }

  const token = await mintProviderToken();

  const apnsBody = {
    aps: {
      alert: {
        title: reminder.title,
        body: reminder.body ?? "",
      },
      sound: "default",
      "thread-id": reminder.love_language,
      "interruption-level": "active",
    },
    reminder_id: reminder.id,
    couple_id: reminder.couple_id,
    love_language: reminder.love_language,
  };

  const apnsRes = await fetch(`${APNS_HOST}/3/device/${profile.apns_token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${token}`,
      "apns-topic": TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(apnsBody),
  });

  if (!apnsRes.ok) {
    const text = await apnsRes.text();
    return new Response(
      JSON.stringify({ ok: false, status: apnsRes.status, body: text }),
      { status: 502, headers: { "content-type": "application/json" } },
    );
  }

  return jsonOK({ pushed: true });
});

// ---------- helpers ----------

function mustEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing env: ${name}`);
  return v;
}

function jsonOK(body: unknown): Response {
  return new Response(JSON.stringify({ ok: true, ...((body as object) ?? {}) }), {
    headers: { "content-type": "application/json" },
  });
}

// Cache the provider token for ~50 minutes (Apple allows max 1 hour).
let cachedToken: { token: string; expires: number } | null = null;

async function mintProviderToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires > now + 60) return cachedToken.token;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBuffer(AUTH_KEY_PEM),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const token = await create(
    { alg: "ES256", kid: KEY_ID, typ: "JWT" },
    { iss: TEAM_ID, iat: getNumericDate(0) },
    key,
  );

  cachedToken = { token, expires: now + 50 * 60 };
  return token;
}

function pemToBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
