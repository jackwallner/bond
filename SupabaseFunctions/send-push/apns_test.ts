import { assert, assertEquals } from "jsr:@std/assert@1";
import { apnsRequest, type ClaimedPush, isDeadToken } from "./apns.ts";

const push: ClaimedPush = {
  reminder_id: "e1000000-0000-0000-0000-000000000001",
  couple_id: "d0000000-0000-0000-0000-00000000000d",
  title: "Bring flowers",
  body: "The yellow ones",
  love_language: "gifts",
  silent: false,
  token: "abc",
  env: "production",
};

Deno.test("an alert carries the reminder and the keys a tap routes on", () => {
  const request = apnsRequest(push, "com.jackwallner.bond", 1000);
  assertEquals(request.url, "https://api.push.apple.com/3/device/abc");
  assertEquals(request.headers["apns-push-type"], "alert");
  assertEquals(request.headers["apns-priority"], "10");
  assertEquals(request.headers["apns-topic"], "com.jackwallner.bond");
  assertEquals(request.headers["apns-collapse-id"], push.reminder_id);
  const body = JSON.parse(request.body);
  assertEquals(body.aps.alert, { title: "Bring flowers", body: "The yellow ones" });
  assertEquals(body.aps["thread-id"], "gifts");
  assertEquals(body.reminder_id, push.reminder_id);
  assertEquals(body.couple_id, push.couple_id);
});

Deno.test("no note means no empty body line", () => {
  const body = JSON.parse(apnsRequest({ ...push, body: null }, "t", 0).body);
  assertEquals(body.aps.alert, { title: "Bring flowers" });
});

Deno.test("a sandbox device goes to the sandbox host", () => {
  assert(apnsRequest({ ...push, env: "sandbox" }, "t", 0).url.startsWith("https://api.sandbox.push.apple.com/"));
});

Deno.test("a silent push shows nothing and meets Apple's background rules", () => {
  const request = apnsRequest({ ...push, silent: true }, "t", 0);
  assertEquals(request.headers["apns-push-type"], "background");
  assertEquals(request.headers["apns-priority"], "5");
  assertEquals(JSON.parse(request.body).aps, { "content-available": 1 });
});

Deno.test("only permanent refusals remove a token", () => {
  assert(isDeadToken(410, '{"reason":"Unregistered"}'));
  assert(isDeadToken(400, '{"reason":"BadDeviceToken"}'));
  assert(!isDeadToken(403, '{"reason":"InvalidProviderToken"}'));
  assert(!isDeadToken(500, '{"reason":"InternalServerError"}'));
});
