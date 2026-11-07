import { assert, assertEquals } from "jsr:@std/assert@1";
import type { ClaimedRow, Device } from "./apns.ts";
import { CHUNK, CLAIM_LIMIT, type SendDeps, sendDue } from "./send.ts";

const token = (n: number) => n.toString(16).padStart(2, "0").repeat(32);
const device = (n: number): Device => ({ token: token(n), env: "production", updated_at: `2026-11-06T17:00:00.${n}+00:00` });

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
  failures = new Map<string, number>(),
  stillRegistered = new Set<string>(),
): Harness {
  const h: Harness = { deps: undefined!, calls: [], logs: [], dropped: 0, peak: 0 };
  const due = [...rows];
  let inFlight = 0;
  h.deps = {
    rpc: (name, args) => {
      h.calls.push({ name, args });
      const failure = failures.get(name);
      if (failure && failure > 0) {
        failures.set(name, failure - 1);
        return Promise.resolve({ data: null, error: { message: "database timeout" } });
      }
      const data = name === "claim_due_reminder_pushes"
        ? due.splice(0, args?.p_limit as number)
        : name === "remove_dead_push_device"
        ? !stillRegistered.has(args?.p_token as string)
        : null;
      return Promise.resolve({ data, error: null });
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
    nowSeconds: () => 1_793_988_030,
    elapsedMs: () => 0,
    log: (message) => h.logs.push(message),
    ...overrides,
  };
  return h;
}

const ok = () => new Response(null, { status: 200 });
const acks = (h: Harness) => h.calls.filter((c) => c.name === "ack_reminder_push").map((c) => c.args);
const marks = (h: Harness) => h.calls.filter((c) => c.name === "mark_push_sent").map((c) => c.args);

Deno.test("a sent occurrence is acknowledged with the due time exactly as claimed", async () => {
  const h = harness([row("r1", [device(1), device(2)])], ok);
  const result = await sendDue(h.deps);
  assertEquals(result.body.sent, 2);
  assertEquals(acks(h), [{
    p_reminder_id: "r1", p_due_at: "2026-11-06T18:00:00.123456+00:00", p_user_id: "user-b",
    p_tokens: [token(1), token(2)],
  }]);
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
    assertEquals(marks(h), [{
      p_reminder_id: "r1", p_due_at: "2026-11-06T18:00:00.123456+00:00", p_user_id: "user-b", p_tokens: [token(1)],
    }], "the retry skips the phone that got it");
  }
});

Deno.test("nothing is recorded when no phone was reached", async () => {
  const h = harness([row("r1", [device(1)])], () => new Response('{"reason":"InternalServerError"}', { status: 500 }));
  await sendDue(h.deps);
  assertEquals(marks(h), []);
  assertEquals(acks(h), []);
});

Deno.test("a refusal that will never pass is not retried", async () => {
  for (const refusal of ["DeviceTokenNotForTopic", "PayloadTooLarge", "BadCollapseId"]) {
    const h = harness([row("r1", [device(1), device(2)])],
      (t) => (t === token(2) ? new Response(`{"reason":"${refusal}"}`, { status: 400 }) : ok()));
    const result = await sendDue(h.deps);
    assertEquals(result.body.rejected, 1);
    assertEquals(acks(h).length, 1, refusal);
    assertEquals(h.calls.some((c) => c.name === "remove_dead_push_device"), false, "the row stays");
    assert(h.logs.some((l) => l.includes(refusal)));
  }
});

Deno.test("our own setup failing is counted and retried, so it can't lose reminders quietly", async () => {
  for (const refusal of ["BadTopic", "TopicDisallowed", "IdleTimeout"]) {
    const h = harness([row("r1", [device(1)])], () => new Response(`{"reason":"${refusal}"}`, { status: 400 }));
    const result = await sendDue(h.deps);
    assertEquals(result.body.failed, 1, refusal);
    assertEquals(result.body.ok, false);
    assertEquals(acks(h), []);
  }
});

Deno.test("the expiry is worked out when each push is sent", async () => {
  let seconds = 1_793_988_030;
  const expiries: string[] = [];
  const h = harness([row("r1", [device(1)])], ok, { nowSeconds: () => (seconds += 100) });
  const fetcher = h.deps.fetch;
  h.deps.fetch = (url, init) => {
    expiries.push((init?.headers as Record<string, string>)["apns-expiration"]);
    return fetcher(url, init);
  };
  await sendDue(h.deps);
  assert(Number(expiries[0]) >= seconds + 60, "never already past");
});

Deno.test("two rows sharing a dead token both count as dead", async () => {
  const h = harness([row("r1", [device(1)]), row("r2", [device(1)])],
    () => new Response('{"reason":"Unregistered"}', { status: 410 }));
  const result = await sendDue(h.deps);
  assertEquals(result.body.deadTokens, 2);
  assertEquals(result.body.failed, 0);
  assertEquals(result.body.ok, true);
});

Deno.test("a short claim with work left claims again", async () => {
  const h = harness([], ok);
  const claims: ClaimedRow[][] = [[], [row("r1", [device(1)])], []];
  let left = 2;
  const rpc = h.deps.rpc;
  h.deps.rpc = (name, args) => {
    if (name === "claim_due_reminder_pushes") return Promise.resolve({ data: claims.shift() ?? [], error: null });
    if (name === "push_work_left") return Promise.resolve({ data: left-- > 0, error: null });
    return rpc(name, args);
  };
  const result = await sendDue(h.deps);
  assertEquals(result.body.sent, 1);
  assertEquals(claims.length, 0);
});

Deno.test("work left does not outrun the budget", async () => {
  const h = harness([], ok, { elapsedMs: () => 60_000 });
  await sendDue(h.deps);
  assertEquals(h.calls.filter((c) => c.name === "claim_due_reminder_pushes").length, 1);
  assertEquals(h.calls.some((c) => c.name === "push_work_left"), false);
});

Deno.test("a record that can't be written at all counts as a failure", async () => {
  const h = harness([row("r1", [device(1)])], ok, {}, new Map([["ack_reminder_push", 2], ["mark_push_sent", 2]]));
  const result = await sendDue(h.deps);
  assertEquals(result.body.failed, 1);
  assertEquals(result.body.ok, false);
});

Deno.test("a record that fails is tried again", async () => {
  const h = harness([row("r1", [device(1)])], ok, {}, new Map([["ack_reminder_push", 1]]));
  const result = await sendDue(h.deps);
  assertEquals(result.body.acked, 1);
  assertEquals(marks(h), []);
});

Deno.test("an ack that keeps failing still records the phones, so a retry skips them", async () => {
  const h = harness([row("r1", [device(1)])], ok, {}, new Map([["ack_reminder_push", 2]]));
  const result = await sendDue(h.deps);
  assertEquals(result.body.acked, 0);
  assertEquals(marks(h).map((m) => m?.p_tokens), [[token(1)]]);
});

Deno.test("a phone that registered during the send is still owed it", async () => {
  const h = harness([row("r1", [device(1), device(2)])],
    (t) => (t === token(2) ? new Response('{"reason":"Unregistered"}', { status: 410 }) : ok()),
    {}, new Map(), new Set([token(2)]));
  const result = await sendDue(h.deps);
  assertEquals(result.body.deadTokens, 0);
  assertEquals(result.body.failed, 1);
  assertEquals(acks(h), []);
  assertEquals(marks(h).map((m) => m?.p_tokens), [[token(1)]]);
});

Deno.test("every send is finished before anything is removed or recorded", async () => {
  const order: string[] = [];
  const h = harness([row("r1", [device(1), device(2)])], (t) => {
    order.push("send");
    return t === token(2) ? new Response('{"reason":"Unregistered"}', { status: 410 }) : ok();
  });
  const rpc = h.deps.rpc;
  h.deps.rpc = (name, args) => {
    if (name !== "claim_due_reminder_pushes") order.push(name);
    return rpc(name, args);
  };
  await sendDue(h.deps);
  assertEquals(order, ["send", "send", "remove_dead_push_device", "ack_reminder_push", "push_work_left"]);
});

Deno.test("a dead token alone is not a failure, and goes only for the user it was claimed for", async () => {
  const h = harness([row("r1", [device(1), device(2)])],
    (t) => (t === token(2) ? new Response('{"reason":"Unregistered"}', { status: 410 }) : ok()));
  const result = await sendDue(h.deps);
  assertEquals(result.body.deadTokens, 1);
  assertEquals(acks(h).length, 1);
  assertEquals(h.calls.find((c) => c.name === "remove_dead_push_device")?.args, {
    p_token: token(2), p_user: "user-b", p_seen: "2026-11-06T17:00:00.2+00:00",
  });
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
  assertEquals(acks(h), [{
    p_reminder_id: null, p_due_at: "2026-11-06T18:00:00.123456+00:00", p_user_id: "user-b", p_tokens: [token(1)],
  }]);
});

Deno.test("a large batch goes out in bounded chunks", async () => {
  const devices = Array.from({ length: 5 }, (_, i) => device(i));
  const rows = Array.from({ length: 60 }, (_, i) => row(`r${i}`, devices));
  const h = harness(rows, ok);
  const result = await sendDue(h.deps);
  assertEquals(result.body.sent, 300);
  assert(h.peak <= CHUNK, `peak ${h.peak}`);
  assertEquals(acks(h).length, 60);
  const claims = h.calls.filter((c) => c.name === "claim_due_reminder_pushes");
  assertEquals(claims.length, 3, "each claim only leases what it can send inside the lease");
  assertEquals(claims[0].args, { p_limit: CLAIM_LIMIT });
});

Deno.test("a run stops claiming once it has used its time", async () => {
  const rows = Array.from({ length: 60 }, (_, i) => row(`r${i}`, [device(1)]));
  const h = harness(rows, ok, { elapsedMs: () => 61_000 });
  await sendDue(h.deps);
  assertEquals(h.calls.filter((c) => c.name === "claim_due_reminder_pushes").length, 1);
});

Deno.test("the response and the logs carry counts and reasons, never a token", async () => {
  const h = harness([row("r1", [device(7)])],
    () => Promise.reject(new TypeError(`error sending request for url (https://api.push.apple.com/3/device/${token(7)})`)));
  const result = await sendDue(h.deps);
  const everything = JSON.stringify(result.body) + h.logs.join("\n");
  assert(!everything.includes(token(7)), everything);
  assertEquals(Object.keys(result.body).sort(), ["acked", "deadTokens", "failed", "ok", "rejected", "sent"]);
});
