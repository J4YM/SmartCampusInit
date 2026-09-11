# RFID Assignment Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the Registrar's "students missing RFID" notice as a real, queryable request queue, and give IT Technician a dedicated tab to see it, with auto-resolution when an RFID number is actually assigned.

**Architecture:** A new `rfid_assignment_requests` table + a `security definer` RPC (`notify_rfid_missing`) that both inserts requests and notifies IT Technician via the existing shared `notifications` table — mirroring `report_technical_issue`'s established pattern exactly. A single shared `RfidRequestsRepository` (`lib/data/`) is consumed by both `RegistrarConnectedPage` (submit + view own log) and `ItTechnicianConnectedPage` (view full queue + auto-resolve on assignment).

**Tech Stack:** Flutter, Supabase (Postgres + PostgREST + RLS), `registrar_module` and `rfid_management_module` presentation packages.

**Spec:** `docs/superpowers/specs/2026-09-11-rfid-assignment-requests-design.md`

## Global Constraints

- Any new/changed SQL must be shown to the user for manual approval in Supabase's SQL editor — **never auto-run** any SQL yourself, under any circumstance. Just write the file.
- Demo-account UUID guard, required on both the submit action and the log-loading action: static demo accounts (`lib/auth/static_demo_accounts.dart`) have ids like `"u_registrar"` — not valid UUIDs, no real Supabase Auth session. Both must be `null`/skipped for such an account, matching the exact established guard pattern already in `RegistrarConnectedPage._notifiableUserId` (excludes any id starting with `u_`).
- `RfidRequestsRepository` is ONE shared class in `lib/data/`, consumed by both `RegistrarConnectedPage` and `ItTechnicianConnectedPage` — never duplicated per-module.
- No custom note/message field on submission, no manual "dismiss" action (only Pending/Fulfilled, and Fulfilled only via an actual RFID assignment), no deep-linking from the new tab into Student Records — all explicitly out of scope per the spec's Non-goals.
- Repository methods get signature-guard tests (construct with a fake Supabase URL, tear off the method against its exact function-type signature, never call it) — this codebase's established pattern.
- Demo-mode fallback convention: every new connected-page callback must be `null` when `AppEnv.supabaseConfigured` is false (or the guard excludes the account), and every presentation-package widget consuming it must already fall back to existing local/demo behavior when it's null.

---

### Task 1: Schema + `RfidRequestsRepository`

**Files:**
- Create: `supabase/add_rfid_assignment_requests_schema.sql`
- Create: `lib/data/rfid_requests_repository.dart`
- Test: `test/rfid_requests_repository_test.dart`

**Interfaces:**
- Produces: `RfidRequestModel` (`{id, studentName, studentNumber, section, requestedByName, requestedAt, isFulfilled}`), `RfidRequestsRepository.notifyRfidMissing({required List<String> studentIds, required String registrarId}) -> Future<int>`, `RfidRequestsRepository.fetchMyRequests(String registrarId) -> Future<List<RfidRequestModel>>`, `RfidRequestsRepository.fetchAllRequests() -> Future<List<RfidRequestModel>>`, `RfidRequestsRepository.markFulfilled(String studentId) -> Future<void>`.
- Consumes: nothing from other tasks — fully self-contained.

- [ ] **Step 1: Write the SQL migration**

```sql
-- supabase/add_rfid_assignment_requests_schema.sql
--
-- One row per student a Registrar flags as missing RFID. Registrar
-- submits via notify_rfid_missing (security definer — Registrar has
-- no direct INSERT access, matching report_technical_issue's
-- established pattern); IT Technician/Admin can see and update the
-- queue directly. Only one *pending* request per student at a time —
-- resubmitting for an already-pending student is a harmless no-op,
-- not a duplicate row.
--
-- Run in Supabase SQL Editor.

create table if not exists public.rfid_assignment_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  requested_by uuid references public.profiles(id),
  requested_at timestamptz not null default now(),
  status text not null default 'Pending' check (status in ('Pending', 'Fulfilled')),
  fulfilled_at timestamptz
);

create unique index if not exists idx_rfid_assignment_requests_pending_student
  on public.rfid_assignment_requests(student_id)
  where status = 'Pending';

create index if not exists idx_rfid_assignment_requests_requested_by
  on public.rfid_assignment_requests(requested_by);

alter table public.rfid_assignment_requests enable row level security;

drop policy if exists "rfid_assignment_requests_select" on public.rfid_assignment_requests;
create policy "rfid_assignment_requests_select"
on public.rfid_assignment_requests for select
to authenticated
using (
  current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
  or requested_by = auth.uid()
);

drop policy if exists "rfid_assignment_requests_update" on public.rfid_assignment_requests;
create policy "rfid_assignment_requests_update"
on public.rfid_assignment_requests for update
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

-- No INSERT policy for authenticated — inserts only ever happen via
-- notify_rfid_missing below (security definer, bypasses RLS).

-- p_registrar_id is an explicit parameter, not auth.uid() — the
-- static demo accounts (lib/auth/static_demo_accounts.dart) never
-- hold a real Supabase Auth session, the same reason
-- report_technical_issue takes its actor id explicitly.
create or replace function public.notify_rfid_missing(
  p_student_ids uuid[],
  p_registrar_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_names text;
begin
  insert into public.rfid_assignment_requests (student_id, requested_by)
  select unnest(p_student_ids), p_registrar_id
  on conflict (student_id) where status = 'Pending' do nothing;

  get diagnostics v_count = row_count;

  if v_count > 0 then
    select string_agg(trim(p.first_name || ' ' || p.last_name), ', ')
      into v_names
      from public.students s
      join public.profiles p on p.id = s.id
      where s.id = any(p_student_ids);

    insert into public.notifications (target_role, title, message)
    values (
      'IT_Technician'::app_role,
      'Students need RFID cards assigned',
      coalesce(v_names, 'Selected students') || ' need an RFID card assigned.'
    );
  end if;

  return v_count;
end;
$$;

revoke all on function public.notify_rfid_missing(uuid[], uuid) from public;
grant execute on function public.notify_rfid_missing(uuid[], uuid) to anon, authenticated;
```

- [ ] **Step 2: Get user approval, then have them run it in Supabase SQL Editor**

Show the exact SQL above and wait for confirmation before continuing — this repo's established convention: do not run it yourself, and do not proceed past this step until you have explicit confirmation. (If you are a dispatched implementer subagent with no channel to the real human, skip waiting — write the file, note in your report that it's pending manual execution, and continue; your coordinator relays it. Nothing in the remaining steps requires the SQL to have actually been run, since the signature-guard test never calls the live database.)

- [ ] **Step 3: Write the failing signature-guard test**

```dart
// test/rfid_requests_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/rfid_requests_repository.dart';

void main() {
  test('RfidRequestsRepository methods have the expected signatures', () {
    final repo = RfidRequestsRepository(
      SupabaseClient('https://example.invalid', 'anon-key'),
    );

    final Future<int> Function({
      required List<String> studentIds,
      required String registrarId,
    }) notifyRfidMissing = repo.notifyRfidMissing;
    expect(notifyRfidMissing, isNotNull);

    final Future<List<RfidRequestModel>> Function(String registrarId)
        fetchMyRequests = repo.fetchMyRequests;
    expect(fetchMyRequests, isNotNull);

    final Future<List<RfidRequestModel>> Function() fetchAllRequests =
        repo.fetchAllRequests;
    expect(fetchAllRequests, isNotNull);

    final Future<void> Function(String studentId) markFulfilled =
        repo.markFulfilled;
    expect(markFulfilled, isNotNull);
  });
}
```

- [ ] **Step 4: Run it, confirm it fails**

Run: `flutter test test/rfid_requests_repository_test.dart` — expect failure (the file/class don't exist yet).

- [ ] **Step 5: Write `lib/data/rfid_requests_repository.dart`**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class RfidRequestModel {
  const RfidRequestModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.requestedByName,
    required this.requestedAt,
    required this.isFulfilled,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final String requestedByName;
  final DateTime requestedAt;
  final bool isFulfilled;
}

/// Backs the "students need RFID" request queue — shared by Registrar
/// (submits requests, views their own submission history) and IT
/// Technician (views the full queue, auto-resolves on assignment). See
/// docs/superpowers/specs/2026-09-11-rfid-assignment-requests-design.md.
class RfidRequestsRepository {
  RfidRequestsRepository(this._client);
  final SupabaseClient _client;

  static const _select = '''
    id,
    requested_at,
    status,
    students ( student_number, profiles ( first_name, last_name ), sections ( name ) ),
    profiles ( first_name, last_name )
  ''';

  Future<int> notifyRfidMissing({
    required List<String> studentIds,
    required String registrarId,
  }) async {
    final result = await _client.rpc(
      'notify_rfid_missing',
      params: {'p_student_ids': studentIds, 'p_registrar_id': registrarId},
    );
    return result as int;
  }

  /// Registrar's own submission history — backs "View Logs".
  Future<List<RfidRequestModel>> fetchMyRequests(String registrarId) async {
    final rows = await _client
        .from('rfid_assignment_requests')
        .select(_select)
        .eq('requested_by', registrarId)
        .order('requested_at', ascending: false);
    return _mapRows(rows as List<dynamic>);
  }

  /// The full queue — backs IT Technician's "RFID Requests" tab and
  /// Overview's pending-count stat card.
  Future<List<RfidRequestModel>> fetchAllRequests() async {
    final rows = await _client
        .from('rfid_assignment_requests')
        .select(_select)
        .order('requested_at', ascending: false);
    return _mapRows(rows as List<dynamic>);
  }

  /// Called after a successful RFID assignment in Student Records — a
  /// no-op if no pending request exists for this student.
  Future<void> markFulfilled(String studentId) async {
    await _client
        .from('rfid_assignment_requests')
        .update({
          'status': 'Fulfilled',
          'fulfilled_at': DateTime.now().toIso8601String(),
        })
        .eq('student_id', studentId)
        .eq('status', 'Pending');
  }

  List<RfidRequestModel> _mapRows(List<dynamic> rows) {
    return rows.map((e) {
      final row = e as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final studentProfile = student?['profiles'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;
      final requester = row['profiles'] as Map<String, dynamic>?;
      return RfidRequestModel(
        id: row['id'] as String,
        studentName: _fullName(
          studentProfile?['first_name'] as String?,
          studentProfile?['last_name'] as String?,
        ),
        studentNumber: student?['student_number'] as String? ?? '',
        section: section?['name'] as String? ?? '',
        requestedByName: _fullName(
          requester?['first_name'] as String?,
          requester?['last_name'] as String?,
        ),
        requestedAt: DateTime.parse(row['requested_at'] as String),
        isFulfilled: row['status'] == 'Fulfilled',
      );
    }).toList();
  }

  String _fullName(String? first, String? last) =>
      '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
}
```

(`students(profiles(...))` nested, and a direct top-level `profiles(...)` for `requested_by`, are two unambiguous embeds of the same target table from different parent contexts — `rfid_assignment_requests` has exactly one direct FK to `profiles`, so PostgREST needs no `!fkey_name` disambiguation hint here.)

- [ ] **Step 6: Run the test, confirm it passes**

Run: `flutter test test/rfid_requests_repository_test.dart` — expect PASS.

- [ ] **Step 7: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/data/rfid_requests_repository.dart` — expect no issues.

- [ ] **Step 8: Commit**

```bash
git add supabase/add_rfid_assignment_requests_schema.sql lib/data/rfid_requests_repository.dart test/rfid_requests_repository_test.dart
git commit -m "feat: add rfid_assignment_requests schema + RfidRequestsRepository"
```

---

### Task 2: Registrar side — real submit + real view logs

**Files:**
- Modify: `lib/ui/registrar_connected_page.dart`
- Modify: `packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart`

**Interfaces:**
- Consumes: `RfidRequestsRepository.notifyRfidMissing`/`fetchMyRequests` (Task 1).
- Produces: `RegistrarDashboardPage.onSubmitNotify` (new callback, `Future<void> Function(List<String> studentIds)?`), `RegistrarDashboardPage.initialRfidNotificationLogs` (new prop, `List<RfidNotificationLogModel>?`) — no later task in this plan depends on either.

**Context:** `RfidNotificationLogModel` already exists (`packages/registrar_module/lib/pages/dashboard/rfid_notification_logs_dialog.dart`) with exactly `{studentName, studentId, section}` — unchanged by this task. `RfidManagementView.onSubmitNotify` is already `ValueChanged<List<String>>?` and `onViewLogs` is already `VoidCallback?` — neither of THOSE signatures change; only what feeds them does.

- [ ] **Step 1: Add `onSubmitNotify`/`initialRfidNotificationLogs` to `RegistrarDashboardPage`, make `_rfidNotificationLogs` real**

Read `packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart` in full first — specifically the constructor (around line 209-228, alongside `onEnrollSection`), the `_RegistrarDashboardPageState` field declarations (around line 310-329, where `final List<RfidNotificationLogModel> _rfidNotificationLogs = [];` currently lives), `initState`/`didUpdateWidget` (around line 331-370), `_submitRfidNotifications` (around line 696-721), and `_showRfidNotificationLogs` (around line 777-783).

Add to the constructor, alongside `onEnrollSection`:

```dart
    this.onSubmitNotify,
    this.initialRfidNotificationLogs,
```

Add to the class body:

```dart
  /// Called with the selected students' ids when "Submit & Notify" is
  /// tapped on the RFID Notify tab. Falls back to purely-local demo
  /// behavior (flips hasRfid in memory, no persistence) when omitted.
  final Future<void> Function(List<String> studentIds)? onSubmitNotify;

  /// The signed-in registrar's own past RFID-notify submissions — backs
  /// "View Logs". Null/omitted falls back to an empty list (no curated
  /// mock data exists for this — matches the demo behavior this tab
  /// already had before this task).
  final List<RfidNotificationLogModel>? initialRfidNotificationLogs;
```

Change the `_rfidNotificationLogs` field declaration from:
```dart
  final List<RfidNotificationLogModel> _rfidNotificationLogs = [];
```
to:
```dart
  late List<RfidNotificationLogModel> _rfidNotificationLogs;
```

In `initState()`, alongside the other `late` field seeds, add:
```dart
    _rfidNotificationLogs = widget.initialRfidNotificationLogs ?? [];
```
(A growable `[]`, not `const []` — the demo-fallback path in `_submitRfidNotifications`, step 2 below, still needs to append to this list locally when `onSubmitNotify` is null.)

In `didUpdateWidget`, alongside the existing sync blocks, add:
```dart
    final newRfidLogs = widget.initialRfidNotificationLogs;
    if (newRfidLogs != null && newRfidLogs != oldWidget.initialRfidNotificationLogs) {
      _rfidNotificationLogs = newRfidLogs;
    }
```

- [ ] **Step 2: Wire `_submitRfidNotifications` through the new callback, matching the established null-fallback shape**

Replace `_submitRfidNotifications`'s body:

```dart
  void _submitRfidNotifications(List<String> selectedIds) {
    final onSubmitNotify = widget.onSubmitNotify;
    if (onSubmitNotify == null) {
      final notified =
          students.where((s) => selectedIds.contains(s.id)).toList();
      setState(() {
        students = students
            .map((s) => selectedIds.contains(s.id)
                ? s.copyWith(hasRfid: true)
                : s)
            .toList();
        _rfidNotificationLogs = [
          ...notified.map((s) => RfidNotificationLogModel(
                studentName: s.name,
                studentId: s.studentId,
                section: s.section,
              )),
          ..._rfidNotificationLogs,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'RFID assignment notice sent for ${selectedIds.length} student(s).',
          ),
        ),
      );
      return;
    }
    onSubmitNotify(selectedIds);
  }
```

(This preserves the exact old demo behavior when `onSubmitNotify` is null, matching `_saveGradeChanges`/`_saveScheduleChanges`'s established shape. `_showRfidNotificationLogs` itself needs NO changes — it already just opens `RfidNotificationLogsDialog(logs: _rfidNotificationLogs)`, and `_rfidNotificationLogs` is now real data when configured.)

- [ ] **Step 3: Run analyze to confirm this file alone still compiles**

Run: `flutter analyze packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart` — expect no issues (the two new fields are both optional/nullable, so no existing call site of `RegistrarDashboardPage(...)` needs to change).

- [ ] **Step 4: Wire `RegistrarConnectedPage`**

Read `lib/ui/registrar_connected_page.dart` in full first.

Add a `RfidRequestsRepository? get _rfidRequestsRepo` getter, matching every other repo getter's exact shape:

```dart
  RfidRequestsRepository? get _rfidRequestsRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return RfidRequestsRepository(Supabase.instance.client);
  }
```

Add the import: `import '../data/rfid_requests_repository.dart';`.

Add a `List<RfidNotificationLogModel>? _myRfidRequests;` field.

Add `_loadMyRfidRequests()`, matching `_loadGradeRecords()`'s exact try/catch/`_toast`-on-failure shape, guarded on BOTH the repo and the demo-account check (`_notifiableUserId`, which already exists in this file and already returns `null` for a `u_`-prefixed id):

```dart
  Future<void> _loadMyRfidRequests() async {
    final repo = _rfidRequestsRepo;
    final registrarId = _notifiableUserId;
    if (repo == null || registrarId == null) return;
    try {
      final requests = await repo.fetchMyRequests(registrarId);
      if (!mounted) return;
      setState(() {
        _myRfidRequests = requests
            .map((r) => RfidNotificationLogModel(
                  studentName: r.studentName,
                  studentId: r.studentNumber,
                  section: r.section,
                ))
            .toList();
      });
    } catch (e) {
      _toast('Could not load RFID request history: $e');
    }
  }
```

Add `_submitRfidNotifications`, same guard shape:

```dart
  Future<void> _submitRfidNotifications(List<String> studentIds) async {
    final repo = _rfidRequestsRepo;
    final registrarId = _notifiableUserId;
    if (repo == null || registrarId == null) return;
    try {
      final count = await repo.notifyRfidMissing(
        studentIds: studentIds,
        registrarId: registrarId,
      );
      await _loadMyRfidRequests();
      _toast(
        count > 0
            ? 'RFID assignment notice sent for $count student(s).'
            : 'Selected student(s) already have a pending request.',
      );
    } catch (e) {
      _toast('Could not send RFID notice: $e');
    }
  }
```

Add `_loadMyRfidRequests()` to `initState`'s existing sequence of `WidgetsBinding.instance.addPostFrameCallback((_) => ...)` calls, in the same style as `_loadGradeRecords`.

In the `build` method's `RegistrarDashboardPage(...)` construction, add:

```dart
      initialRfidNotificationLogs: _myRfidRequests,
      onSubmitNotify: (_rfidRequestsRepo == null || _notifiableUserId == null)
          ? null
          : _submitRfidNotifications,
```

Update this file's class-level doc comment (currently lists which tables/tabs are real) to mention `rfid_assignment_requests`/RFID Notify alongside the others.

Add `RfidRequestsRepository`/`RfidRequestModel` to whatever import already brings in `RfidNotificationLogModel` from `package:registrar_module/registrar_module.dart` if it isn't already covered — check the top of the file first (it likely already has a bare `import 'package:registrar_module/registrar_module.dart';` covering `RfidNotificationLogModel`).

- [ ] **Step 5: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/ui/registrar_connected_page.dart packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart` — expect no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/registrar_connected_page.dart packages/registrar_module/lib/pages/dashboard/registrar_dashboard_page.dart
git commit -m "feat: wire Registrar's RFID Notify tab to real requests"
```

---

### Task 3: IT Technician's new "RFID Requests" tab (presentation layer)

**Files:**
- Create: `packages/rfid_management_module/lib/ui/rfid_requests_tab.dart`
- Modify: `packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart`
- Modify: `packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart`

**Interfaces:**
- Produces: `RfidRequestRowModel` (`{id, studentName, studentNumber, section, requestedByLabel, requestedAtLabel, isFulfilled}`), `RfidRequestsTab` widget (`{required List<RfidRequestRowModel> requests}`), `ItTechnicianDashboardTab.rfidRequests` (new enum value), `ItTechnicianDashboardPage.rfidRequestsTabBuilder` (new required `WidgetBuilder`), `ItTechnicianOverviewStats.rfidRequestsPending` (new required `int` field).
- Consumes: nothing from other tasks in this plan — presentation-only, no repository wiring yet (Task 4 wires real data in).

**Context:** This task is scoped exactly like every other tab's initial UI scaffolding elsewhere in this codebase — a read-only list widget with no filter, no actions, no navigation beyond what's already true of a plain list (per the spec's Non-goals: no dismiss action, no deep-link). Read `packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart` in full first, especially the `enum ItTechnicianDashboardTab` (line 16), `ItTechnicianOverviewStats` (line 53-65), the constructor's `required this.technicalIssuesTabBuilder` (line 78), `_buildTabContent`'s switch (line 374-390), `_SubNavBar._tabs` (line 399-415), and `_MetricsRow` (line 505-549) — this brief's line numbers may drift if the file changed since this brief was written; confirm by reading before editing.

- [ ] **Step 1: Write `RfidRequestRowModel` and `RfidRequestsTab`**

```dart
// packages/rfid_management_module/lib/ui/rfid_requests_tab.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

class RfidRequestRowModel {
  const RfidRequestRowModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.requestedByLabel,
    required this.requestedAtLabel,
    required this.isFulfilled,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String section;
  final String requestedByLabel;
  final String requestedAtLabel;
  final bool isFulfilled;
}

/// Read-only queue of Registrar's "students need RFID" requests — no
/// filter, no dismiss action, no deep-link into Student Records (see
/// docs/superpowers/specs/2026-09-11-rfid-assignment-requests-design.md's
/// Non-goals). A request clears itself once IT Technician actually
/// assigns an RFID number to that student via Student Records.
class RfidRequestsTab extends StatelessWidget {
  const RfidRequestsTab({super.key, required this.requests});

  final List<RfidRequestRowModel> requests;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ItTechnicianColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RFID Requests',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ItTechnicianColors.rowText(context),
            ),
          ),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            Text(
              'No RFID requests yet.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            )
          else
            for (final request in requests) _RfidRequestRow(request: request),
        ],
      ),
    );
  }
}

class _RfidRequestRow extends StatelessWidget {
  const _RfidRequestRow({required this.request});

  final RfidRequestRowModel request;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.studentName} — ${request.studentNumber}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText(context),
                  ),
                ),
                Text(
                  '${request.section} · Requested by ${request.requestedByLabel} on ${request.requestedAtLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: ItTechnicianColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: request.isFulfilled
                  ? const Color(0x33137333)
                  : const Color(0x33CD4855),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              request.isFulfilled ? 'Fulfilled' : 'Pending',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: request.isFulfilled
                    ? ItTechnicianColors.successGreen
                    : ItTechnicianColors.dangerRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Check `packages/rfid_management_module/lib/rfid_management_module.dart` (the barrel file) — add `export 'ui/rfid_requests_tab.dart';` if this package's barrel doesn't already cover everything in `ui/` via a wildcard-style set of exports (check the existing pattern for `technical_issues_tab.dart`'s export line and mirror it exactly).

- [ ] **Step 2: Add the 4th tab to `ItTechnicianDashboardPage`**

In `enum ItTechnicianDashboardTab`, add `rfidRequests`:
```dart
enum ItTechnicianDashboardTab { studentRecords, readerDevices, technicalIssues, rfidRequests }
```

In `ItTechnicianOverviewStats`, add `rfidRequestsPending`:
```dart
class ItTechnicianOverviewStats {
  const ItTechnicianOverviewStats({
    required this.totalStudents,
    required this.totalReaders,
    required this.onlineReaders,
    required this.openTicketCount,
    required this.rfidRequestsPending,
  });

  final int totalStudents;
  final int totalReaders;
  final int onlineReaders;
  final int openTicketCount;
  final int rfidRequestsPending;
}
```

In `ItTechnicianDashboardPage`'s constructor, add `required this.rfidRequestsTabBuilder,` alongside `required this.technicalIssuesTabBuilder,`, and the field:
```dart
  final WidgetBuilder rfidRequestsTabBuilder;
```

In `_buildTabContent`'s switch, add a case:
```dart
      case ItTechnicianDashboardTab.rfidRequests:
        return widget.rfidRequestsTabBuilder(context);
```

In `_SubNavBar._tabs`, add an entry:
```dart
    (
      ItTechnicianDashboardTab.rfidRequests,
      'RFID Requests',
      Icons.contactless_outlined,
    ),
```

In `_MetricsRow.build`, update the `stats ?? const ItTechnicianOverviewStats(...)` fallback to include `rfidRequestsPending: 0,`, and add a stat card to the `cards` list:
```dart
      _StatCard(
        label: 'RFID Requests Pending',
        value: '${s.rfidRequestsPending}',
        icon: Icons.contactless_outlined,
      ),
```

- [ ] **Step 3: Update the test file's two construction sites**

Read `packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart` in full first — it constructs `ItTechnicianDashboardPage` twice (once in the shared `buildPage()` helper, once directly in the mobile-viewport test). Add `rfidRequestsTabBuilder: (_) => const Center(child: Text('RFID Requests Content')),` to BOTH construction sites, matching the existing stub-builder style used for `studentRecordsTabBuilder`/`technicalIssuesTabBuilder` in each.

- [ ] **Step 4: Run the full suite and analyze**

Run: `flutter test packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart` (from the worktree root — do NOT `cd` into the package first; this environment has a known issue where running tests from inside a package resolves a stale, incompatible `google_fonts` version and fails to compile for unrelated reasons) — expect all existing tests still PASS (the new required builder doesn't change any existing assertion).

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze packages/rfid_management_module` — expect no issues.

- [ ] **Step 5: Commit**

```bash
git add packages/rfid_management_module/lib/ui/rfid_requests_tab.dart packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart packages/rfid_management_module/lib/rfid_management_module.dart packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart
git commit -m "feat: add IT Technician's RFID Requests tab (presentation layer)"
```

(Only `git add` `rfid_management_module.dart` if Step 1 actually needed to change it.)

---

### Task 4: Wire real data into IT Technician + auto-resolve

**Files:**
- Modify: `lib/ui/it_technician_connected_page.dart`

**Interfaces:**
- Consumes: `RfidRequestsRepository.fetchAllRequests`/`markFulfilled` (Task 1), `RfidRequestRowModel`/`RfidRequestsTab`/`ItTechnicianDashboardTab.rfidRequests`/`rfidRequestsTabBuilder`/`ItTechnicianOverviewStats.rfidRequestsPending` (Task 3).
- Produces: nothing further in this plan — this is the last task.

**Context:** Read `lib/ui/it_technician_connected_page.dart` in full first — specifically `_studentsRepo`/`_issuesRepo`-style getters (around line 98), `_loadOverviewStats` (around line 454-478), `_saveStudent` (around line 240-278, where `repo.update(...)` is called with `rfidUid: form.rfidNo` when `editing != null`), `initState` (around line 513-524), and the `build` method's `ItTechnicianDashboardPage(...)` construction (around line 536-626) — this brief's line numbers may drift if the file changed since this brief was written; confirm by reading before editing.

- [ ] **Step 1: Add the repository getter and load method**

Add a `RfidRequestsRepository? get _rfidRequestsRepo`, matching `_studentsRepo`'s exact shape:

```dart
  RfidRequestsRepository? get _rfidRequestsRepo =>
      AppEnv.supabaseConfigured ? RfidRequestsRepository(Supabase.instance.client) : null;
```

Add the import: `import '../data/rfid_requests_repository.dart';`.

Add a `List<RfidRequestModel>? _rfidRequests;` field.

Add `_loadRfidRequests()`:

```dart
  Future<void> _loadRfidRequests() async {
    final repo = _rfidRequestsRepo;
    if (repo == null) return;
    try {
      final requests = await repo.fetchAllRequests();
      if (!mounted) return;
      setState(() => _rfidRequests = requests);
    } catch (e) {
      debugPrint('Could not load RFID requests: $e');
    }
  }
```

Add `_loadRfidRequests()` to `initState`'s existing `addPostFrameCallback` sequence, alongside `_loadStudents`/`_loadReaders`/`_loadReports`/`_loadOverviewStats`/`_loadNotifications`.

- [ ] **Step 2: Compute the Overview pending count**

In `_loadOverviewStats()`, add a third branch alongside the existing `studentsRepo`/`issuesRepo` blocks:

```dart
      final rfidRequestsRepo = _rfidRequestsRepo;
      if (rfidRequestsRepo != null) {
        final allRequests = await rfidRequestsRepo.fetchAllRequests();
        if (!mounted) return;
        setState(() => _overviewRfidRequestsPending =
            allRequests.where((r) => !r.isFulfilled).length);
      }
```

Add the backing field `int? _overviewRfidRequestsPending;` alongside `_overviewTotalStudentCount`/`_overviewOpenTicketCount` (read the existing field declarations first to match their exact naming/nullability style).

In the `build` method's `ItTechnicianOverviewStats(...)` construction, add:
```dart
        rfidRequestsPending: _overviewRfidRequestsPending ?? 0,
```

- [ ] **Step 3: Wire the new tab builder**

In the `build` method's `ItTechnicianDashboardPage(...)` construction, add:

```dart
      rfidRequestsTabBuilder: (_) => RfidRequestsTab(
        requests: (_rfidRequests ?? const [])
            .map((r) => RfidRequestRowModel(
                  id: r.id,
                  studentName: r.studentName,
                  studentNumber: r.studentNumber,
                  section: r.section,
                  requestedByLabel: r.requestedByName,
                  requestedAtLabel: _formatRequestDate(r.requestedAt),
                  isFulfilled: r.isFulfilled,
                ))
            .toList(),
      ),
```

Add a small private date formatter (check first whether this file already has a similar date-formatting helper elsewhere to reuse instead of introducing a new one — if one exists, use it instead of this snippet):

```dart
  String _formatRequestDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
```

- [ ] **Step 4: Wire the auto-resolve hook**

In `_saveStudent`, find the `if (editing != null) { await repo.update(...); }` branch. Immediately after that `await repo.update(...)` call succeeds (still inside the `if (editing != null)` block, after the `update` call, before the method's existing `await _loadStudents(); await _loadOverviewStats();` calls), add:

```dart
        if (form.rfidNo.trim().isNotEmpty) {
          final rfidRequestsRepo = _rfidRequestsRepo;
          if (rfidRequestsRepo != null) {
            await rfidRequestsRepo.markFulfilled(editing.id);
            await _loadRfidRequests();
          }
        }
```

Read the actual current body of `_saveStudent` first — this brief's understanding of exactly where `await repo.update(...)` sits relative to the surrounding `try`/`finally` may not be perfectly precise; place this block logically right after the update succeeds, inside the same `try`, not inside the `finally`.

- [ ] **Step 5: Run the full suite and analyze**

Run: `flutter test -j 1` — expect all passing except the one pre-existing, unrelated `guidance_counselor_cold_boot_mobile_test.dart` failure.

Run: `flutter analyze lib/ui/it_technician_connected_page.dart` — expect no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/it_technician_connected_page.dart
git commit -m "feat: wire IT Technician's RFID Requests tab to real data + auto-resolve"
```
