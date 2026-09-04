# attendance_display

A standalone Flutter Windows app for the second monitor at the kiosk PC's
entrance. Shows a student's photo/name/section when they tap a dedicated
entrance RFID reader — see `docs/superpowers/specs/2026-09-04-attendance-tap-monitor-design.md`
for the full design and `docs/superpowers/plans/2026-09-04-attendance-tap-monitor.md`
for how it was built.

This app has no operator console and receives no touch/mouse input — every
screen renders and updates itself. Setup below is entirely manual; there is
no installer or automated provisioning.

## Setup

### 1. Run the SQL migrations

In the Supabase SQL Editor, in order:

1. `supabase/add_rfid_tap_debounce.sql`
2. `supabase/add_attendance_display_setup.sql`

The second one registers the entrance reader's `rfid_readers` row and adds
`rfid_tap_events` to the `supabase_realtime` publication — without that
publication statement, the display's Realtime subscription (`lib/
tap_feed_controller.dart`) will never receive a tap, silently, with no
error anywhere.

### 2. Create the service-auth user

This app signs in as a dedicated, long-lived Auth user on startup (needed to
read the private `student-photos` storage bucket). It isn't SQL — create it
via Supabase Dashboard → Authentication → Users → "Add user":

- Email: something like `attendance-display@internal.local` (matches the
  comments in `add_attendance_display_setup.sql`).
- Password: a strong, generated one. Record it — you'll need it for step 3.

### 3. Configure `.env`

```
cp .env.example .env
```

Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SERVICE_EMAIL`,
`SERVICE_PASSWORD` (the user from step 2).

### 4. Match the reader's real USB serial

`add_attendance_display_setup.sql` registers the entrance reader with a
placeholder `usb_serial` of `ATTENDANCE-ENTRANCE-001`. Once the physical
reader is known:

- Update that row (re-run the insert with the real serial, or `update
  public.rfid_readers set usb_serial = '...' where usb_serial =
  'ATTENDANCE-ENTRANCE-001'` in the SQL Editor), and
- Set `READER_USB_SERIAL` in `.env` to the same value.

These two must match exactly, or `TapFeedController.start()` won't find a
reader row and will keep retrying the lookup with a backoff (visible in the
console log) instead of ever subscribing.

### 5. Read the reader's vendor/product ID

For the Windows Raw Input capture (`packages/rfid_raw_input_windows/`),
which captures this reader's keystrokes by device identity independent of
window focus:

1. Plug in the reader.
2. Open Windows Device Manager → find the reader (usually under
   "Keyboards") → Properties → Details tab → "Hardware Ids".
3. Read off the `VID_xxxx&PID_xxxx` value.
4. Set `READER_VENDOR_ID` and `READER_PRODUCT_ID` in `.env` to the hex
   values (with or without the `0x` prefix — both parse).

If left blank, the app falls back to the focus-based text-field capture
(`lib/reader_input_field.dart`) — the display still works, but only while
its window has OS focus.

### 6. `READER_PREFIX` (only if the reader model supports it)

Some RFID reader models can be configured to emit a distinct prefix
character before each scanned UID. If yours can (check its documentation
or config utility) and you've set one up, put that exact character in
`READER_PREFIX` — incoming input that doesn't start with it is treated as a
misdirected tap from a different reader and discarded. Leave blank
otherwise (most reader models don't support this) — every input then
passes through unchanged.

### 7. Hardware verification: confirm Raw Input actually works

This is the one check that can't be automated or verified outside real
hardware. With everything above configured:

1. `flutter run -d windows`
2. Click into an *unrelated* window (e.g. Notepad) so the attendance
   display does **not** have OS focus.
3. Tap the entrance reader.
4. Confirm the welcome card still appears.

This is the actual proof Raw Input is intercepting the reader's keystrokes
independent of focus. If the welcome card only appears while the display
window itself has focus, Raw Input isn't working — the text-field fallback
is what's actually firing, and the display's focus is what's making it
look like Raw Input is running.

## Known limitation: shared-focus kiosk PCs

The Raw Input mode this plugin uses (`RIDEV_INPUTSINK`) *observes* input
without *consuming* it. On a kiosk PC where this display shares a desktop
with other windows (e.g. the kiosk app's own reader input field), the
entrance reader's keystrokes still land in whatever window currently has
keyboard focus, in addition to being captured by Raw Input. `stripReaderPrefix`
(`lib/reader_input_field.dart`) defends this display against a misdirected
*kiosk* tap being misread as an entrance tap, but only in that one
direction — it does not, and cannot, stop an *entrance* tap from also being
typed into whatever else has focus on the same PC. Worth being aware of
during hardware setup; not something this app attempts to fully solve.

## Testing

```
flutter test
```

Covers the pure logic: `AttendanceEnv` resolution/`configured` (`test/
env_test.dart`), tap-data formatting (`test/tap_feed_controller_test.dart`),
the idle/welcome UI (`test/tap_display_screen_test.dart`), reader-prefix
stripping (`test/reader_prefix_test.dart`), and the Raw Input watchdog
decision (`test/reader_watchdog_test.dart`). Supabase/timer-driven
orchestration code (`TapFeedController`, `ReaderInputCapture`'s widget
wiring) isn't unit-tested, matching this repo's established convention of
testing pure logic and leaving Supabase-touching glue code to manual/
hardware verification.
