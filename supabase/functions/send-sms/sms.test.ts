// Run with Node (>=22.6):  node --test supabase/functions/send-sms/sms.test.ts
// or Deno:                 deno test supabase/functions/send-sms/sms.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { messageType, sendViaPhilSms } from "./sms.ts";

const cfg = { token: "TOKEN123", senderId: "STIBALIUAG" };
const row = { id: "1", recipient: "639171234567", message: "STI Baliuag: Juan tapped IN at 7:02 AM." };

function fakeFetch(status: number, body: unknown, capture?: { url?: string; init?: RequestInit }) {
  return (async (url: string, init: RequestInit) => {
    if (capture) { capture.url = url; capture.init = init; }
    return new Response(typeof body === "string" ? body : JSON.stringify(body), { status });
  }) as unknown as typeof fetch;
}

test("messageType: ASCII is plain, non-GSM characters become unicode", () => {
  assert.equal(messageType("Juan tapped IN at 7:02 AM."), "plain");
  assert.equal(messageType("Ana didn’t tap out"), "unicode");
});

test("posts the documented PhilSMS request", async () => {
  const cap: { url?: string; init?: RequestInit } = {};
  const res = await sendViaPhilSms(row, cfg, fakeFetch(200, { status: "success", data: {} }, cap));
  assert.equal(res.ok, true);
  assert.equal(cap.url, "https://dashboard.philsms.com/api/v3/sms/send");
  assert.equal(cap.init?.method, "POST");
  assert.equal((cap.init?.headers as Record<string, string>).Authorization, "Bearer TOKEN123");
  assert.deepEqual(JSON.parse(cap.init?.body as string), {
    recipient: "639171234567",
    sender_id: "STIBALIUAG",
    type: "plain",
    message: row.message,
  });
});

test("baseUrl can be overridden", async () => {
  const cap: { url?: string; init?: RequestInit } = {};
  await sendViaPhilSms(row, { ...cfg, baseUrl: "https://example.test/api/v3" }, fakeFetch(200, { status: "success" }, cap));
  assert.equal(cap.url, "https://example.test/api/v3/sms/send");
});

test("API-level error (HTTP 200, status:error) is a failure with the provider's message", async () => {
  const res = await sendViaPhilSms(row, cfg, fakeFetch(200, { status: "error", message: "Insufficient balance" }));
  assert.equal(res.ok, false);
  assert.equal(!res.ok && res.error, "Insufficient balance");
});

test("HTTP error with a non-JSON body reports the status code", async () => {
  const res = await sendViaPhilSms(row, cfg, fakeFetch(502, "<html>Bad gateway</html>"));
  assert.equal(res.ok, false);
  assert.equal(!res.ok && res.error, "PhilSMS HTTP 502");
});

test("network failure is a failure, not a throw", async () => {
  const boom = (async () => { throw new Error("connection reset"); }) as unknown as typeof fetch;
  const res = await sendViaPhilSms(row, cfg, boom);
  assert.equal(res.ok, false);
  assert.match(!res.ok ? res.error : "", /connection reset/);
});

test("missing recipient never calls the network", async () => {
  let called = false;
  const spy = (async () => { called = true; return new Response("{}"); }) as unknown as typeof fetch;
  const res = await sendViaPhilSms({ ...row, recipient: null }, cfg, spy);
  assert.equal(res.ok, false);
  assert.equal(called, false);
});

test("the token is never echoed into an error", async () => {
  const res = await sendViaPhilSms(row, cfg, fakeFetch(401, { status: "error", message: "Unauthenticated." }));
  assert.equal(JSON.stringify(res).includes("TOKEN123"), false);
});
