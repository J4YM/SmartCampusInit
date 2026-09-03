# Attendance Tap Monitor — Design

## Context

A second physical monitor, connected to the same PC as the Virtual
Admission Kiosk, sits at the school entrance and shows a live "who just
tapped" feed — photo, name, section/program — as students tap a dedicated
RFID reader. It needs no touch interaction. A second USB keyboard-wedge
RFID reader (distinct from the kiosk's own reader) feeds it, physically
connected to the same PC.

`rfid_tap_events`/`rfid_readers`/`record_rfid_tap` already exist in the
schema (`supabase/add_rfid_reader_network_schema.sql`) and already do
almost everything needed — per-reader identity, in/out toggling, student
resolution — but nothing calls `record_rfid_tap` from the kiosk's own tap
flow today; it's only called by an admin dev simulator and a separate,
unrelated `tools/rfid_reader_service` Python tool built for a
multi-floor-reader deployment this school isn't using.

## Architecture

**A new, standalone Flutter Windows app**, not a second window inside the
kiosk app or a `desktop_multi_window` integration. This repo has zero
existing multi-window precedent (confirmed by full-repo search), and the
one existing "alternate entry point," `lib/main_slip.dart`, is a **web**
build target (`flutter build web --target lib/main_slip.dart`, per
`scripts/netlify_build.sh:87`) — not evidence that this project can
produce two independent Windows `.exe`s from one `pubspec.yaml`/`windows/`
runner without extra build-output-naming work. A separate top-level
Flutter project (its own `pubspec.yaml`, its own `windows/` runner) is the
straightforward way to get a genuinely independent, independently
launchable second program.

```
attendance_display/              (new standalone Flutter app)
  lib/
    main.dart                    entry point: Supabase init, service sign-in, runs the idle/tap UI
    tap_feed_controller.dart     Realtime subscription -> resolves student -> emits display state
    tap_display_screen.dart      idle screen + "Welcome" card UI
  pubspec.yaml
  windows/                       Flutter's generated Windows runner

packages/
  rfid_raw_input_windows/        (new local plugin package)
    lib/
      rfid_raw_input_windows.dart   Dart API: RfidRawInputReader.taps (Stream<String>), given a target device's vendor/product id
    windows/
      rfid_raw_input_windows_plugin.cpp   RegisterRawInputDevices(RIDEV_INPUTSINK), WM_INPUT handling, HID keyboard usage-code decode, per-device filtering, forwards completed UID strings (buffered until Enter) to Dart via EventChannel
```

`rfid_raw_input_windows` is its own local package (not folded into
`attendance_display`) so the same device-filtered capture is available to
the kiosk app later too, without the kiosk depending on the attendance
app or vice versa.

## Components

### 1. `record_rfid_tap` debounce

Add a guard at the top of the existing RPC: if this student's most recent
`rfid_tap_events` row is within 5 seconds, return that existing row
unchanged instead of inserting/toggling again. Pure SQL addition to the
existing function — no schema change.

### 2. New reader registration

One new `rfid_readers` row for the entrance reader (distinct `usb_serial`
from the kiosk's own — the actual serial comes from the physical device
once it's in hand; a placeholder is used until then and updated by the
person doing hardware setup).

### 3. Service auth identity (photo access)

`student-photos` is a private bucket, `authenticated`-only. A long-running
unattended display can't use the app's existing anonymous-sign-in-then-
immediately-sign-out pattern (`StudentsRepository.create()`) — it needs a
persistent session. A dedicated Supabase Auth user
(`attendance-display@internal.local`, or similar, password supplied via
`--dart-define` matching how `AppEnv` already sources the Supabase URL/anon
key) that the app signs into once at startup and stays signed in for the
life of the process.

### 4. Raw Input plugin

Registers for the entrance reader's specific HID device (matched by
vendor/product ID, read off the physical device once available) with
`RIDEV_INPUTSINK`, so it receives that device's keystrokes regardless of
window focus. Buffers characters until Enter, exposes completed UID
strings to Dart as a stream. **This is the piece with real, unavoidable
hardware-in-the-loop risk** — HID usage-code-to-character decoding and
device matching can only be fully verified against the actual reader on
actual Windows hardware, which isn't available in this environment. The
plan below implements it as completely as static analysis allows and
flags the verification step explicitly rather than claiming untested
native code works.

### 5. Defense-in-depth: reader prefix

If the physical reader supports a configurable prefix/suffix (check the
specific model's documentation/config utility — not verifiable from here),
configure a distinct prefix for the entrance reader and have the app
discard any input not carrying it. Independent of whether Raw Input is
working correctly; cheap extra safety net.

### 6. Tap feed / UI

`attendance_display` subscribes to Realtime `INSERT` on `rfid_tap_events`
filtered to the entrance reader's `reader_id`. On a new row: resolve the
student (name, section, `photo_path` -> signed URL), show a "Welcome,
{name}" card with photo for ~5 seconds, then return to an idle screen.

## Out of scope

- Kiosk-side Raw Input adoption (the kiosk's own reader keeps working as
  it does today — unlogged lookups). Worth doing later with the same
  plugin package, not required for this feature to work.
- Any admin UI to manage the entrance reader's config — a straight SQL
  insert is enough for one reader.
