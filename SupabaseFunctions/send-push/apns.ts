// What send-push asks APNs to do, kept free of I/O so it can be tested.

export interface Device {
  token: string;
  env: "production" | "sandbox";
}

/// A row from claim_due_reminder_pushes. Since 0019 it is one occurrence with
/// its due time, target and devices, and a phone signal has no reminder. Before
/// 0019 it was one row per device (token, env) that the claim had already moved on.
export interface ClaimedRow {
  reminder_id: string | null;
  couple_id: string | null;
  title: string | null;
  body: string | null;
  love_language: string | null;
  silent: boolean;
  user_id?: string | null;
  due_at?: string | null;
  devices?: Device[] | null;
  token?: string;
  env?: Device["env"];
}

export interface Occurrence {
  reminderId: string | null;
  coupleId: string | null;
  title: string;
  body: string | null;
  loveLanguage: string | null;
  silent: boolean;
  userId: string | null;
  /// Exactly as the claim returned it, because the acknowledgement compares it.
  dueAt: string | null;
  devices: Device[];
  /// A pre-0019 row: already moved on by the claim, so it is never acknowledged.
  legacy: boolean;
}

export function occurrence(row: ClaimedRow): Occurrence {
  const legacy = typeof row.token === "string";
  return {
    reminderId: row.reminder_id,
    coupleId: row.couple_id,
    title: row.title ?? "",
    body: row.body,
    loveLanguage: row.love_language,
    silent: row.silent,
    userId: row.user_id ?? null,
    dueAt: legacy ? null : row.due_at ?? null,
    devices: legacy ? [{ token: row.token!, env: row.env ?? "production" }] : row.devices ?? [],
    legacy,
  };
}

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

/// The claim skips what is an hour late, so APNs keeps it no longer than that.
const STALE_SECONDS = 3_600;
/// APNs refuses a larger payload.
export const MAX_PAYLOAD_BYTES = 4_096;

export function dueSeconds(push: Occurrence): number | null {
  if (!push.dueAt) return null;
  const ms = Date.parse(push.dueAt);
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
}

export function apnsRequest(push: Occurrence, device: Device, topic: string, nowSeconds: number) {
  const due = dueSeconds(push);
  const headers: Record<string, string> = {
    "apns-topic": topic,
    "apns-push-type": push.silent ? "background" : "alert",
    // Apple requires 5 for a background push.
    "apns-priority": push.silent ? "5" : "10",
    "apns-expiration": String(Math.min(nowSeconds, due ?? nowSeconds) + STALE_SECONDS),
    "content-type": "application/json",
  };
  // One id per occurrence, so a retry replaces the copy a phone already got.
  if (!push.silent && push.reminderId) {
    headers["apns-collapse-id"] = due === null ? push.reminderId : `${push.reminderId}.${due}`;
  }

  return {
    url: `${HOSTS[device.env] ?? HOSTS.production}/3/device/${device.token}`,
    headers,
    body: payload(push),
  };
}

function bytes(text: string): number {
  return new TextEncoder().encode(text).length;
}

function graphemes(text: string): string[] {
  return [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)].map((s) => s.segment);
}

/// The longest start of `text` (whole characters, then an ellipsis) that `fits`
/// accepts, or null when not even the ellipsis does.
function shorten(text: string, fits: (candidate: string) => boolean): string | null {
  const parts = graphemes(text);
  let low = 0;
  let high = parts.length - 1;
  let best: string | null = null;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    const candidate = parts.slice(0, mid).join("") + "…";
    if (fits(candidate)) {
      best = candidate;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return best;
}

/// The JSON APNs gets. A long note is cut so the whole payload stays under
/// Apple's limit; the full note is still in the app.
export function payload(push: Occurrence): string {
  const build = (title: string, body: string | null) => {
    const aps: Record<string, unknown> = push.silent ? { "content-available": 1 } : {
      alert: body ? { title, body } : { title },
      sound: "default",
      ...(push.loveLanguage ? { "thread-id": push.loveLanguage } : {}),
    };
    // The same keys a local notification carries, so a tap routes the same way.
    const json: Record<string, unknown> = { aps };
    if (push.reminderId) json.reminder_id = push.reminderId;
    if (push.coupleId) json.couple_id = push.coupleId;
    if (push.loveLanguage) json.love_language = push.loveLanguage;
    return JSON.stringify(json);
  };
  const fits = (json: string) => bytes(json) < MAX_PAYLOAD_BYTES;

  let title = push.title;
  let body = push.body;
  if (fits(build(title, body))) return build(title, body);
  if (body) {
    body = shorten(body, (candidate) => fits(build(title, candidate)));
    if (body !== null) return build(title, body);
  }
  title = shorten(title, (candidate) => fits(build(candidate, null))) ?? "";
  return build(title, null);
}

/// True when APNs says this token will never work again.
export function isDeadToken(status: number, responseBody: string): boolean {
  return status === 410 || responseBody.includes("BadDeviceToken") ||
    responseBody.includes("Unregistered");
}

/// True when APNs refused our provider token, which a fresh one may fix.
export function isProviderTokenRefused(status: number, responseBody: string): boolean {
  return status === 403 &&
    (responseBody.includes("ExpiredProviderToken") || responseBody.includes("InvalidProviderToken"));
}

/// APNs' reason code alone, never the token or URL.
export function reason(responseBody: string): string {
  try {
    const parsed = JSON.parse(responseBody);
    return typeof parsed?.reason === "string" ? parsed.reason : "unknown";
  } catch {
    return "unknown";
  }
}
