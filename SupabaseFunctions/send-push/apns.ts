// What send-push asks APNs to do, kept free of I/O so it can be tested.

export interface ClaimedPush {
  reminder_id: string;
  couple_id: string;
  title: string;
  body: string | null;
  love_language: string;
  silent: boolean;
  token: string;
  env: "production" | "sandbox";
}

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

const ONE_DAY_SECONDS = 86_400;

export function apnsRequest(push: ClaimedPush, topic: string, nowSeconds: number) {
  const headers: Record<string, string> = {
    "apns-topic": topic,
    "apns-push-type": push.silent ? "background" : "alert",
    // Apple requires 5 for a background push.
    "apns-priority": push.silent ? "5" : "10",
    "apns-expiration": String(nowSeconds + ONE_DAY_SECONDS),
    "content-type": "application/json",
  };
  if (!push.silent) headers["apns-collapse-id"] = push.reminder_id;

  const aps: Record<string, unknown> = push.silent ? { "content-available": 1 } : {
    alert: push.body ? { title: push.title, body: push.body } : { title: push.title },
    sound: "default",
    "thread-id": push.love_language,
  };

  return {
    url: `${HOSTS[push.env]}/3/device/${push.token}`,
    headers,
    // The same keys a local notification carries, so a tap routes the same way.
    body: JSON.stringify({
      aps,
      reminder_id: push.reminder_id,
      couple_id: push.couple_id,
      love_language: push.love_language,
    }),
  };
}

/// True when APNs says this token will never work again.
export function isDeadToken(status: number, responseBody: string): boolean {
  return status === 410 || responseBody.includes("BadDeviceToken") ||
    responseBody.includes("Unregistered");
}
