// send-email — drains public.email_outbox through Resend.
//
// Called by the database only (pg_net from the email_outbox insert trigger and
// the 5-minute sweeper cron job — see supabase/add_escalation_reports.sql),
// never by the Flutter app, so the Resend API key never ships in the client.
// Mirrors send-sms.
//
// Deploy with JWT verification off (the caller is Postgres):
//   supabase functions deploy send-email --no-verify-jwt
//   supabase secrets set RESEND_API_KEY=... EMAIL_FROM="STI Baliuag <noreply@yourdomain>" \
//                        EMAIL_WEBHOOK_SECRET=...
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

const BATCH_SIZE = 20;
const MAX_BATCHES = 5;

interface OutboxRow {
  id: string;
  recipient: string;
  subject: string;
  body: string;
}

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

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const secret = Deno.env.get("EMAIL_WEBHOOK_SECRET");
  const presented = req.headers.get("x-email-secret") ?? "";
  if (!secret || !timingSafeEqual(presented, secret)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("EMAIL_FROM");
  if (!apiKey || !from) {
    return json({ error: "RESEND_API_KEY / EMAIL_FROM not configured" }, 500);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let sent = 0;
  let failed = 0;

  for (let batch = 0; batch < MAX_BATCHES; batch++) {
    const { data, error } = await supabase.rpc("claim_email_batch", {
      p_limit: BATCH_SIZE,
    });
    if (error) return json({ error: error.message, sent, failed }, 500);

    const rows = (data ?? []) as OutboxRow[];
    if (rows.length === 0) break;

    for (const row of rows) {
      try {
        const res = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from,
            to: [row.recipient],
            subject: row.subject,
            text: row.body,
            html: `<p>${escapeHtml(row.body).replace(/\n/g, "<br>")}</p>`,
          }),
        });
        if (res.ok) {
          sent++;
          await supabase.from("email_outbox").update({
            status: "sent",
            sent_at: new Date().toISOString(),
            error: null,
          }).eq("id", row.id);
        } else {
          failed++;
          await supabase.from("email_outbox").update({
            status: "failed",
            error: `Resend ${res.status}: ${(await res.text()).slice(0, 300)}`,
          }).eq("id", row.id);
        }
      } catch (e) {
        failed++;
        await supabase.from("email_outbox").update({
          status: "failed",
          error: String(e).slice(0, 300),
        }).eq("id", row.id);
      }
    }

    if (rows.length < BATCH_SIZE) break;
  }

  return json({ sent, failed });
});
