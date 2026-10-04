# Kiosk Offline-First (Drift) — Design

Date: 2026-10-04
Status: Draft for review

## Goal

The Windows kiosk (`lib/main_kiosk.dart`, `lib/kiosk/capstone_kiosk_scan_host.dart`)
keeps working with no internet. A student or security officer never sees a
network error, and no tap or report is lost. Offline work is stored locally
and synced automatically when connectivity returns.

### In scope (must work offline)

1. Student and staff card identification.
2. Attendance taps, including the welcome popup with in/out direction.
3. Security violation report plus admission slip creation and printing.
4. Offense list (reference data for the report flow).

### Out of scope

- Web or Android kiosk (Windows only).
- Encrypting the local database (SQLCipher). Noted as a known risk.
- Making the web slip-lookup page (`lib/main_slip.dart`) work offline.
- Changes to server-side RPC logic.

## Decisions

- **Drift (SQLite) + a small custom outbox**, not Brick. The server owns the tap
  rules in the `record_rfid_tap` RPC, which Brick's table-upsert queue cannot
  replay. The hard problem is the local tap logic, which needs real SQL queries.
- **No new server tables or RPCs.** `record_rfid_tap` already accepts
  `p_tapped_at`. Replays are idempotent: a repeat of an identical tap falls
  inside the 5-second debounce and returns the existing row.
  `submit_admission_slip` already takes a client-generated `slipId`, so a
  duplicate-key response on replay is treated as success.
- **The kiosk decides taps locally, always** (online or offline), then syncs.
  One code path, no online/offline behavior fork.

## Architecture

New package `packages/kiosk_offline` (no UI). Keeps SQLite and Drift out of the
web build's dependency graph concerns (Netlify pins Flutter 3.24.5; Drift
version constraints must be verified against Dart 3.5.4 before adding).
`capstone_kiosk_scan_host.dart` calls this package instead of Supabase directly.

Units, each independently testable:

| Unit | Responsibility | Depends on |
|---|---|---|
| `KioskDatabase` | Drift schema, DAOs | drift, sqlite3 |
| `ReferenceSync` | Pull students/staff/offenses into cache | Supabase client, `KioskDatabase` |
| `TapEngine` | Local in/out decision, writes `local_taps` + outbox | `KioskDatabase`, `TapRules` |
| `TapRules` | Pure Dart port of server rules | none |
| `Outbox` | Enqueue, ordered drain, backoff, rejection handling | `KioskDatabase`, Supabase client |
| `ConnectivityMonitor` | Probe + status stream | http |
| `SyncCoordinator` | Owns timers/triggers for pull and drain | the above |

## Local schema

Cache (read-only, refreshed from server): `students` (id, rfid_uid, name,
student_number, year_level, section, course), `staff` (id, rfid_card_id, name,
role), `offenses`, and `professors` only if the self-report "Teacher / Adviser"
picker needs it (confirm when reading the report flow).

Local state: `local_taps` (id, student_id nullable, rfid_uid, reader_usb_serial,
direction, tapped_at), `outbox` (id, type `tap|slip`, payload JSON, created_at,
tapped_at nullable, attempts, status `pending|rejected`, last_error),
`sync_meta` (table name, last_synced_at).

## Reference data sync

- Startup: full pull if the cache is empty, otherwise delta pull.
- Every 5 minutes while online, and on each offline→online transition.
- Periodic full re-pull (daily) to catch deleted or reassigned cards, which
  deltas cannot show.
- All lookups (`identifyStudent`, `identifyStaff`, offense list) read the local
  DB only. Stale-while-revalidate: the background refresh never blocks a read.
- The cache is on disk, so a reboot while offline still works.

## Tap flow

1. Resolve `rfid_uid` against the local `students` cache.
2. `TapRules` decides, mirroring `record_rfid_tap`:
   - School day = `((tapped_at in Asia/Manila) + 5h30m).date` (rollover 6:30 PM
     Manila).
   - Debounce: a tap within 5 seconds of the student's last tap this school day
     echoes that tap, no new row.
   - No tap yet: `in`. Last was `in`: `out` if at least `tapOutMinWait` has
     elapsed, otherwise reject with the server's message. Last was `out`:
     reject ("You have already tapped in and out for today.").
   - Unrecognized card: logged as `in` every time.
3. Insert into `local_taps` and `outbox` (one DB transaction), with the real
   `tappedAt`.
4. Show the welcome popup immediately.

`tapOutMinWait` is one configurable constant: default **1 hour** (production),
overridable via dart-define (e.g. 5 seconds for dev). It must match the live
SQL; the repo currently contains two versions
(`add_rfid_tap_daily_limit.sql` enforces 5 s, `fix_rfid_school_day_timezone.sql`
enforces 1 h). Rule vectors are shared between Dart tests and documented
against the SQL so drift is caught.

## Outbox and sync triggers

Entry types: `tap` (calls `record_rfid_tap` with `p_tapped_at`) and `slip`
(calls `submit_admission_slip`).

Drain triggers:
1. Immediately after each enqueue (online latency is effectively unchanged).
2. A probe timer: every 15 s while the outbox is non-empty or the kiosk is
   offline; every 60 s when idle and online. A successful probe triggers a drain.
3. App startup (drains whatever survived a reboot or crash).

Drain rules:
- Strict `tappedAt`/`created_at` order; one entry at a time.
- Network error: stay `pending`, exponential backoff (cap 60 s), keep order.
- Server rejection (`PostgrestException`: unknown/deactivated reader, rule
  violation): mark `rejected` with the message, continue to the next entry. Never
  retried automatically.
- Slip duplicate-key: treat as success.
- Success: delete the entry.
- Rejections are also written to the audit log when online, so loss is never
  silent.

## Slips and violations offline

The slip is built, printed and enqueued as it is today; `submit_admission_slip`
runs on replay. **Known limitation:** the slip's QR points at the web slip page,
which reads from the server, so scanning shows "invalid link" until the kiosk
has synced.

## UI

- Status chip on the kiosk: "Online", "Offline · N pending", "N failed".
- Diagnostics view (opened via the chip) lists rejected entries with their
  messages and timestamps. Read-only; no retry button in v1.
- Unknown card while offline shows the existing "not recognized" state.

## Connectivity detection

An HTTPS request to the Supabase REST host (3 s timeout), not adapter state,
because "connected, no internet" is the common failure.

## Testing

- `TapRules` unit tests with shared vectors: 18:29/18:30 Manila rollover,
  debounce, in then out after the wait, rejection before the wait, third tap
  rejected, unknown card.
- `Outbox` tests (in-memory Drift): ordering, backoff on network error,
  rejection does not block the queue, duplicate replay is idempotent, survival
  across a simulated restart.
- `ReferenceSync` tests with a fake client: full vs delta pull, offline reads.
- Manual Windows checklist: disconnect network, tap several cards, file a
  report, reconnect, verify the server rows and timestamps.

## Risks

- Dart rule port can drift from the SQL; mitigated by shared vectors and the
  single `tapOutMinWait` constant, but a SQL change requires a matching Dart
  change.
- Local DB holds student names and RFID UIDs unencrypted.
- A card assigned while the kiosk is offline shows "not recognized" until the next
  pull; the server still resolves it correctly on replay.
- Drift/Dart version compatibility with the pinned Flutter 3.24.5 must be
  verified before implementation.
- Estimated size: 600–900 lines including tests.
