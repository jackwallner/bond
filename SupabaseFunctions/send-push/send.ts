// One run of send-push: claim what is due, send it, record what went out.
// Everything outside (the database, APNs, the clock) comes in through `deps`.

import {
  apnsRequest,
  type ClaimedRow,
  type Device,
  isDeadToken,
  isPassing,
  isProviderTokenRefused,
  occurrence,
  type Occurrence,
  reason,
} from "./apns.ts";

export interface RpcResult {
  data: unknown;
  error: { message: string } | null;
}

export interface SendDeps {
  rpc(name: string, args?: Record<string, unknown>): Promise<RpcResult>;
  fetch(url: string, init: RequestInit): Promise<Response>;
  providerToken(): Promise<string>;
  /// APNs refused the provider token: mint a new one next time.
  dropProviderToken(): void | Promise<void>;
  topic: string;
  nowSeconds: () => number;
  elapsedMs(): number;
  log(message: string): void;
}

export interface SendResult {
  status: number;
  body: {
    ok: boolean;
    sent: number;
    deadTokens: number;
    rejected: number;
    failed: number;
    acked: number;
    error?: string;
  };
}

/// How many requests are in flight at once, so a large batch cannot exhaust the function.
export const CHUNK = 50;
/// A claim leases its rows for 3 minutes, longer than the function can run. 25
/// occurrences and 25 signals at 10 phones each is 10 chunks: 80 s if every request
/// times out, 20 s more if every token is dead and every removal hits the database's
/// 2 s limit, then the records. So nothing is claimed twice.
export const CLAIM_LIMIT = 25;
/// Claim again while there is more. One more claim can take 125 s with the claim
/// itself, and the function is cut off at 150 s.
const BUDGET_MS = 25_000;

async function inChunks<T>(items: T[], run: (item: T) => Promise<void>): Promise<void> {
  for (let start = 0; start < items.length; start += CHUNK) {
    await Promise.all(items.slice(start, start + CHUNK).map(run));
  }
}

type Outcome = "sent" | "dead" | "rejected" | "retry";

interface Send {
  push: Occurrence;
  device: Device;
  outcome?: Outcome;
}

async function deliver(push: Occurrence, device: Device, authorization: string, deps: SendDeps): Promise<Outcome> {
  const request = apnsRequest(push, device, deps.topic, deps.nowSeconds());
  try {
    const response = await deps.fetch(request.url, {
      method: "POST",
      headers: { ...request.headers, authorization },
      body: request.body,
      signal: AbortSignal.timeout(8000),
    });
    if (response.ok) {
      await response.body?.cancel();
      return "sent";
    }
    const text = await response.text();
    if (isDeadToken(response.status, text)) return "dead";
    if (isProviderTokenRefused(response.status, text)) await deps.dropProviderToken();
    deps.log(`APNs ${response.status} ${reason(text)}`);
    return isPassing(response.status, text) ? "retry" : "rejected";
  } catch (err) {
    // The name only: a fetch error message can carry the device URL.
    deps.log(`APNs request failed: ${err instanceof Error ? err.name : "unknown"}`);
    return "retry";
  }
}

/// Only while the row is the one claimed. If the phone registered since, this
/// token works after all, and it still needs the occurrence.
async function removeDead(send: Send, deps: SendDeps): Promise<Outcome> {
  const { data, error } = await deps.rpc("remove_dead_push_device", {
    p_token: send.device.token,
    p_user: send.push.userId,
    p_seen: send.device.updated_at,
  });
  if (error) deps.log(`dead token not removed: ${error.message}`);
  return !error && data === true ? "dead" : "retry";
}

type Counts = Omit<SendResult["body"], "ok" | "error">;

async function call(name: string, args: Record<string, unknown>, deps: SendDeps): Promise<boolean> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const { error } = await deps.rpc(name, args);
    if (!error) return true;
    deps.log(`${name} failed: ${error.message}`);
  }
  return false;
}

async function record(push: Occurrence, retry: boolean, finished: string[], counts: Counts, deps: SendDeps) {
  const key = { p_reminder_id: push.reminderId, p_due_at: push.dueAt, p_user_id: push.userId, p_tokens: finished };
  if (!retry && await call("ack_reminder_push", key, deps)) {
    counts.acked += 1;
    return;
  }
  // The retry goes only to the phones that are still owed it.
  if (finished.length > 0 && !await call("mark_push_sent", key, deps)) counts.failed += 1;
}

/// A short claim may only have stopped at its examined limit, with good rows still
/// behind stale ones, and those can pass their hour by the next run.
async function keepGoing(claimed: number, deps: SendDeps): Promise<boolean> {
  if (deps.elapsedMs() > BUDGET_MS) return false;
  if (claimed === CLAIM_LIMIT) return true;
  const { data, error } = await deps.rpc("push_work_left", {});
  return !error && data === true;
}

export async function sendDue(deps: SendDeps): Promise<SendResult> {
  const counts: Counts = { sent: 0, deadTokens: 0, rejected: 0, failed: 0, acked: 0 };

  while (true) {
    const { data, error } = await deps.rpc("claim_due_reminder_pushes", { p_limit: CLAIM_LIMIT });
    if (error) {
      deps.log(`claim failed: ${error.message}`);
      return { status: 500, body: { ok: false, ...counts, error: "claim failed" } };
    }
    const pushes = ((data ?? []) as ClaimedRow[]).map(occurrence);
    if (pushes.length === 0) {
      if (await keepGoing(0, deps)) continue;
      break;
    }

    let authorization: string;
    try {
      authorization = `bearer ${await deps.providerToken()}`;
    } catch (err) {
      // Nothing is recorded, so every claimed row is sent again after its lease.
      deps.log(`provider token failed: ${err instanceof Error ? err.name : "unknown"}`);
      return { status: 500, body: { ok: false, ...counts, error: "provider token failed" } };
    }

    const sends: Send[] = pushes.flatMap((push) => push.devices.map((device) => ({ push, device })));
    await inChunks(sends, async (send) => {
      send.outcome = await deliver(send.push, send.device, authorization, deps);
    });
    await inChunks(sends.filter((send) => send.outcome === "dead"), async (send) => {
      send.outcome = await removeDead(send, deps);
    });

    const retry = new Set<Occurrence>();
    const finished = new Map<Occurrence, string[]>(pushes.map((push) => [push, []]));
    for (const { push, device, outcome } of sends) {
      if (outcome === "retry") {
        counts.failed += 1;
        retry.add(push);
        continue;
      }
      if (outcome === "sent") counts.sent += 1;
      else if (outcome === "dead") counts.deadTokens += 1;
      else counts.rejected += 1;
      finished.get(push)!.push(device.token);
    }
    await inChunks(pushes, (push) => record(push, retry.has(push), finished.get(push)!, counts, deps));

    if (!await keepGoing(pushes.length, deps)) break;
  }

  return { status: 200, body: { ok: counts.failed === 0, ...counts } };
}
