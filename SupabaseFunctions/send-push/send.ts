// One run of send-push: claim what is due, send it, acknowledge what went out.
// Everything outside (the database, APNs, the clock) comes in through `deps`.

import {
  apnsRequest,
  type ClaimedRow,
  type Device,
  isDeadToken,
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
  dropProviderToken(): void;
  topic: string;
  nowSeconds: number;
  log(message: string): void;
}

export interface SendResult {
  status: number;
  body: { ok: boolean; sent: number; deadTokens: number; failed: number; acked: number; error?: string };
}

/// How many requests are in flight at once, so a large batch cannot exhaust the function.
export const CHUNK = 50;

async function inChunks<T>(items: T[], run: (item: T) => Promise<void>): Promise<void> {
  for (let start = 0; start < items.length; start += CHUNK) {
    await Promise.all(items.slice(start, start + CHUNK).map(run));
  }
}

type Outcome = "sent" | "dead" | "retry";

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
      // Only while the token is still this user's: it may have moved since the claim.
      const { error } = push.legacy
        ? await deps.rpc("delete_push_device", { p_token: device.token })
        : await deps.rpc("delete_push_device", { p_token: device.token, p_user: push.userId });
      if (error) deps.log(`dead token not removed: ${error.message}`);
      return "dead";
    }
    if (isProviderTokenRefused(response.status, text)) deps.dropProviderToken();
    deps.log(`APNs ${response.status} ${reason(text)}`);
    return "retry";
  } catch (err) {
    // The name only: a fetch error message can carry the device URL.
    deps.log(`APNs request failed: ${err instanceof Error ? err.name : "unknown"}`);
    return "retry";
  }
}

export async function sendDue(deps: SendDeps): Promise<SendResult> {
  const counts = { sent: 0, deadTokens: 0, failed: 0, acked: 0 };

  const { data, error } = await deps.rpc("claim_due_reminder_pushes");
  if (error) {
    deps.log(`claim failed: ${error.message}`);
    return { status: 500, body: { ok: false, ...counts, error: "claim failed" } };
  }
  const pushes = ((data ?? []) as ClaimedRow[]).map(occurrence);
  if (pushes.length === 0) return { status: 200, body: { ok: true, ...counts } };

  let authorization: string;
  try {
    authorization = `bearer ${await deps.providerToken()}`;
  } catch (err) {
    // Nothing is acknowledged, so every claimed row is sent again after its lease.
    deps.log(`provider token failed: ${err instanceof Error ? err.name : "unknown"}`);
    return { status: 500, body: { ok: false, ...counts, error: "provider token failed" } };
  }

  const retry = new Set<Occurrence>();
  const sends = pushes.flatMap((push) => push.devices.map((device) => ({ push, device })));
  await inChunks(sends, async ({ push, device }) => {
    const outcome = await deliver(push, device, authorization, deps);
    if (outcome === "sent") counts.sent += 1;
    else if (outcome === "dead") counts.deadTokens += 1;
    else {
      counts.failed += 1;
      retry.add(push);
    }
  });

  // A dead token alone is not a reason to try again. A passing failure on any
  // device is: the phones that got it see the retry replace their copy.
  const done = pushes.filter((push) => !push.legacy && push.dueAt && !retry.has(push));
  await inChunks(done, async (push) => {
    const { error } = await deps.rpc("ack_reminder_push", {
      p_reminder_id: push.reminderId,
      p_due_at: push.dueAt,
      p_user_id: push.userId,
    });
    if (error) deps.log(`ack failed: ${error.message}`);
    else counts.acked += 1;
  });

  return { status: 200, body: { ok: counts.failed === 0, ...counts } };
}
