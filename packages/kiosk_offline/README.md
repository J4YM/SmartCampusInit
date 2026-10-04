# kiosk_offline

Offline-first data layer for the Windows kiosk (`lib/main_kiosk.dart`). It keeps
a local Drift (SQLite) cache of students, staff and offenses; decides taps
locally when the server is unreachable (a Dart port of the `record_rfid_tap`
rules); queues taps and admission slips in an outbox; and replays them in order
when connectivity returns, preserving the original `tapped_at`. While online,
taps go to the server first and the local DB mirrors the result. The package has
no UI; the host (`lib/kiosk/capstone_kiosk_scan_host.dart`) calls it instead of
Supabase directly. On web it resolves to a no-op facade, so the Netlify web
build does not pull in SQLite.

## Architecture

| Unit | Responsibility | Depends on |
|---|---|---|
| `KioskDatabase` | Drift schema, DAOs | drift, sqlite3 |
| `ReferenceSync` | Pull students/staff/offenses into cache | Supabase client, `KioskDatabase` |
| `TapEngine` | Local in/out decision, writes `local_taps` + outbox | `KioskDatabase`, `TapRules` |
| `TapRules` | Pure Dart port of server rules | none |
| `Outbox` | Enqueue, ordered drain, backoff, rejection handling | `KioskDatabase`, Supabase client |
| `ConnectivityMonitor` | Probe + status stream | http |
| `SyncCoordinator` | Owns timers/triggers for pull and drain | the above |

## Keeping the rules in sync

`lib/src/tap_rules.dart` mirrors the SQL function `record_rfid_tap`. Any change
to that SQL (school-day rollover, debounce, tap-out wait, messages) needs a
matching change in `tap_rules.dart` **and** `test/tap_rules_test.dart`, or the
offline decisions will diverge from what the server accepts on replay.

## `KIOSK_TAP_OUT_MIN_WAIT_SECONDS`

Minimum seconds between tap-in and tap-out. Default `3600` (1 hour,
production). For development use a small value, e.g. `5`:

    flutter run -d windows -t lib/main_kiosk.dart --dart-define-from-file=supabase_dart_defines.json --dart-define=KIOSK_TAP_OUT_MIN_WAIT_SECONDS=5

It **must match the live SQL** (the repo contains two versions:
`add_rfid_tap_daily_limit.sql` enforces 5 s, `fix_rfid_school_day_timezone.sql`
enforces 1 h). See `supabase_dart_defines.json.example`.

## Tests and code generation

    cd packages/kiosk_offline
    flutter test
    flutter analyze

On Windows, `flutter test` loads `sqlite3.dll`; it was not needed on the
verification machine, but if the tests fail to open SQLite, put a `sqlite3.dll`
(e.g. the one from a built kiosk, `build/windows/x64/runner/Debug/`) on the PATH
or next to the test runner.

Regenerate Drift code after changing the schema:

    dart run build_runner build --delete-conflicting-outputs

## Netlify / Dart 3.5.4

Netlify pins Flutter 3.24.5 (Dart 3.5.4). Verified by querying
`pub.dev/api/packages/<pkg>/versions/<ver>`: drift 2.31.0 (sdk >=3.5.0),
sqlite3 2.9.4 (>=3.5.0), sqlite3_flutter_libs 0.5.42 (>=2.12.0), path_provider
2.1.5 (^3.4.0), all <= 3.5.4. This is only a metadata check; the Netlify deploy
preview is the real proof. If `flutter pub get` there reports an SDK mismatch
for a transitive package, add an exact pin in this package's `pubspec.yaml`
(not a root `dependency_overrides`).

## Manual offline checklist (not yet run)

Status: **not yet run** on a real Windows kiosk. Run:
`flutter run -d windows -t lib/main_kiosk.dart --dart-define-from-file=supabase_dart_defines.json --dart-define=KIOSK_TAP_OUT_MIN_WAIT_SECONDS=10`
and record pass/fail per line in the PR description.

1. Online: chip shows **Online**; tap a known card → welcome popup with in/out matching the server's `rfid_tap_events`.
2. Disconnect the network (disable the adapter). Within ~15 s the chip turns **Offline · 0 pending**.
3. Tap a known student card → welcome popup appears instantly, chip shows **Offline · 1 pending**.
4. Tap the same card again within 5 s → same direction, pending stays 1.
5. Wait 10 s, tap again → the opposite direction, pending 2. Tap a third time → "You have already tapped in and out for today."
6. Tap an unknown card → "not recognised" state, pending increments.
7. Tap a Security staff card → report screen opens; search a student number prefix; pick offenses; confirm → slip preview prints; chip pending increments.
8. Reconnect. Within ~15 s the chip shows **Syncing** then **Online**; in Supabase `rfid_tap_events` shows the offline taps with their **original `tapped_at`**, and `admission_slips`/`student_violations` contain the slip.
9. Force a rejection (deactivate `KIOSK-MAIN-001` in `rfid_readers`, tap offline, reconnect, then reactivate): chip shows **1 failed**, the dialog lists the "deactivated" message.
10. Restart the app while offline with a populated cache: identification still works.
