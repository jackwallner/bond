// APNs sender. pg_cron calls it when a partner's reminder is due (migration 0014);
// claim_due_reminder_pushes decides what goes out and moves each row on, so this
// only sends and clears out dead tokens.
//
// Secrets (`supabase secrets set`, never committed):
//   APNS_TEAM_ID, APNS_KEY_ID, APNS_TOPIC
//   APNS_PRIVATE_KEY   the .p8 contents; a literal "\n" is accepted for newlines
//   PUSH_CRON_SECRET   matches send_push_secret in the Vault
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { apnsRequest, type ClaimedPush, isDeadToken } from "./apns.ts";

const REQUIRED = [
  "APNS_TEAM_ID",
  "APNS_KEY_ID",
  "APNS_TOPIC",
  "APNS_PRIVATE_KEY",
  "PUSH_CRON_SECRET",
] as const;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const array = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const byte of array) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Apple rejects a provider token older than an hour and limits how often one
// changes, so it lives for 50 minutes in this isolate.
let provider: { token: string; mintedAt: number } | null = null;

async function providerToken(nowSeconds: number): Promise<string> {
  if (provider && nowSeconds - provider.mintedAt < 50 * 60) return provider.token;

  const pem = Deno.env.get("APNS_PRIVATE_KEY")!
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") })}.${
    encode({ iss: Deno.env.get("APNS_TEAM_ID"), iat: nowSeconds })
  }`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  provider = { token: `${unsigned}.${base64url(signature)}`, mintedAt: nowSeconds };
  return provider.token;
}

Deno.serve(async (req) => {
  const missing = REQUIRED.filter((name) => !(Deno.env.get(name) ?? "").trim());
  if (missing.length > 0) return json({ ok: false, missing }, 500);

  if (req.headers.get("authorization") !== `Bearer ${Deno.env.get("PUSH_CRON_SECRET")}`) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("claim_due_reminder_pushes");
  if (error) return json({ ok: false, error: error.message }, 500);
  const pushes = (data ?? []) as ClaimedPush[];
  if (pushes.length === 0) return json({ ok: true, sent: 0 });

  const nowSeconds = Math.floor(Date.now() / 1000);
  const authorization = `bearer ${await providerToken(nowSeconds)}`;
  const topic = Deno.env.get("APNS_TOPIC")!;
  let sent = 0;
  let deadTokens = 0;
  const failures: string[] = [];

  await Promise.all(pushes.map(async (push) => {
    const request = apnsRequest(push, topic, nowSeconds);
    try {
      const response = await fetch(request.url, {
        method: "POST",
        headers: { ...request.headers, authorization },
        body: request.body,
        signal: AbortSignal.timeout(8000),
      });
      if (response.ok) {
        await response.body?.cancel();
        sent += 1;
        return;
      }
      const text = await response.text();
      if (isDeadToken(response.status, text)) {
        deadTokens += 1;
        await supabase.rpc("delete_push_device", { p_token: push.token });
      } else {
        failures.push(`${response.status} ${text}`);
      }
    } catch (err) {
      failures.push(err instanceof Error ? err.message : String(err));
    }
  }));

  return json({ ok: failures.length === 0, sent, deadTokens, failures });
});
