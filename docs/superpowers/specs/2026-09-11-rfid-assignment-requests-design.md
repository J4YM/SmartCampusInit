# Registrar RFID-Missing Notice → IT Technician Dashboard

## Context

The Registrar module's "RFID Notify" tab (`RfidManagementView`) lets a
registrar select students missing an RFID card and click "Submit &
Notify." Today this is entirely fake: `_submitRfidNotifications`
(`registrar_dashboard_page.dart`) only flips `hasRfid` on the local,
in-memory `students` list and appends to an in-memory
`_rfidNotificationLogs` list — nothing reaches Supabase, and
`RegistrarConnectedPage` has no callback for this action at all. The
"View Logs" dialog reads that same fake in-memory list. On any reload,
the local `hasRfid` flip reverts, since `RegistrarRepository.fetchStudents()`
still reads the real (unchanged) `students.rfid_uid` column.

Meanwhile, the IT Technician Dashboard — the people who'd actually
issue/assign RFID cards — has zero visibility into any of this. Its
Student Records tab already has a manual "RFID No." text field in the
edit-student dialog (the only place `students.rfid_uid` is ever
actually set), but nothing tells IT Technician which students need
one, or that a registrar has flagged specific students.

This sub-project connects the two: a real, persisted, actionable
request queue, following the same shape this codebase already uses for
Technical Issues (`technical_issue_reports` + a `security definer` RPC
that also inserts into the shared `notifications` table).

## Goals

- Registrar's "Submit & Notify" persists a real request per selected
  student and notifies IT Technician via the existing shared
  notification bell.
- IT Technician gets a new, dedicated "RFID Requests" tab showing the
  real queue (student, section, requested by, requested date, status),
  plus a pending-count stat card on Overview.
- A request auto-resolves to Fulfilled the moment IT Technician saves
  a non-empty RFID number for that student via the Student Records
  edit dialog — no separate "mark resolved" action needed.
- Registrar's existing "View Logs" dialog shows their own real
  submission history instead of an in-memory list.

## Non-goals (explicitly out of scope)

- A custom note/message field on submission — the notice text is
  auto-generated from the selected students' names, matching the
  existing UI's "select rows, click a button" shape exactly.
- Any change to how RFID numbers actually get typed in — the existing
  Student Records edit dialog's free-text "RFID No." field is
  unchanged; this sub-project only adds a request queue around it.
- Deep-linking from the new RFID Requests tab straight into a specific
  student's edit dialog — IT Technician navigates to Student Records
  separately, same as Technical Issues and Student Records are already
  independent tabs today.
- A manual "dismiss without assigning" action — the only two states
  are Pending and Fulfilled (matching this codebase's established
  Good Moral Certificate request pattern), and Fulfilled only happens
  via an actual RFID assignment.

## Architecture

New table `rfid_assignment_requests`, one row per (student, submission
batch member). Registrar's submit action calls a new `security
definer` RPC, `notify_rfid_missing`, matching `report_technical_issue`'s
exact established template: it inserts request rows (skipping students
who already have a pending request, via a partial unique index) and,
if anything new was inserted, one row into the existing `notifications`
table targeted at `IT_Technician`. A new shared `RfidRequestsRepository`
(`lib/data/`) is consumed by both `RegistrarConnectedPage` (submit +
view own log) and `ItTechnicianConnectedPage` (view full queue + the
auto-resolve hook on student save) — mirroring how `StudentsRepository`
is already shared across both connected pages today.

## Component 1: Schema + RPC

```sql
-- supabase/add_rfid_assignment_requests_schema.sql

create table if not exists public.rfid_assignment_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  requested_by uuid references public.profiles(id),
  requested_at timestamptz not null default now(),
  status text not null default 'Pending' check (status in ('Pending', 'Fulfilled')),
  fulfilled_at timestamptz
);

-- Only one *pending* request per student at a time — resubmitting for
-- a student who's already pending is a harmless no-op, not a
-- duplicate row. A student can still accumulate multiple *historical*
-- (Fulfilled) rows over time (e.g. a card is lost and reassigned
-- later), since the partial index only constrains the Pending state.
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
-- notify_rfid_missing (security definer, bypasses RLS), matching
-- report_technical_issue's established pattern exactly.

-- p_registrar_id is an explicit parameter, not auth.uid() — the
-- static demo accounts (lib/auth/static_demo_accounts.dart) never
-- hold a real Supabase Auth session, the same reason
-- report_technical_issue/record_rfid_tap take their actor id
-- explicitly instead of trusting auth.uid().
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

`v_count` (students actually newly-queued, excluding no-op resubmits
of already-pending students) is returned so the Registrar-side toast
can say something accurate ("3 students queued for RFID assignment")
rather than a blind "sent" message — same honesty principle this
codebase's other write actions already follow (e.g. Class Schedule's
save toast names the real section used).

## Component 2: Registrar side — real submit + real log

`RegistrarRepository` gains no new methods (this RPC/read logic lives
in the new shared repository below, not duplicated into
`RegistrarRepository` — Registrar and IT Technician read/write the
exact same table through the exact same code).

New file `lib/data/rfid_requests_repository.dart`:

```dart
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

class RfidRequestsRepository {
  RfidRequestsRepository(this._client);
  final SupabaseClient _client;

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

  static const _select = '''
    id,
    requested_at,
    status,
    students ( student_number, profiles ( first_name, last_name ), sections ( name ) ),
    profiles ( first_name, last_name )
  ''';
  // Two sibling embeds of `profiles` from one base table (`students(profiles(...))`
  // nested, and a direct `profiles(...)` for `requested_by`) are unambiguous to
  // PostgREST here — `rfid_assignment_requests` has exactly one direct FK to
  // `profiles` (`requested_by`), so no `!fkey_name` disambiguation hint is
  // needed (contrast with student_violations, which has no direct FK to
  // profiles at all and needed the embed fixed for a different reason).

  /// Registrar's own submission history — backs "View Logs".
  Future<List<RfidRequestModel>> fetchMyRequests(String registrarId) async {
    final rows = await _client
        .from('rfid_assignment_requests')
        .select(_select)
        .eq('requested_by', registrarId)
        .order('requested_at', ascending: false);
    return _mapRows(rows);
  }

  /// The full queue — backs IT Technician's "RFID Requests" tab and
  /// Overview's pending-count stat card.
  Future<List<RfidRequestModel>> fetchAllRequests() async {
    final rows = await _client
        .from('rfid_assignment_requests')
        .select(_select)
        .order('requested_at', ascending: false);
    return _mapRows(rows);
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

  /// Called after a successful RFID assignment in Student Records — a
  /// no-op if no pending request exists for this student (e.g. the
  /// number was typed in without ever going through a notify flow).
  Future<void> markFulfilled(String studentId) async {
    await _client
        .from('rfid_assignment_requests')
        .update({'status': 'Fulfilled', 'fulfilled_at': DateTime.now().toIso8601String()})
        .eq('student_id', studentId)
        .eq('status', 'Pending');
  }
}
```

`RegistrarConnectedPage` gains an `onSubmitNotify`/`onViewLogs` pair
threaded through `RegistrarDashboardPage` (currently entirely absent —
`RfidManagementView` is invoked directly from
`registrar_dashboard_page.dart` today, bypassing the connected-page
layer). `_submitRfidNotifications`/`_rfidNotificationLogs`/
`RfidNotificationLogModel`'s in-memory-only bodies are replaced with
real calls through the new repository; the real submission toast
reports the RPC's actual `v_count`. "View Logs" reads
`fetchMyRequests` mapped into the existing (unchanged)
`RfidNotificationLogModel` view type the dialog already renders.

**Demo-account guard, required:** `requested_by`/`registrarId` flows
into a `uuid` column (`rfid_assignment_requests.requested_by`) and
into the RPC's `p_registrar_id uuid` parameter. Static demo accounts
(`lib/auth/static_demo_accounts.dart`) have ids like `"u_registrar"` —
not valid UUIDs, and not backed by a real Supabase Auth session —
so passing one straight through would fail the RPC call outright with
a type-cast error. `onSubmitNotify`/`onViewLogs` must both be `null`
when the signed-in user's id starts with `u_`, matching the exact
established guard already used elsewhere in this codebase (e.g.
`GuidanceCounselorConnectedPage._notifiableUserId`,
`StudentPortalConnectedPage._studentId`) — falling back to
`RfidManagementView`'s existing local/demo button behavior for a demo
session, same as every other guarded action in this app.

## Component 3: IT Technician side — real queue + auto-resolve

`ItTechnicianDashboardTab` gains a fourth value, `rfidRequests`,
alongside a new `rfidRequestsTabBuilder` prop on
`ItTechnicianDashboardPage` (mirrors `technicalIssuesTabBuilder`
exactly). The new tab is a read-only list (student, section, requested
by, requested date, Pending/Fulfilled status badge) — no filter, no
actions beyond what's already true of a plain list, matching this
sub-project's Non-goals (no dismiss, no deep-link).

`ItTechnicianOverviewStats` gains `rfidRequestsPending` alongside the
existing `totalStudents`/`totalReaders`/`onlineReaders`/
`openTicketCount`, computed the same way `openTicketCount` already is
(`fetchAllRequests().where((r) => !r.isFulfilled).length`).

Auto-resolve: `ItTechnicianConnectedPage._saveStudent`, after a
successful `StudentsRepository.update(...)` call where `form.rfidNo`
is non-empty, calls `RfidRequestsRepository.markFulfilled(editing.id)`.
Only wired for the edit path (`editing != null`) — a brand-new student
created with an RFID number already filled in was never the subject of
a pending request in the first place, so there's nothing to resolve.

## Testing

Signature-guard tests (established pattern) for
`RfidRequestsRepository.notifyRfidMissing`/`fetchMyRequests`/
`fetchAllRequests`/`markFulfilled`. No test for the RPC's SQL itself
(this codebase doesn't test SQL directly — `enroll_section_students`
and `report_technical_issue` don't have SQL-level tests either, only
the Dart-side signature guards).

## Migration / rollout order

1. `supabase/add_rfid_assignment_requests_schema.sql` — shown to the
   user for manual approval, never auto-run (this repo's established
   convention). Everything else compiles and tests against a fake
   Supabase URL without the migration having run yet; only live usage
   of Submit & Notify / the RFID Requests tab is blocked until it has.
2. `RfidRequestsRepository` + its signature-guard tests.
3. Registrar side wiring (real submit, real log).
4. IT Technician side wiring (new tab, Overview stat, auto-resolve
   hook) — independent of step 3's UI details, only depends on step 2.
