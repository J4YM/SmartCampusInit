// PhilSMS client logic, kept free of Deno/Supabase globals so it can be unit
// tested under plain Node (see sms.test.ts) and imported unchanged by index.ts.
//
// API (PhilSMS developer docs). The host matters: an API token only works on
// the host that issued it. Tokens from this project's PhilSMS account are
// valid on dashboard.philsms.com and rejected ("Unauthenticated.") by
// app.philsms.com, which the public docs page happens to be served from.
// Override with the PHILSMS_BASE_URL secret if PhilSMS ever moves it.
//   POST https://dashboard.philsms.com/api/v3/sms/send
//   Authorization: Bearer <token>
//   body: { recipient: "639XXXXXXXXX", sender_id, type: "plain"|"unicode", message }
//   ok:    { "status": "success", "data": ... }
//   error: { "status": "error", "message": "..." }

export interface OutboxRow {
  id: string;
  recipient: string | null;
  message: string;
}

export interface PhilSmsConfig {
  token: string;
  senderId: string;
  baseUrl?: string;
}

export type SendResult =
  | { ok: true; response: unknown }
  | { ok: false; error: string; response?: unknown };

export const DEFAULT_BASE_URL = "https://dashboard.philsms.com/api/v3";

// Printable ASCII + newline is always safe as GSM "plain". Anything else
// (curly quotes, accented capitals, emoji) is sent as "unicode" so the
// provider does not mangle or reject it.
export function messageType(message: string): "plain" | "unicode" {
  return /^[\x20-\x7E\r\n]*$/.test(message) ? "plain" : "unicode";
}

export async function sendViaPhilSms(
  row: OutboxRow,
  cfg: PhilSmsConfig,
  fetchFn: typeof fetch = fetch,
): Promise<SendResult> {
  if (!row.recipient) {
    return { ok: false, error: "No recipient on outbox row" };
  }

  let res: Response;
  try {
    res = await fetchFn(`${cfg.baseUrl ?? DEFAULT_BASE_URL}/sms/send`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${cfg.token}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        recipient: row.recipient,
        sender_id: cfg.senderId,
        type: messageType(row.message),
        message: row.message,
      }),
    });
  } catch (e) {
    return { ok: false, error: `Network error: ${(e as Error).message}` };
  }

  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    // Non-JSON body (gateway error page, etc.) — fall through to HTTP status.
  }

  const status = (body as { status?: string } | null)?.status;
  if (res.ok && status === "success") {
    return { ok: true, response: body };
  }

  const detail = (body as { message?: string } | null)?.message;
  return {
    ok: false,
    error: detail ?? `PhilSMS HTTP ${res.status}`,
    response: body ?? undefined,
  };
}
