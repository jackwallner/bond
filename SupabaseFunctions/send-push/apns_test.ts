import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  apnsRequest,
  type ClaimedRow,
  isDeadToken,
  isProviderTokenRefused,
  MAX_PAYLOAD_BYTES,
  occurrence,
  reason,
} from "./apns.ts";

const device = { token: "ab".repeat(32), env: "production" as const, updated_at: "2026-11-06T17:00:00+00:00" };
const row: ClaimedRow = {
  reminder_id: "e1000000-0000-0000-0000-000000000001",
  couple_id: "d0000000-0000-0000-0000-00000000000d",
  title: "Bring flowers",
  body: "The yellow ones",
  love_language: "gifts",
  silent: false,
  user_id: "b0000000-0000-0000-0000-00000000000b",
  due_at: "2026-11-06T18:00:00.123456+00:00",
  devices: [device],
};
const push = occurrence(row);
const due = Date.parse("2026-11-06T18:00:00Z") / 1000;

Deno.test("an alert carries the reminder and the keys a tap routes on", () => {
  const request = apnsRequest(push, device, "com.jackwallner.bond", due + 30);
  assertEquals(request.url, `https://api.push.apple.com/3/device/${device.token}`);
  assertEquals(request.headers["apns-push-type"], "alert");
  assertEquals(request.headers["apns-priority"], "10");
  assertEquals(request.headers["apns-topic"], "com.jackwallner.bond");
  const body = JSON.parse(request.body);
  assertEquals(body.aps.alert, { title: "Bring flowers", body: "The yellow ones" });
  assertEquals(body.aps["thread-id"], "gifts");
  assertEquals(body.reminder_id, push.reminderId);
  assertEquals(body.couple_id, push.coupleId);
});

Deno.test("APNs drops it once it is as late as the claim would skip it", () => {
  const late = apnsRequest(push, device, "t", due + 45 * 60);
  assertEquals(late.headers["apns-expiration"], String(due + 3600), "a retry does not extend it");
});

Deno.test("a retry of the same occurrence replaces it, the next one does not", () => {
  const first = apnsRequest(push, device, "t", due).headers["apns-collapse-id"];
  const retry = apnsRequest(push, device, "t", due + 120).headers["apns-collapse-id"];
  const tomorrow = apnsRequest(
    occurrence({ ...row, due_at: "2026-11-07T18:00:00+00:00" }),
    device,
    "t",
    due,
  ).headers["apns-collapse-id"];
  assertEquals(first, `${push.reminderId}.${due}`);
  assertEquals(first, retry);
  assert(first !== tomorrow);
  assert(new TextEncoder().encode(first).length <= 64, "APNs allows 64 bytes");
});

Deno.test("no note means no empty body line", () => {
  const body = JSON.parse(apnsRequest(occurrence({ ...row, body: null }), device, "t", 0).body);
  assertEquals(body.aps.alert, { title: "Bring flowers" });
});

Deno.test("a long note is cut so APNs takes it", () => {
  for (const note of ["x".repeat(5000), "é".repeat(3000), "👩‍👩‍👧".repeat(400)]) {
    const request = apnsRequest(occurrence({ ...row, body: note }), device, "t", 0);
    assert(new TextEncoder().encode(request.body).length < MAX_PAYLOAD_BYTES, "under the limit");
    const sent: string = JSON.parse(request.body).aps.alert.body;
    assert(sent.endsWith("…"));
    assert(note.startsWith(sent.slice(0, -1)), "cut at a whole character");
    assert(sent.length > 500, "and keeps as much as fits");
  }
  const long = apnsRequest(occurrence({ ...row, title: "t".repeat(5000), body: "b" }), device, "t", 0);
  const alert = JSON.parse(long.body).aps.alert;
  assert(new TextEncoder().encode(long.body).length < MAX_PAYLOAD_BYTES);
  assert(alert.title.endsWith("…"));
});

Deno.test("a sandbox device goes to the sandbox host", () => {
  assert(apnsRequest(push, { ...device, env: "sandbox" }, "t", 0).url.startsWith("https://api.sandbox.push.apple.com/"));
});

Deno.test("a silent push shows nothing and meets Apple's background rules", () => {
  const request = apnsRequest(occurrence({ ...row, silent: true }), device, "t", 0);
  assertEquals(request.headers["apns-push-type"], "background");
  assertEquals(request.headers["apns-priority"], "5");
  assertEquals(request.headers["apns-collapse-id"], undefined);
  assertEquals(JSON.parse(request.body).aps, { "content-available": 1 });
});

Deno.test("a phone signal carries no reminder at all", () => {
  const signal = occurrence({
    reminder_id: null, couple_id: null, title: null, body: null, love_language: null,
    silent: true, user_id: row.user_id, due_at: row.due_at, devices: [device],
  });
  assertEquals(JSON.parse(apnsRequest(signal, device, "t", 0).body), { aps: { "content-available": 1 } });
});

Deno.test("only permanent refusals remove a token", () => {
  assert(isDeadToken(410, '{"reason":"Unregistered"}'));
  assert(isDeadToken(400, '{"reason":"BadDeviceToken"}'));
  assert(!isDeadToken(403, '{"reason":"InvalidProviderToken"}'));
  assert(!isDeadToken(500, '{"reason":"InternalServerError"}'));
  assert(isProviderTokenRefused(403, '{"reason":"ExpiredProviderToken"}'));
  assertEquals(reason('{"reason":"TooManyRequests"}'), "TooManyRequests");
  assertEquals(reason("<html>"), "unknown");
});
