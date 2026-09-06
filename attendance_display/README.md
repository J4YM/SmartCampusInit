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

#### If a second reader of the same model is also connected to this PC

If this entrance reader shares its vendor/product id with another device
that's also plugged into the same machine (e.g. the kiosk app's own
reader, if it's the same model), `READER_VENDOR_ID`/`READER_PRODUCT_ID`
alone can't tell them apart — set `READER_INSTANCE_HINT` too (see
`.env.example`'s comment for how to find the value).

**But test this before relying on it.** This hint only works when
Windows' Raw Input device list (`GetRawInputDeviceList`) actually
contains a *separate entry* for each device. Verified against two
genuinely identical reader units (same model, same firmware — so
identical HID report descriptors): Windows collapsed them to a single
Raw Input entry no matter which one was connected more recently or which
USB port either was in — the "missing" device wasn't filtered by our
code, it simply never appeared in the OS's own device list, and no
software-side filtering can retrieve an entry the OS isn't reporting.

If your two readers are that similar, `READER_INSTANCE_HINT` won't help.
Pick one instead:
- **Different reader models for the two roles** — sidesteps this
  entirely; the original vendor/product id filtering (without a hint)
  works as designed once the two devices are genuinely distinct.
- **Run this app on a separate PC** from the kiosk app — since only one
  of the two identical-model readers is ever connected to any given
  machine at a time, there's no ambiguity for Windows to collapse. This
  is a deployment change (not "second monitor on the kiosk PC" as
  originally designed), needs its own PC.
- **Drop Raw Input, rely on the focus-based fallback + `READER_PREFIX`**
  (previous/next section) — works with identical hardware on the same
  PC, but only if this specific reader model supports configuring a
  distinct prefix character per unit (check its documentation/config
  utility — many cheap generic keyboard-wedge modules do support this
  as their own answer to exactly this multi-reader scenario). Leave
  `READER_VENDOR_ID`/`READER_PRODUCT_ID` blank so the app doesn't try
  Raw Input at all, configure a different prefix on each physical unit,
  and set this app's `READER_PREFIX` to the entrance unit's prefix
  character. The tradeoff: this display then only captures taps while
  its own window has OS focus, same as before Task 7.

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
