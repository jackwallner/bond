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
  nowSeconds: number;
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
/// A claim leases its rows for 2 minutes. 25 occurrences and 25 signals at 10
/// phones each is 10 chunks, 80 s if every request times out, so all of it is
/// recorded before the lease ends and nothing is claimed twice.
export const CLAIM_LIMIT = 25;
/// Claim again while there is more, stopping well inside the function's limit.
const BUDGET_MS = 60_000;

async function inChunks<T>(items: T[], run: (item: T) => Promise<void>): Promise<void> {
  for (let start = 0; start < items.length; start += CHUNK) {
    await Promise.all(items.slice(start, start + CHUNK).map(run));
  }
}

type Outcome = "sent" | "dead" | "rejected" | "retry";

async function deliver(push: Occurrence, device: Device, authorization: string, deps: SendDeps): Promise<Outcome> {
  const request = apnsRequest(push, device, deps.topic, deps.nowSeconds);
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
    if (isDeadToken(response.status, text)) {
      // Only while the row is the one claimed: the phone may have registered since.
      const { error } = await deps.rpc("delete_push_device", {
        p_token: device.token,
        p_user: push.userId,
        p_seen: device.updated_at,
      });
      if (error) deps.log(`dead token not removed: ${error.message}`);
      return "dead";
    }
    if (isProviderTokenRefused(response.status, text)) await deps.dropProviderToken();
    deps.log(`APNs ${response.status} ${reason(text)}`);
    return isPassing(response.status, text) ? "retry" : "rejected";
  } catch (err) {
    // The name only: a fetch error message can carry the device URL.
    deps.log(`APNs request failed: ${err instanceof Error ? err.name : "unknown"}`);
    return "retry";
  }
}

type Counts = Omit<SendResult["body"], "ok" | "error">;

async function record(push: Occurrence, retry: boolean, finished: string[], counts: Counts, deps: SendDeps) {
  const key = { p_reminder_id: push.reminderId, p_due_at: push.dueAt, p_user_id: push.userId };
  if (retry) {
    // The retry goes only to the phones that are still owed it.
    if (finished.length === 0) return;
    const { error } = await deps.rpc("mark_push_sent", { ...key, p_tokens: finished });
    if (error) deps.log(`sent phones not recorded: ${error.message}`);
    return;
  }
  const { error } = await deps.rpc("ack_reminder_push", key);
  if (error) deps.log(`ack failed: ${error.message}`);
  else counts.acked += 1;
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
    if (pushes.length === 0) break;

    let authorization: string;
    try {
      authorization = `bearer ${await deps.providerToken()}`;
    } catch (err) {
      // Nothing is recorded, so every claimed row is sent again after its lease.
      deps.log(`provider token failed: ${err instanceof Error ? err.name : "unknown"}`);
      return { status: 500, body: { ok: false, ...counts, error: "provider token failed" } };
    }

    const retry = new Set<Occurrence>();
    const finished = new Map<Occurrence, string[]>(pushes.map((push) => [push, []]));
    const sends = pushes.flatMap((push) => push.devices.map((device) => ({ push, device })));
    await inChunks(sends, async ({ push, device }) => {
      const outcome = await deliver(push, device, authorization, deps);
      if (outcome === "retry") {
        counts.failed += 1;
        retry.add(push);
        return;
      }
      if (outcome === "sent") counts.sent += 1;
      else if (outcome === "dead") counts.deadTokens += 1;
      else counts.rejected += 1;
      finished.get(push)!.push(device.token);
    });
    await inChunks(pushes, (push) => record(push, retry.has(push), finished.get(push)!, counts, deps));

    if (pushes.length < CLAIM_LIMIT || deps.elapsedMs() > BUDGET_MS) break;
  }

  return { status: 200, body: { ok: counts.failed === 0, ...counts } };
}
