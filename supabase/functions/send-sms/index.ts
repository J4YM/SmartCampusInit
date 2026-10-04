// send-sms — drains public.sms_outbox through PhilSMS.
//
// Called by the database only (pg_net from the sms_outbox insert trigger and
// the 5-minute sweeper cron job — see supabase/add_sms_alerts_schema.sql), not
// by the Flutter app. The PhilSMS token therefore never ships in the client.
//
// Deploy with JWT verification off (the caller is Postgres, not a signed-in
// user) — the shared secret below is the gate instead:
//   supabase functions deploy send-sms --no-verify-jwt
//   supabase secrets set PHILSMS_API_TOKEN=... PHILSMS_SENDER_ID=... SMS_WEBHOOK_SECRET=...
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { sendViaPhilSms, type OutboxRow } from "./sms.ts";

const BATCH_SIZE = 20;
const MAX_BATCHES = 10; // 200 SMS per invocation; the sweeper picks up the rest.
const CONCURRENCY = 5;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const secret = Deno.env.get("SMS_WEBHOOK_SECRET");
  const presented = req.headers.get("x-sms-secret") ?? "";
  if (!secret || !timingSafeEqual(presented, secret)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const token = Deno.env.get("PHILSMS_API_TOKEN");
  const senderId = Deno.env.get("PHILSMS_SENDER_ID");
  if (!token || !senderId) {
    return json({ error: "PHILSMS_API_TOKEN / PHILSMS_SENDER_ID not configured" }, 500);
  }

  // Optional; defaults to dashboard.philsms.com (see sms.ts for why).
  const baseUrl = Deno.env.get("PHILSMS_BASE_URL") || undefined;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let sent = 0;
  let failed = 0;

  for (let batch = 0; batch < MAX_BATCHES; batch++) {
    const { data, error } = await supabase.rpc("claim_sms_batch", {
      p_limit: BATCH_SIZE,
    });
    if (error) return json({ error: error.message, sent, failed }, 500);

    const rows = (data ?? []) as OutboxRow[];
    if (rows.length === 0) break;

    for (let i = 0; i < rows.length; i += CONCURRENCY) {
      await Promise.all(
        rows.slice(i, i + CONCURRENCY).map(async (row) => {
          const result = await sendViaPhilSms(row, { token, senderId, baseUrl });
          if (result.ok) {
            sent++;
            await supabase.from("sms_outbox").update({
              status: "sent",
              sent_at: new Date().toISOString(),
              error: null,
              provider_response: result.response,
            }).eq("id", row.id);
          } else {
            failed++;
            await supabase.from("sms_outbox").update({
              status: "failed",
              error: result.error,
              provider_response: result.response ?? null,
            }).eq("id", row.id);
          }
        }),
      );
    }

    if (rows.length < BATCH_SIZE) break;
  }

  return json({ sent, failed });
});
