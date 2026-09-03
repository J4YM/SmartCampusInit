# Attendance Tap Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone Windows desktop app, running on a second monitor connected to the kiosk PC, that shows a student's photo/name/section as they tap a dedicated entrance RFID reader.

**Architecture:** A new top-level Flutter Windows app (`attendance_display/`) subscribes to Supabase Realtime on `rfid_tap_events` and renders an idle/"Welcome" UI. It captures its reader's raw keyboard-wedge input the same way the kiosk already does (a focused hidden text field) for the first working version, then upgrades to a new local plugin package (`packages/rfid_raw_input_windows/`) that uses the Windows Raw Input API to capture that reader's keystrokes by device identity, independent of window focus. Two small SQL changes (a debounce guard on the existing `record_rfid_tap` RPC, and a new reader + service-auth row) round it out.

**Tech Stack:** Flutter (Windows desktop target), `supabase_flutter` (Realtime, Auth, Storage), Win32 Raw Input API via a native platform-channel plugin.

**Spec:** `docs/superpowers/specs/2026-09-04-attendance-tap-monitor-design.md`

## Global Constraints

- No existing table/column is altered — `record_rfid_tap`'s change is additive logic inside the existing function body.
- The debounce window is 5 seconds, applied per-student regardless of which reader the prior tap came from.
- `attendance_display` never receives touch/mouse interaction — every screen must render and update itself with zero user input.
- The service-auth credentials are supplied via `--dart-define`/`.env`, matching this repo's existing `AppEnv` pattern (`lib/env.dart`) — never hardcoded in source.
- The Raw Input native plugin (Task 6) cannot be compiled or hardware-tested in this environment — implement it completely, but its correctness can only be confirmed by the user running it against the real reader on real Windows hardware.

---

### Task 1: Debounce guard on `record_rfid_tap`

**Files:**
- Create: `supabase/add_rfid_tap_debounce.sql`

**Interfaces:**
- Produces: `record_rfid_tap(p_reader_usb_serial text, p_rfid_uid text, p_tapped_at timestamptz default now())` — same signature and return shape as today (`table(tap_id uuid, reader_id uuid, student_id uuid, tap_direction rfid_tap_direction, tapped_at timestamptz)`); behavior changes only for a same-student tap within 5 seconds of their last one.

- [ ] **Step 1: Write the migration**

```sql
-- Adds a 5-second debounce to record_rfid_tap so an accidental double-tap
-- of the same card doesn't toggle in/out twice. Minimal change to the
-- existing function (supabase/add_rfid_reader_network_schema.sql) — same
-- signature, same return shape, one added early-return branch.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create or replace function public.record_rfid_tap(
  p_reader_usb_serial text,
  p_rfid_uid text,
  p_tapped_at timestamptz default now()
)
returns table (
  tap_id uuid,
  reader_id uuid,
  student_id uuid,
  tap_direction public.rfid_tap_direction,
  tapped_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reader_id uuid;
  v_student_id uuid;
  v_last_tap_id uuid;
  v_last_direction public.rfid_tap_direction;
  v_last_tapped_at timestamptz;
  v_next_direction public.rfid_tap_direction;
  v_tap_id uuid;
begin
  select id into v_reader_id
    from public.rfid_readers
    where usb_serial = p_reader_usb_serial;

  if v_reader_id is null then
    raise exception 'Unknown reader serial: %', p_reader_usb_serial;
  end if;

  update public.rfid_readers
    set last_seen_at = p_tapped_at
    where id = v_reader_id;

  select id into v_student_id
    from public.students
    where rfid_uid = p_rfid_uid;

  if v_student_id is not null then
    select id, tap_direction, tapped_at
      into v_last_tap_id, v_last_direction, v_last_tapped_at
      from public.rfid_tap_events
      where student_id = v_student_id
        and tapped_at::date = p_tapped_at::date
      order by tapped_at desc
      limit 1;

    -- Debounce: an accidental double-tap within 5 seconds just echoes back
    -- the tap that already got recorded, instead of toggling again.
    if v_last_tap_id is not null
       and p_tapped_at - v_last_tapped_at < interval '5 seconds' then
      return query
        select v_last_tap_id, v_reader_id, v_student_id, v_last_direction, v_last_tapped_at;
      return;
    end if;
  end if;

  v_next_direction := case
    when v_last_direction = 'in' then 'out'::public.rfid_tap_direction
    else 'in'::public.rfid_tap_direction
  end;

  insert into public.rfid_tap_events (
    reader_id, rfid_uid, student_id, tap_direction, tapped_at
  )
  values (
    v_reader_id, p_rfid_uid, v_student_id, v_next_direction, p_tapped_at
  )
  returning id into v_tap_id;

  return query
    select v_tap_id, v_reader_id, v_student_id, v_next_direction, p_tapped_at;
end;
$$;
```

- [ ] **Step 2: Get user approval, then have them run it in Supabase SQL Editor**

Show the exact SQL above and wait for confirmation it ran successfully before continuing (this repo's established convention — see `MEMORY.md`'s "Confirm SQL before DB writes").

- [ ] **Step 3: Verify manually**

Ask the user to run this in the SQL Editor and confirm it returns a single row (not two) for a student tapped twice within 5 seconds:

```sql
select public.record_rfid_tap('KIOSK-MAIN-001', '<a real rfid_uid from students>', now());
select public.record_rfid_tap('KIOSK-MAIN-001', '<same rfid_uid>', now() + interval '2 seconds');
select count(*) from public.rfid_tap_events where rfid_uid = '<same rfid_uid>' and tapped_at > now() - interval '1 minute';
-- expect: count = 1, not 2
```

- [ ] **Step 4: Commit**

```bash
git add supabase/add_rfid_tap_debounce.sql
git commit -m "feat: debounce accidental double-taps in record_rfid_tap"
```

---

### Task 2: Entrance reader + service-auth account

**Files:**
- Create: `supabase/add_attendance_display_setup.sql`

**Interfaces:**
- Produces: an `rfid_readers` row the app's `.env` will reference by `usb_serial`; a Supabase Auth user the app signs in as.

- [ ] **Step 1: Write the migration**

```sql
-- Registers the Attendance Tap Monitor's dedicated entrance reader.
-- usb_serial is a placeholder — update it once the physical reader's real
-- serial is known (whoever does hardware setup edits this row, or reruns
-- this insert with the correct value before the app goes live).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

insert into public.rfid_readers (label, usb_serial, location, is_kiosk_reader)
values ('Attendance Entrance Reader', 'ATTENDANCE-ENTRANCE-001', 'Main Entrance', false)
on conflict (usb_serial) do nothing;
```

- [ ] **Step 2: Get user approval, then have them run it**

- [ ] **Step 3: Create the service-auth user**

This part isn't SQL — ask the user to create it via Supabase Dashboard → Authentication → Users → "Add user", with a strong generated password, email like `attendance-display@internal.local`. Confirm the exact email/password they used (needed for Task 4's `.env`).

- [ ] **Step 4: Commit**

```bash
git add supabase/add_attendance_display_setup.sql
git commit -m "feat: register the attendance entrance RFID reader"
```

---

### Task 3: `attendance_display` app scaffold

**Files:**
- Create: `attendance_display/pubspec.yaml`
- Create: `attendance_display/lib/env.dart`
- Create: `attendance_display/lib/main.dart`
- Create: `attendance_display/.env.example`
- Create: `attendance_display/test/env_test.dart`

**Interfaces:**
- Produces: `AttendanceEnv.resolve()`, `AttendanceEnv.supabaseUrl`/`supabaseAnonKey`/`serviceEmail`/`servicePassword`/`readerUsbSerial` (all `String`), `AttendanceEnv.configured` (`bool`) — consumed by Task 4/5.

- [ ] **Step 1: Write the failing test for env resolution**

```dart
// attendance_display/test/env_test.dart
import 'package:attendance_display/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configured is false until every required value is set', () {
    AttendanceEnv.supabaseUrl = '';
    AttendanceEnv.supabaseAnonKey = '';
    AttendanceEnv.serviceEmail = '';
    AttendanceEnv.servicePassword = '';
    AttendanceEnv.readerUsbSerial = '';
    expect(AttendanceEnv.configured, isFalse);

    AttendanceEnv.supabaseUrl = 'https://example.supabase.co';
    AttendanceEnv.supabaseAnonKey = 'anon-key';
    AttendanceEnv.serviceEmail = 'attendance-display@internal.local';
    AttendanceEnv.servicePassword = 'secret';
    AttendanceEnv.readerUsbSerial = 'ATTENDANCE-ENTRANCE-001';
    expect(AttendanceEnv.configured, isTrue);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd attendance_display && flutter test test/env_test.dart` — expect failure (package doesn't exist yet).

- [ ] **Step 3: Scaffold the project**

```bash
cd /path/to/repo
flutter create --platforms windows --org com.stibaliuag attendance_display
```

Then replace the generated `attendance_display/pubspec.yaml` dependencies section with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_dotenv: ^5.2.1
  supabase_flutter: ^2.6.0
  google_fonts: ^6.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

- [ ] **Step 4: Write `lib/env.dart`**

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Populated by [AttendanceEnv.resolve] after `.env` loads in `main`.
/// Mirrors the parent app's `lib/env.dart` pattern.
class AttendanceEnv {
  AttendanceEnv._();

  static String supabaseUrl = '';
  static String supabaseAnonKey = '';

  /// Credentials for the dedicated, long-lived Auth user this display
  /// signs in as on startup (needed to read the private `student-photos`
  /// bucket — see supabase/add_student_photos_storage.sql).
  static String serviceEmail = '';
  static String servicePassword = '';

  /// Must match the `usb_serial` of the `rfid_readers` row this monitor's
  /// reader is registered under (see supabase/add_attendance_display_setup.sql).
  static String readerUsbSerial = '';

  static void resolve() {
    supabaseUrl = _pick('SUPABASE_URL');
    supabaseAnonKey = _pick('SUPABASE_ANON_KEY');
    serviceEmail = _pick('SERVICE_EMAIL');
    servicePassword = _pick('SERVICE_PASSWORD');
    readerUsbSerial = _pick('READER_USB_SERIAL');
  }

  static String _pick(String key) {
    final raw = dotenv.env[key];
    return raw?.trim() ?? '';
  }

  static bool get configured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      serviceEmail.isNotEmpty &&
      servicePassword.isNotEmpty &&
      readerUsbSerial.isNotEmpty;
}
```

- [ ] **Step 5: Run the test, confirm it passes**

Run: `cd attendance_display && flutter test test/env_test.dart` — expect PASS.

- [ ] **Step 6: Write `.env.example` and `main.dart`**

```
# attendance_display/.env.example
SUPABASE_URL=
SUPABASE_ANON_KEY=
SERVICE_EMAIL=attendance-display@internal.local
SERVICE_PASSWORD=
READER_USB_SERIAL=ATTENDANCE-ENTRANCE-001
```

```dart
// attendance_display/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  AttendanceEnv.resolve();

  if (AttendanceEnv.configured) {
    await Supabase.initialize(
      url: AttendanceEnv.supabaseUrl,
      anonKey: AttendanceEnv.supabaseAnonKey,
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: AttendanceEnv.serviceEmail,
      password: AttendanceEnv.servicePassword,
    );
  }

  runApp(const AttendanceDisplayApp());
}

class AttendanceDisplayApp extends StatelessWidget {
  const AttendanceDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            AttendanceEnv.configured
                ? 'Attendance Display — waiting for taps'
                : 'Not configured — check .env',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Verify it builds and runs**

Run: `cd attendance_display && flutter run -d windows` — confirm a window opens showing "Attendance Display — waiting for taps" (or the not-configured message if `.env` isn't filled in yet — that's expected before hardware setup).

- [ ] **Step 8: Commit**

```bash
git add attendance_display/
git commit -m "feat: scaffold the attendance_display standalone app"
```

---

### Task 4: Tap feed controller — resolve a tap into display data

**Files:**
- Create: `attendance_display/lib/tap_feed_controller.dart`
- Create: `attendance_display/lib/tap_display_data.dart`
- Test: `attendance_display/test/tap_feed_controller_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks except `AttendanceEnv` (Task 3).
- Produces: `TapDisplayData` (`{String name, String section, String? photoSignedUrl, String direction}`); `formatTapDisplayData({required String firstName, required String lastName, required String sectionName, required String? photoSignedUrl, required String direction}) -> TapDisplayData` — a pure function, the actual Supabase-calling orchestration around it is wired in Task 5 (not itself unit-tested, matching this repo's established pattern of testing pure logic and leaving Supabase-touching glue code untested — see `lib/documents/good_moral_certificate_text.dart` for the same split).

- [ ] **Step 1: Write the failing test**

```dart
// attendance_display/test/tap_feed_controller_test.dart
import 'package:attendance_display/tap_display_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a resolved tap into display data', () {
    final data = formatTapDisplayData(
      firstName: 'Juan',
      lastName: 'Dela Cruz',
      sectionName: 'BSIT - 3B',
      photoSignedUrl: 'https://example.com/signed/photo.jpg',
      direction: 'in',
    );

    expect(data.name, 'Juan Dela Cruz');
    expect(data.section, 'BSIT - 3B');
    expect(data.photoSignedUrl, 'https://example.com/signed/photo.jpg');
    expect(data.direction, 'in');
  });

  test('falls back to a generic label when the card is unregistered', () {
    final data = formatTapDisplayData(
      firstName: '',
      lastName: '',
      sectionName: '',
      photoSignedUrl: null,
      direction: 'in',
    );

    expect(data.name, 'Unregistered card');
    expect(data.photoSignedUrl, isNull);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd attendance_display && flutter test test/tap_feed_controller_test.dart` — expect failure (`tap_display_data.dart` doesn't exist).

- [ ] **Step 3: Write `tap_display_data.dart`**

```dart
class TapDisplayData {
  const TapDisplayData({
    required this.name,
    required this.section,
    required this.photoSignedUrl,
    required this.direction,
  });

  final String name;
  final String section;
  final String? photoSignedUrl;

  /// 'in' or 'out' — mirrors `rfid_tap_events.tap_direction`.
  final String direction;
}

TapDisplayData formatTapDisplayData({
  required String firstName,
  required String lastName,
  required String sectionName,
  required String? photoSignedUrl,
  required String direction,
}) {
  final name = '${firstName.trim()} ${lastName.trim()}'.trim();
  return TapDisplayData(
    name: name.isEmpty ? 'Unregistered card' : name,
    section: sectionName.trim(),
    photoSignedUrl: photoSignedUrl,
    direction: direction,
  );
}
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `cd attendance_display && flutter test test/tap_feed_controller_test.dart` — expect PASS.

- [ ] **Step 5: Write `tap_feed_controller.dart`** (the Realtime-subscribing orchestration; not unit-tested, per this repo's convention for Supabase-touching glue)

```dart
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'tap_display_data.dart';

/// Subscribes to Realtime inserts on `rfid_tap_events` for this monitor's
/// own reader, resolves each into [TapDisplayData], and emits it — the UI
/// (Task 5) just listens to [stream].
class TapFeedController {
  TapFeedController(this._client);

  final SupabaseClient _client;
  final _controller = StreamController<TapDisplayData>.broadcast();
  RealtimeChannel? _channel;
  String? _readerId;

  Stream<TapDisplayData> get stream => _controller.stream;

  Future<void> start() async {
    final reader = await _client
        .from('rfid_readers')
        .select('id')
        .eq('usb_serial', AttendanceEnv.readerUsbSerial)
        .maybeSingle();
    _readerId = reader?['id'] as String?;
    if (_readerId == null) return;

    _channel = _client
        .channel('public:rfid_tap_events:attendance_display')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rfid_tap_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reader_id',
            value: _readerId,
          ),
          callback: (payload) => _handleTap(payload.newRecord),
        )
        .subscribe();
  }

  Future<void> _handleTap(Map<String, dynamic> row) async {
    final studentId = row['student_id'] as String?;
    final direction = row['tap_direction'] as String? ?? 'in';

    if (studentId == null) {
      _controller.add(formatTapDisplayData(
        firstName: '',
        lastName: '',
        sectionName: '',
        photoSignedUrl: null,
        direction: direction,
      ));
      return;
    }

    final student = await _client
        .from('students')
        .select(
          'photo_path, profiles(first_name, last_name), sections(name)',
        )
        .eq('id', studentId)
        .maybeSingle();
    if (student == null) return;

    final profile = student['profiles'] as Map<String, dynamic>?;
    final section = student['sections'] as Map<String, dynamic>?;
    final photoPath = student['photo_path'] as String?;

    String? signedUrl;
    if (photoPath != null && photoPath.isNotEmpty) {
      signedUrl = await _client.storage
          .from('student-photos')
          .createSignedUrl(photoPath, 300);
    }

    _controller.add(formatTapDisplayData(
      firstName: profile?['first_name'] as String? ?? '',
      lastName: profile?['last_name'] as String? ?? '',
      sectionName: section?['name'] as String? ?? '',
      photoSignedUrl: signedUrl,
      direction: direction,
    ));
  }

  Future<void> dispose() async {
    final channel = _channel;
    if (channel != null) await _client.removeChannel(channel);
    await _controller.close();
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add attendance_display/lib/tap_display_data.dart attendance_display/lib/tap_feed_controller.dart attendance_display/test/tap_feed_controller_test.dart
git commit -m "feat: resolve rfid_tap_events inserts into display data"
```

---

### Task 5: Idle + "Welcome" UI

**Files:**
- Create: `attendance_display/lib/tap_display_screen.dart`
- Modify: `attendance_display/lib/main.dart`
- Test: `attendance_display/test/tap_display_screen_test.dart`

**Interfaces:**
- Consumes: `TapFeedController.stream` (Task 4), `TapDisplayData` (Task 4).
- Produces: `TapDisplayScreen` widget (`{required Stream<TapDisplayData> tapStream}`).

- [ ] **Step 1: Write the failing test**

```dart
// attendance_display/test/tap_display_screen_test.dart
import 'dart:async';

import 'package:attendance_display/tap_display_data.dart';
import 'package:attendance_display/tap_display_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows idle state, then a welcome card on a tap, then reverts',
      (tester) async {
    final controller = StreamController<TapDisplayData>();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: TapDisplayScreen(tapStream: controller.stream),
    ));

    expect(find.text('Tap your ID to check in'), findsOneWidget);

    controller.add(const TapDisplayData(
      name: 'Juan Dela Cruz',
      section: 'BSIT - 3B',
      photoSignedUrl: null,
      direction: 'in',
    ));
    await tester.pump();

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('BSIT - 3B'), findsOneWidget);
    expect(find.textContaining('Welcome'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Tap your ID to check in'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd attendance_display && flutter test test/tap_display_screen_test.dart` — expect failure (`tap_display_screen.dart` doesn't exist).

- [ ] **Step 3: Write `tap_display_screen.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'tap_display_data.dart';

class TapDisplayScreen extends StatefulWidget {
  const TapDisplayScreen({super.key, required this.tapStream});

  final Stream<TapDisplayData> tapStream;

  @override
  State<TapDisplayScreen> createState() => _TapDisplayScreenState();
}

class _TapDisplayScreenState extends State<TapDisplayScreen> {
  static const _showDuration = Duration(seconds: 5);

  StreamSubscription<TapDisplayData>? _subscription;
  TapDisplayData? _current;
  Timer? _revertTimer;

  @override
  void initState() {
    super.initState();
    _subscription = widget.tapStream.listen(_handleTap);
  }

  void _handleTap(TapDisplayData data) {
    _revertTimer?.cancel();
    setState(() => _current = data);
    _revertTimer = Timer(_showDuration, () {
      if (mounted) setState(() => _current = null);
    });
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: data == null ? _buildIdle() : _buildWelcome(data),
      ),
    );
  }

  Widget _buildIdle() {
    return const Text(
      'Tap your ID to check in',
      style: TextStyle(color: Colors.white70, fontSize: 28),
    );
  }

  Widget _buildWelcome(TapDisplayData data) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 90,
          backgroundColor: Colors.white24,
          backgroundImage: data.photoSignedUrl == null
              ? null
              : NetworkImage(data.photoSignedUrl!),
          child: data.photoSignedUrl == null
              ? const Icon(Icons.person, size: 90, color: Colors.white70)
              : null,
        ),
        const SizedBox(height: 24),
        Text(
          data.direction == 'in' ? 'Welcome!' : 'See you later!',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          data.name,
          style: const TextStyle(color: Colors.white, fontSize: 26),
        ),
        const SizedBox(height: 6),
        Text(
          data.section,
          style: const TextStyle(color: Colors.white60, fontSize: 18),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `cd attendance_display && flutter test test/tap_display_screen_test.dart` — expect PASS.

- [ ] **Step 5: Wire it into `main.dart`**, replacing the placeholder `Scaffold` from Task 3 Step 6:

```dart
      home: AttendanceEnv.configured
          ? Builder(builder: (context) {
              final controller = TapFeedController(Supabase.instance.client);
              controller.start();
              return TapDisplayScreen(tapStream: controller.stream);
            })
          : const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Text(
                  'Not configured — check .env',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
```

(add the two new imports: `tap_feed_controller.dart`, `tap_display_screen.dart`)

- [ ] **Step 6: Commit**

```bash
git add attendance_display/lib/tap_display_screen.dart attendance_display/lib/main.dart attendance_display/test/tap_display_screen_test.dart
git commit -m "feat: idle/welcome UI for the attendance display"
```

---

### Task 6: Temporary reader input (works today, no native plugin yet)

**Files:**
- Create: `attendance_display/lib/reader_input_field.dart`
- Modify: `attendance_display/lib/main.dart`

**Interfaces:**
- Produces: `ReaderInputCapture` widget — an invisible, always-focused text field that calls `onUid(String uid)` when Enter is pressed, then clears and refocuses. Same technique `VirtualAdmissionKioskScreen` already uses for the kiosk's own reader.

This makes the app fully functional end-to-end (tap the reader while this window has focus → `record_rfid_tap` gets called → the Realtime feed picks it up → UI updates) before tackling the harder, hardware-dependent Raw Input plugin in Task 7. This is the "keep the display window always focused" mitigation discussed in the design — real, but not the full fix; Task 7 replaces it.

- [ ] **Step 1: Write `reader_input_field.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Invisible, permanently-focused capture field for a USB keyboard-wedge
/// RFID reader — the reader "types" the UID followed by Enter. Calls
/// `record_rfid_tap` directly. Temporary: Task 7 replaces this with a
/// device-filtered Raw Input capture that doesn't depend on window focus.
class ReaderInputCapture extends StatefulWidget {
  const ReaderInputCapture({super.key, required this.child});

  final Widget child;

  @override
  State<ReaderInputCapture> createState() => _ReaderInputCaptureState();
}

class _ReaderInputCaptureState extends State<ReaderInputCapture> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();

  Future<void> _handleSubmit(String value) async {
    final uid = value.trim();
    _controller.clear();
    _focusNode.requestFocus();
    if (uid.isEmpty) return;
    try {
      await Supabase.instance.client.rpc('record_rfid_tap', params: {
        'p_reader_usb_serial': AttendanceEnv.readerUsbSerial,
        'p_rfid_uid': uid,
      });
    } catch (_) {
      // A misread/unknown card is a data-quality signal server-side
      // (record_rfid_tap logs it with student_id null), not something
      // this unattended display can act on — nothing to surface here.
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          width: 0,
          height: 0,
          child: Offstage(
            child: TextField(
              focusNode: _focusNode,
              controller: _controller,
              autofocus: true,
              onSubmitted: _handleSubmit,
              onTapOutside: (_) => _focusNode.requestFocus(),
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Wrap the home screen with it in `main.dart`**

Wrap whichever branch renders `TapDisplayScreen` (from Task 5 Step 5) in `ReaderInputCapture(child: ...)`, and add the `reader_input_field.dart` import.

- [ ] **Step 3: Verify manually**

Run: `cd attendance_display && flutter run -d windows`. With `.env` filled in and a real reader plugged in (or by typing a known `rfid_uid` value followed by Enter directly, simulating the reader), confirm the welcome card appears and reverts to idle after 5 seconds.

- [ ] **Step 4: Commit**

```bash
git add attendance_display/lib/reader_input_field.dart attendance_display/lib/main.dart
git commit -m "feat: capture entrance reader taps via a focused input field"
```

---

### Task 7: `rfid_raw_input_windows` plugin — device-filtered capture

**Files:**
- Create: `packages/rfid_raw_input_windows/pubspec.yaml`
- Create: `packages/rfid_raw_input_windows/lib/rfid_raw_input_windows.dart`
- Create: `packages/rfid_raw_input_windows/windows/rfid_raw_input_windows_plugin.cpp`
- Create: `packages/rfid_raw_input_windows/windows/rfid_raw_input_windows_plugin.h`
- Create: `packages/rfid_raw_input_windows/windows/CMakeLists.txt`
- Modify: `attendance_display/pubspec.yaml`
- Modify: `attendance_display/lib/main.dart`

**Interfaces:**
- Produces: `RfidRawInputReader.taps(int vendorId, int productId) -> Stream<String>` — a Dart API the app listens to instead of `ReaderInputCapture` (Task 6, which stays in the codebase as a documented fallback rather than being deleted, in case Raw Input proves unreliable on-site).

**This task carries real, unavoidable risk this plan cannot eliminate**: HID usage-code decoding and per-device matching can only be verified against the actual reader on actual Windows hardware, which isn't available in this environment. The steps below implement it completely and correctly per the Win32 Raw Input API's documented behavior, but the verification step is a manual hardware check the user has to run, not an automated test.

- [ ] **Step 1: Scaffold the plugin package**

```bash
flutter create --template=plugin --platforms=windows --org com.stibaliuag rfid_raw_input_windows
mv rfid_raw_input_windows packages/
```

- [ ] **Step 2: Write the Dart API** (`packages/rfid_raw_input_windows/lib/rfid_raw_input_windows.dart`)

```dart
import 'dart:async';
import 'package:flutter/services.dart';

/// Captures keystrokes from one specific USB HID keyboard-wedge device
/// (identified by vendor/product id) via the Windows Raw Input API,
/// regardless of which window currently has focus. Buffers characters
/// until Enter, then emits the completed string.
class RfidRawInputReader {
  RfidRawInputReader._();

  static const _methodChannel = MethodChannel('rfid_raw_input_windows/methods');
  static const _eventChannel = EventChannel('rfid_raw_input_windows/events');

  /// [vendorId]/[productId] identify the target reader (read these off the
  /// physical device — e.g. via Windows Device Manager's Hardware IDs tab,
  /// format `VID_xxxx&PID_xxxx`).
  static Stream<String> taps(int vendorId, int productId) {
    return _eventChannel
        .receiveBroadcastStream({
          'vendorId': vendorId,
          'productId': productId,
        })
        .map((event) => event as String);
  }

  /// True if the native side found and registered a matching device.
  static Future<bool> deviceFound(int vendorId, int productId) async {
    final result = await _methodChannel.invokeMethod<bool>('deviceFound', {
      'vendorId': vendorId,
      'productId': productId,
    });
    return result ?? false;
  }
}
```

- [ ] **Step 3: Write the native plugin header** (`packages/rfid_raw_input_windows/windows/rfid_raw_input_windows_plugin.h`)

```cpp
#ifndef FLUTTER_PLUGIN_RFID_RAW_INPUT_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_RFID_RAW_INPUT_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>
#include <string>

namespace rfid_raw_input_windows {

class RfidRawInputWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  RfidRawInputWindowsPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~RfidRawInputWindowsPlugin();

 private:
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void RegisterDevice(unsigned short vendor_id, unsigned short product_id);
  void OnRawInput(LPARAM lparam);

  flutter::PluginRegistrarWindows *registrar_;
  int window_proc_id_ = -1;
  unsigned short target_vendor_id_ = 0;
  unsigned short target_product_id_ = 0;
  HANDLE target_device_handle_ = nullptr;
  std::wstring buffer_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace rfid_raw_input_windows

#endif
```

- [ ] **Step 4: Write the native plugin implementation** (`packages/rfid_raw_input_windows/windows/rfid_raw_input_windows_plugin.cpp`)

```cpp
#include "rfid_raw_input_windows_plugin.h"

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

namespace rfid_raw_input_windows {

using flutter::EncodableMap;
using flutter::EncodableValue;

// static
void RfidRawInputWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<RfidRawInputWindowsPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

RfidRawInputWindowsPlugin::RfidRawInputWindowsPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  auto method_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "rfid_raw_input_windows/methods",
      &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [this](const auto &call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  auto event_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "rfid_raw_input_windows/events",
      &flutter::StandardMethodCodec::GetInstance());
  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<EncodableValue>>(
      [this](const EncodableValue *arguments,
             std::unique_ptr<flutter::EventSink<EncodableValue>> &&events)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        event_sink_ = std::move(events);
        if (auto *map = std::get_if<EncodableMap>(arguments)) {
          auto vid = map->find(EncodableValue("vendorId"));
          auto pid = map->find(EncodableValue("productId"));
          if (vid != map->end() && pid != map->end()) {
            RegisterDevice(
                static_cast<unsigned short>(std::get<int>(vid->second)),
                static_cast<unsigned short>(std::get<int>(pid->second)));
          }
        }
        return nullptr;
      },
      [this](const EncodableValue *arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        event_sink_ = nullptr;
        return nullptr;
      });
  event_channel->SetStreamHandler(std::move(handler));

  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

RfidRawInputWindowsPlugin::~RfidRawInputWindowsPlugin() {
  if (window_proc_id_ != -1) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

void RfidRawInputWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() == "deviceFound") {
    const auto *map = std::get_if<EncodableMap>(call.arguments());
    if (!map) {
      result->Error("bad_args", "Expected a map with vendorId/productId");
      return;
    }
    auto vid = map->find(EncodableValue("vendorId"));
    auto pid = map->find(EncodableValue("productId"));
    if (vid == map->end() || pid == map->end()) {
      result->Error("bad_args", "Missing vendorId/productId");
      return;
    }
    RegisterDevice(
        static_cast<unsigned short>(std::get<int>(vid->second)),
        static_cast<unsigned short>(std::get<int>(pid->second)));
    result->Success(EncodableValue(target_device_handle_ != nullptr));
    return;
  }
  result->NotImplemented();
}

void RfidRawInputWindowsPlugin::RegisterDevice(unsigned short vendor_id,
                                                unsigned short product_id) {
  target_vendor_id_ = vendor_id;
  target_product_id_ = product_id;
  target_device_handle_ = nullptr;

  // Enumerate connected raw input devices and find the one whose HID
  // vendor/product id matches. RIDI_DEVICEINFO gives us that without
  // needing a separate SetupAPI pass.
  UINT device_count = 0;
  GetRawInputDeviceList(nullptr, &device_count, sizeof(RAWINPUTDEVICELIST));
  if (device_count == 0) return;

  std::vector<RAWINPUTDEVICELIST> devices(device_count);
  GetRawInputDeviceList(devices.data(), &device_count, sizeof(RAWINPUTDEVICELIST));

  for (const auto &device : devices) {
    if (device.dwType != RIM_TYPEHID) continue;

    RID_DEVICE_INFO info;
    info.cbSize = sizeof(RID_DEVICE_INFO);
    UINT size = sizeof(RID_DEVICE_INFO);
    if (GetRawInputDeviceInfoW(device.hDevice, RIDI_DEVICEINFO, &info, &size) <= 0) {
      continue;
    }
    if (info.hid.dwVendorId == vendor_id && info.hid.dwProductId == product_id) {
      target_device_handle_ = device.hDevice;
      break;
    }
  }

  if (target_device_handle_ == nullptr) return;

  // RIDEV_INPUTSINK: receive this device's input even when our window
  // doesn't have foreground focus — the whole point of this plugin.
  RAWINPUTDEVICE rid;
  rid.usUsagePage = 0x01;  // Generic Desktop
  rid.usUsage = 0x06;      // Keyboard
  rid.dwFlags = RIDEV_INPUTSINK;
  rid.hwndTarget = registrar_->GetView()->GetNativeWindow();
  RegisterRawInputDevices(&rid, 1, sizeof(RAWINPUTDEVICE));
}

std::optional<LRESULT> RfidRawInputWindowsPlugin::HandleWindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_INPUT) {
    OnRawInput(lparam);
  }
  return std::nullopt;
}

void RfidRawInputWindowsPlugin::OnRawInput(LPARAM lparam) {
  if (target_device_handle_ == nullptr) return;

  UINT size = 0;
  GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, nullptr, &size,
                   sizeof(RAWINPUTHEADER));
  if (size == 0) return;

  std::vector<BYTE> buffer(size);
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, buffer.data(),
                       &size, sizeof(RAWINPUTHEADER)) != size) {
    return;
  }

  auto *raw = reinterpret_cast<RAWINPUT *>(buffer.data());
  if (raw->header.dwType != RIM_TYPEKEYBOARD) return;
  // Ignore input from any device other than our registered reader — this
  // is what makes the capture independent of window focus AND of the
  // kiosk's own reader's taps.
  if (raw->header.hDevice != target_device_handle_) return;

  const RAWKEYBOARD &kb = raw->data.keyboard;
  if (kb.Flags & RI_KEY_BREAK) return;  // key-up; only act on key-down

  BYTE keyboard_state[256] = {0};
  WCHAR decoded[4] = {0};
  int result = ToUnicode(kb.VKey, kb.MakeCode, keyboard_state, decoded, 4, 0);

  if (kb.VKey == VK_RETURN) {
    if (!buffer_.empty() && event_sink_) {
      // Narrow the wide buffer — RFID UIDs are ASCII digits/letters, so a
      // direct narrow is safe here (no non-ASCII characters expected).
      std::string uid(buffer_.begin(), buffer_.end());
      event_sink_->Success(EncodableValue(uid));
    }
    buffer_.clear();
    return;
  }

  if (result == 1) {
    buffer_ += decoded[0];
  }
}

}  // namespace rfid_raw_input_windows
```

- [ ] **Step 5: Write `CMakeLists.txt`** (mirrors the standard generated plugin template — `flutter create --template=plugin` from Step 1 already produces a correct one; confirm it lists `rfid_raw_input_windows_plugin.cpp` as a source and links `flutter_wrapper_plugin`. No changes needed if the scaffold step generated it correctly — verify, don't rewrite blindly.)

- [ ] **Step 6: Add the dependency in `attendance_display/pubspec.yaml`**

```yaml
  rfid_raw_input_windows:
    path: ../packages/rfid_raw_input_windows
```

- [ ] **Step 7: Wire it into `main.dart`, alongside the Task 6 fallback**

```dart
      home: AttendanceEnv.configured
          ? Builder(builder: (context) {
              final controller = TapFeedController(Supabase.instance.client);
              controller.start();
              return ReaderInputCapture(
                child: TapDisplayScreen(tapStream: controller.stream),
              );
            })
          : ...
```

Then have `ReaderInputCapture` also listen to `RfidRawInputReader.taps(vendorId, productId)` (vendor/product id read from `.env`, same pattern as `readerUsbSerial`) and call the same `_handleSubmit` logic for whichever source fires — Raw Input when it successfully found the device, the focused text field as a fallback when it didn't (`RfidRawInputReader.deviceFound` returning false). This keeps the app working even before Raw Input is confirmed reliable on-site.

- [ ] **Step 8: Manual hardware verification (cannot be automated)**

With the real reader connected and its actual vendor/product ID read from Windows Device Manager (Properties → Details → Hardware Ids, format `VID_xxxx&PID_xxxx`) filled into `.env`:
1. Run `cd attendance_display && flutter run -d windows`.
2. Click into an *unrelated* window (e.g. Notepad) so the attendance display does NOT have focus.
3. Tap the entrance reader.
4. Confirm the welcome card still appears — this is the actual proof Raw Input is working; if it only works while the display window has focus, the plugin isn't intercepting correctly and Task 6's fallback is what's actually firing.

- [ ] **Step 9: Commit**

```bash
git add packages/rfid_raw_input_windows/ attendance_display/pubspec.yaml attendance_display/lib/main.dart attendance_display/lib/reader_input_field.dart
git commit -m "feat: capture entrance reader taps via Windows Raw Input, independent of focus"
```

---

### Task 8: Reader-prefix defense-in-depth (conditional on hardware support)

**Files:**
- Modify: `attendance_display/lib/reader_input_field.dart`
- Modify: `attendance_display/lib/env.dart`
- Test: `attendance_display/test/reader_prefix_test.dart`

**Interfaces:**
- Consumes: `ReaderInputCapture` (Task 6/7).
- Produces: `stripReaderPrefix(String raw, String expectedPrefix) -> String?` — pure function, returns null (discard) when the input doesn't carry the expected prefix, otherwise the UID with the prefix removed.

This only applies if the physical reader actually supports configuring a distinct prefix character (check the model's documentation or config utility — not something this plan can verify). If it doesn't, skip this task; nothing else depends on it.

- [ ] **Step 1: Write the failing test**

```dart
// attendance_display/test/reader_prefix_test.dart
import 'package:attendance_display/reader_input_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips a matching prefix and returns the UID', () {
    expect(stripReaderPrefix('#1234567890', '#'), '1234567890');
  });

  test('discards input without the expected prefix', () {
    expect(stripReaderPrefix('1234567890', '#'), isNull);
  });

  test('passes input through unchanged when no prefix is configured', () {
    expect(stripReaderPrefix('1234567890', ''), '1234567890');
  });
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd attendance_display && flutter test test/reader_prefix_test.dart` — expect failure (function doesn't exist).

- [ ] **Step 3: Add `stripReaderPrefix` to `reader_input_field.dart`**

```dart
/// Returns [raw] with [expectedPrefix] removed, or null if [raw] doesn't
/// carry it — a cheap safety net against a misdirected tap from the
/// kiosk's own reader being misread as an entrance tap (or vice versa),
/// independent of whether Raw Input (Task 7) is working correctly. A
/// blank [expectedPrefix] means the reader isn't configured with one —
/// every input passes through unchanged.
String? stripReaderPrefix(String raw, String expectedPrefix) {
  if (expectedPrefix.isEmpty) return raw;
  if (!raw.startsWith(expectedPrefix)) return null;
  return raw.substring(expectedPrefix.length);
}
```

- [ ] **Step 4: Run the test, confirm it passes**

Run: `cd attendance_display && flutter test test/reader_prefix_test.dart` — expect PASS.

- [ ] **Step 5: Add `readerPrefix` to `AttendanceEnv`** (Task 3's `env.dart`) — same pattern as its other fields, sourced from a new `READER_PREFIX` `.env` key, defaulting to `''` (not required for `configured`, since most readers won't support this).

- [ ] **Step 6: Call it in `ReaderInputCapture._handleSubmit`** (Task 6/7) — before calling `record_rfid_tap`, run the raw value through `stripReaderPrefix(uid, AttendanceEnv.readerPrefix)`; if it returns null, return early without calling the RPC.

- [ ] **Step 7: Manual verification**

Confirm the specific reader model supports prefix configuration (check its documentation/config utility) before relying on this — if it doesn't, leave `READER_PREFIX` blank in `.env` and this task's code is a no-op passthrough.

- [ ] **Step 8: Commit**

```bash
git add attendance_display/lib/reader_input_field.dart attendance_display/lib/env.dart attendance_display/test/reader_prefix_test.dart
git commit -m "feat: add reader-prefix defense-in-depth against cross-reader taps"
```
