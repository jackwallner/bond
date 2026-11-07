// APNs sender. pg_cron calls it when a partner's reminder or a phone signal is
// due (migrations 0014, 0019). claim_due_reminder_pushes leases what is due;
// this sends it, acknowledges what went out (ack_reminder_push) and clears out
// dead tokens. Anything not acknowledged is claimed again after its lease.
//
// Secrets (`supabase secrets set`, never committed):
//   APNS_TEAM_ID, APNS_KEY_ID, APNS_TOPIC
//   APNS_PRIVATE_KEY   the .p8 contents; a literal "\n" is accepted for newlines
//   PUSH_CRON_SECRET   matches send_push_secret in the Vault
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { ProviderTokens } from "./provider.ts";
import { sendDue } from "./send.ts";

const REQUIRED = ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_TOPIC", "APNS_PRIVATE_KEY"] as const;

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

async function mintProviderToken(issuedAt: number): Promise<string> {
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
    encode({ iss: Deno.env.get("APNS_TEAM_ID"), iat: issuedAt })
  }`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64url(signature)}`;
}

let tokens: ProviderTokens | null = null;

Deno.serve(async (req) => {
  // The secret first, so a stranger learns nothing about the configuration.
  const secret = (Deno.env.get("PUSH_CRON_SECRET") ?? "").trim();
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  const missing = REQUIRED.filter((name) => !(Deno.env.get(name) ?? "").trim());
  if (missing.length > 0) {
    console.error(`send-push missing secrets: ${missing.join(", ")}`);
    return json({ ok: false, error: "not configured" }, 500);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  tokens ??= new ProviderTokens(mintProviderToken, {
    async load() {
      const { data, error } = await supabase.rpc("get_apns_provider_token", { p_key_id: keyId });
      const row = (data as { token: string; issued_at: string }[] | null)?.[0];
      if (error || !row) return null;
      return { token: row.token, issuedAt: Math.floor(Date.parse(row.issued_at) / 1000) };
    },
    async save(token) {
      await supabase.rpc("put_apns_provider_token", {
        p_key_id: keyId,
        p_token: token.token,
        p_issued_at: new Date(token.issuedAt * 1000).toISOString(),
      });
    },
  });
  const started = Date.now();
  const nowSeconds = Math.floor(started / 1000);

  const result = await sendDue({
    rpc: async (name, args) => {
      const { data, error } = await supabase.rpc(name, args).abortSignal(AbortSignal.timeout(
        name === "claim_due_reminder_pushes" ? 15_000 : 2_000,
      ));
      return { data, error: error ? { message: error.message } : null };
    },
    fetch: (url, init) => fetch(url, init),
    providerToken: () => tokens!.get(nowSeconds),
    dropProviderToken: () => tokens!.drop(),
    topic: Deno.env.get("APNS_TOPIC")!,
    nowSeconds,
    elapsedMs: () => Date.now() - started,
    log: (message) => console.error(message),
  });
  return json(result.body, result.status);
});
