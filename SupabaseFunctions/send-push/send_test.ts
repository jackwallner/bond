import { assert, assertEquals } from "jsr:@std/assert@1";
import type { ClaimedRow, Device } from "./apns.ts";
import { CHUNK, type SendDeps, sendDue } from "./send.ts";

const token = (n: number) => n.toString(16).padStart(2, "0").repeat(32);
const device = (n: number): Device => ({ token: token(n), env: "production" });

function row(id: string, devices: Device[], extra: Partial<ClaimedRow> = {}): ClaimedRow {
  return {
    reminder_id: id, couple_id: "d", title: "Flowers", body: null, love_language: "gifts", silent: false,
    user_id: "user-b", due_at: "2026-11-06T18:00:00.123456+00:00", devices, ...extra,
  };
}

interface Harness {
  deps: SendDeps;
  calls: { name: string; args?: Record<string, unknown> }[];
  logs: string[];
  dropped: number;
  peak: number;
}

function harness(
  rows: ClaimedRow[],
  answer: (token: string) => Response | Promise<Response>,
  overrides: Partial<SendDeps> = {},
): Harness {
  const h: Harness = { deps: undefined!, calls: [], logs: [], dropped: 0, peak: 0 };
  let inFlight = 0;
  h.deps = {
    rpc: (name, args) => {
      h.calls.push({ name, args });
      return Promise.resolve({ data: name === "claim_due_reminder_pushes" ? rows : null, error: null });
    },
    fetch: async (url) => {
      inFlight += 1;
      h.peak = Math.max(h.peak, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 1));
      try {
        return await answer(url.split("/").pop()!);
      } finally {
        inFlight -= 1;
      }
    },
    providerToken: () => Promise.resolve("jwt"),
    dropProviderToken: () => {
      h.dropped += 1;
    },
    topic: "com.jackwallner.bond",
    nowSeconds: 1_793_988_030,
    log: (message) => h.logs.push(message),
    ...overrides,
  };
  return h;
}

const ok = () => new Response(null, { status: 200 });
const acks = (h: Harness) => h.calls.filter((c) => c.name === "ack_reminder_push").map((c) => c.args);

Deno.test("a sent occurrence is acknowledged with the due time exactly as claimed", async () => {
  const h = harness([row("r1", [device(1), device(2)])], ok);
  const result = await sendDue(h.deps);
  assertEquals(result.body.sent, 2);
  assertEquals(acks(h), [{ p_reminder_id: "r1", p_due_at: "2026-11-06T18:00:00.123456+00:00", p_user_id: "user-b" }]);
});

Deno.test("a passing failure on any device leaves the occurrence for the retry", async () => {
  for (const failure of [
    () => new Response('{"reason":"ServiceUnavailable"}', { status: 503 }),
    () => new Response('{"reason":"TooManyRequests"}', { status: 429 }),
    () => Promise.reject(new DOMException("timed out", "TimeoutError")),
  ]) {
    const h = harness([row("r1", [device(1), device(2)]), row("r2", [device(3)])],
      (t) => (t === token(2) ? failure() : ok()));
    const result = await sendDue(h.deps);
    assertEquals(acks(h).map((a) => a?.p_reminder_id), ["r2"]);
    assertEquals(result.body.failed, 1);
    assertEquals(result.body.ok, false);
  }
});

Deno.test("a dead token alone is not a failure, and goes only for the user it was claimed for", async () => {
  const h = harness([row("r1", [device(1), device(2)])],
    (t) => (t === token(2) ? new Response('{"reason":"Unregistered"}', { status: 410 }) : ok()));
  const result = await sendDue(h.deps);
  assertEquals(result.body.deadTokens, 1);
  assertEquals(acks(h).length, 1);
  assertEquals(h.calls.find((c) => c.name === "delete_push_device")?.args, { p_token: token(2), p_user: "user-b" });
});

Deno.test("a refused provider token is minted again and the occurrence retried", async () => {
  const h = harness([row("r1", [device(1)])],
    () => new Response('{"reason":"InvalidProviderToken"}', { status: 403 }));
  await sendDue(h.deps);
  assertEquals(h.dropped, 1);
  assertEquals(acks(h).length, 0);
});

Deno.test("a provider token that cannot be made acknowledges nothing", async () => {
  const h = harness([row("r1", [device(1)])], ok, { providerToken: () => Promise.reject(new Error("bad key")) });
  const result = await sendDue(h.deps);
  assertEquals(result.status, 500);
  assertEquals(acks(h).length, 0);
});

Deno.test("phone signals are acknowledged by user", async () => {
  const h = harness([row("x", [device(1)], { reminder_id: null, couple_id: null, title: null, love_language: null, silent: true })], ok);
  await sendDue(h.deps);
  assertEquals(acks(h), [{ p_reminder_id: null, p_due_at: "2026-11-06T18:00:00.123456+00:00", p_user_id: "user-b" }]);
});

Deno.test("rows from the claim before 0019 are sent and never acknowledged", async () => {
  const legacy: ClaimedRow = {
    reminder_id: "r1", couple_id: "d", title: "Flowers", body: null, love_language: "gifts",
    silent: false, token: token(1), env: "production",
  };
  const h = harness([legacy, { ...legacy, token: token(2) }],
    (t) => (t === token(2) ? new Response('{"reason":"BadDeviceToken"}', { status: 400 }) : ok()));
  const result = await sendDue(h.deps);
  assertEquals(result.body.sent, 1);
  assertEquals(acks(h).length, 0);
  assertEquals(h.calls.find((c) => c.name === "delete_push_device")?.args, { p_token: token(2) });
});

Deno.test("a large batch goes out in bounded chunks", async () => {
  const devices = Array.from({ length: 5 }, (_, i) => device(i));
  const rows = Array.from({ length: 60 }, (_, i) => row(`r${i}`, devices));
  const h = harness(rows, ok);
  const result = await sendDue(h.deps);
  assertEquals(result.body.sent, 300);
  assert(h.peak <= CHUNK, `peak ${h.peak}`);
  assertEquals(acks(h).length, 60);
});

Deno.test("the response and the logs carry counts and reasons, never a token", async () => {
  const h = harness([row("r1", [device(7)])],
    () => Promise.reject(new TypeError(`error sending request for url (https://api.push.apple.com/3/device/${token(7)})`)));
  const result = await sendDue(h.deps);
  const everything = JSON.stringify(result.body) + h.logs.join("\n");
  assert(!everything.includes(token(7)), everything);
  assertEquals(Object.keys(result.body).sort(), ["acked", "deadTokens", "failed", "ok", "sent"]);
});
