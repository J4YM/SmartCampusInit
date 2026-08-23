# IT Technician Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current RFID Management Dashboard (a single cluttered page reachable only from the Admin Hub) with a full IT Technician staff role and dashboard — same RFID/student/reader capabilities, reorganized into an Overview / Student Records / Reader Devices / Technical Issues tabbed shell matching the rest of the app's dashboards, plus a technical-issue ticketing system fed by Teacher and Admin.

**Architecture:** A new `AppRole.itTechnician` role routes to a new tabbed dashboard (`ItTechnicianDashboardPage` in `packages/rfid_management_module`, wired by `lib/ui/it_technician_connected_page.dart`) built on the same `dashboard_layout` header/tab/bottom-nav primitives every other dashboard uses. A new `technical_issue_reports`/`technical_issue_comments` Postgres schema backs a ticket queue, routed through the existing centralized `notifications` table so the bell needs no new plumbing. Teacher and Admin get a shared `ReportTechnicalIssueDialog` (added to `dashboard_layout`) as their reporting entry point.

**Tech Stack:** Flutter (Dart ≥3.3.0), Supabase (Postgres + PostgREST + Realtime), the existing melos-style local-path package workspace (`packages/*`), `google_fonts`, `flutter_test` for widget tests.

**Spec:** `docs/superpowers/specs/2026-08-23-it-technician-dashboard-design.md`

## Global Constraints

- Match the existing visual system exactly: Poppins via `GoogleFonts.poppins`, navy header `0xFF15253F`, card border `0xFFE5E7EB`/`0xFFE2E8F0`, 10px card corner radius, `kDashboardMobileBreakpoint = 800` for the header↔bottom-nav switch, 1440px `DashboardPageWrapper` cap.
- Every new Supabase table gets both a real role-based RLS policy AND a broad `anon` demo policy, matching every existing migration in `supabase/*.sql` (static demo accounts run under the anon key with no JWT) — see `add_notifications_schema.sql` for the exact pattern to copy.
- Client code never assumes a real `auth.uid()` — every RPC that needs to know who's acting takes the actor's id/role as explicit parameters, matching how `_effectiveProfessorId` and `_notifiableUserId` already work around static demo accounts having no real Supabase Auth session.
- `SystemModuleId.rfidManagement`'s enum identifier is NOT renamed (it's referenced in switch statements across `module_access.dart`, `admin_hub_page.dart`, `system_module_id.dart`'s icon switch, etc. — renaming it is unrelated churn). Only its `.title` changes, from `'RFID Management'` to `'IT Technician Dashboard'`.
- Existing access to this module (Admin, Registrar, Security Personnel — per the current `ModuleAccess.canSeeModule` switch) is preserved unchanged; IT Technician is added alongside them, not in place of them.
- No SQL is run against Supabase by an agent. Every task that changes the schema ends with the SQL file written and committed — running it in the Supabase SQL Editor is a manual step for the user, called out explicitly in that task and summarized again at the end of this plan.
- No auto-detection/alerting for offline devices — reader/kiosk offline status is manual-report-only this phase (see spec's Non-goals).

---

### Task 1: Technical-issue schema (SQL migration)

**Files:**
- Create: `supabase/add_it_technician_schema.sql`

**Interfaces:**
- Produces: Postgres enum value `'IT_Technician'` on `app_role`; tables `public.technical_issue_reports`, `public.technical_issue_comments`; enums `public.technical_issue_category`, `public.technical_issue_status`; RPCs `public.report_technical_issue(p_category text, p_description text, p_reporter_id uuid, p_reporter_role text, p_location text default null)` returning the new report row, and `public.add_technical_issue_comment(p_report_id uuid, p_message text, p_author_id uuid, p_author_role text)` returning the new comment row plus enough of the parent report to route a notification.

- [ ] **Step 1: Write the migration file**

```sql
-- IT Technician role + technical-issue ticketing (offline device/reader,
-- offline kiosk, classroom PC problems). See
-- docs/superpowers/specs/2026-08-23-it-technician-dashboard-design.md.
--
-- Run in Supabase SQL Editor, after add_notifications_schema.sql and
-- add_notifications_user_targeting.sql (this reuses that table's dual
-- target_role/target_user_id routing) and add_rfid_reader_network_schema.sql
-- (referenced only in comments below).

-- ---------------------------------------------------------------------------
-- 1. New role value on the shared app_role enum.
-- ---------------------------------------------------------------------------

alter type public.app_role add value if not exists 'IT_Technician';

-- ---------------------------------------------------------------------------
-- 2. Ticket tables.
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.technical_issue_category as enum (
    'offline_device', 'offline_kiosk', 'classroom_pc', 'other'
  );
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.technical_issue_status as enum (
    'open', 'in_progress', 'resolved'
  );
exception
  when duplicate_object then null;
end $$;

create table if not exists public.technical_issue_reports (
  id uuid primary key default gen_random_uuid(),
  category public.technical_issue_category not null,
  description text not null,
  location text,
  reported_by uuid not null references public.profiles(id),
  -- Denormalized so a resolved ticket still shows "reported by a Teacher"
  -- even if that profile is later deleted — matches the `app_role` db
  -- value convention (see lib/auth/app_role.dart's appRoleToDbValue).
  reported_by_role text not null,
  status public.technical_issue_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id)
);

create index if not exists technical_issue_reports_status_idx
  on public.technical_issue_reports (status, created_at desc);

alter table public.technical_issue_reports enable row level security;

drop policy if exists "technical_issue_reports_insert" on public.technical_issue_reports;
create policy "technical_issue_reports_insert"
  on public.technical_issue_reports
  for insert
  to authenticated
  with check (current_user_role() in ('Teacher'::app_role, 'Admin'::app_role));

-- IT Technician + Admin see every ticket; a reporter sees their own.
drop policy if exists "technical_issue_reports_select" on public.technical_issue_reports;
create policy "technical_issue_reports_select"
  on public.technical_issue_reports
  for select
  to authenticated
  using (
    current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
    or auth.uid() = reported_by
  );

drop policy if exists "technical_issue_reports_update" on public.technical_issue_reports;
create policy "technical_issue_reports_update"
  on public.technical_issue_reports
  for update
  to authenticated
  using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role))
  with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

-- Demo-mode anon access — same tradeoff as every other table's anon policy
-- in this project (static demo accounts have no JWT). Tighten before
-- production.
drop policy if exists "technical_issue_reports_anon_all" on public.technical_issue_reports;
create policy "technical_issue_reports_anon_all"
  on public.technical_issue_reports
  for all
  to anon
  using (true)
  with check (true);

create table if not exists public.technical_issue_comments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.technical_issue_reports(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  author_role text not null,
  message text not null,
  created_at timestamptz not null default now()
);

create index if not exists technical_issue_comments_report_idx
  on public.technical_issue_comments (report_id, created_at);

alter table public.technical_issue_comments enable row level security;

drop policy if exists "technical_issue_comments_insert" on public.technical_issue_comments;
create policy "technical_issue_comments_insert"
  on public.technical_issue_comments
  for insert
  to authenticated
  with check (
    current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
    or auth.uid() = (
      select reported_by from public.technical_issue_reports where id = report_id
    )
  );

drop policy if exists "technical_issue_comments_select" on public.technical_issue_comments;
create policy "technical_issue_comments_select"
  on public.technical_issue_comments
  for select
  to authenticated
  using (
    current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
    or auth.uid() = (
      select reported_by from public.technical_issue_reports where id = report_id
    )
  );

drop policy if exists "technical_issue_comments_anon_all" on public.technical_issue_comments;
create policy "technical_issue_comments_anon_all"
  on public.technical_issue_comments
  for all
  to anon
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- 3. RPCs. Both take the actor's id/role as explicit parameters rather than
--    relying on auth.uid()/current_user_role() — the static demo accounts
--    (lib/auth/static_demo_accounts.dart) never hold a real Supabase Auth
--    session, the same reason record_rfid_tap and every *_id column in this
--    project's demo-friendly RPCs work this way.
-- ---------------------------------------------------------------------------

create or replace function public.report_technical_issue(
  p_category public.technical_issue_category,
  p_description text,
  p_reporter_id uuid,
  p_reporter_role text,
  p_location text default null
)
returns public.technical_issue_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.technical_issue_reports;
begin
  insert into public.technical_issue_reports (
    category, description, location, reported_by, reported_by_role
  )
  values (
    p_category, p_description, p_location, p_reporter_id, p_reporter_role
  )
  returning * into v_report;

  insert into public.notifications (target_role, title, message)
  values (
    'IT_Technician'::app_role,
    'New technical issue reported',
    p_description
  );

  return v_report;
end;
$$;

revoke all on function public.report_technical_issue(
  public.technical_issue_category, text, uuid, text, text
) from public;
grant execute on function public.report_technical_issue(
  public.technical_issue_category, text, uuid, text, text
) to anon, authenticated;

create or replace function public.add_technical_issue_comment(
  p_report_id uuid,
  p_message text,
  p_author_id uuid,
  p_author_role text
)
returns public.technical_issue_comments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comment public.technical_issue_comments;
  v_reporter_id uuid;
begin
  insert into public.technical_issue_comments (
    report_id, author_id, author_role, message
  )
  values (
    p_report_id, p_author_id, p_author_role, p_message
  )
  returning * into v_comment;

  select reported_by into v_reporter_id
    from public.technical_issue_reports
    where id = p_report_id;

  -- IT Technician/Admin replying routes straight back to the original
  -- reporter; the reporter replying broadcasts to IT Technician again.
  if p_author_role in ('IT_Technician', 'Admin') then
    insert into public.notifications (target_role, title, message, user_id)
    values (
      'Teacher'::app_role,
      'Update on your technical issue report',
      p_message,
      v_reporter_id
    );
  else
    insert into public.notifications (target_role, title, message)
    values (
      'IT_Technician'::app_role,
      'New reply on a technical issue report',
      p_message
    );
  end if;

  return v_comment;
end;
$$;

revoke all on function public.add_technical_issue_comment(
  uuid, text, uuid, text
) from public;
grant execute on function public.add_technical_issue_comment(
  uuid, text, uuid, text
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Realtime — matches add_notifications_schema.sql's pattern so a future
--    ticket-list live-refresh can subscribe the same way the bell already
--    does. Idempotent.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'technical_issue_reports'
  ) then
    alter publication supabase_realtime add table public.technical_issue_reports;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'technical_issue_comments'
  ) then
    alter publication supabase_realtime add table public.technical_issue_comments;
  end if;
end $$;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/add_it_technician_schema.sql
git commit -m "Add IT Technician role and technical-issue ticket schema"
```

> **Manual step (flagged again in the final summary):** this file is not run automatically. Open it, review it, and run it in the Supabase SQL Editor before Task 10's connected page can work end-to-end.

---

### Task 2: Role, module access, and staff-assignment wiring

**Files:**
- Modify: `lib/auth/app_role.dart`
- Modify: `lib/modules/module_access.dart`
- Modify: `lib/modules/system_module_id.dart`
- Modify: `lib/auth/static_demo_accounts.dart`
- Modify: `packages/admin_dashboard/lib/pages/staff_accounts/staff_accounts_page.dart`
- Modify: `lib/ui/admin/staff_role_mapping.dart`
- Test: `test/app_role_it_technician_test.dart`

**Interfaces:**
- Produces: `AppRole.itTechnician`; `appRoleToDbValue(AppRole.itTechnician) == 'IT_Technician'`; `ModuleAccess.canSeeModule(AppRole.itTechnician, SystemModuleId.rfidManagement) == true`; `SystemModuleId.rfidManagement.title == 'IT Technician Dashboard'`.

- [ ] **Step 1: Add the role to `AppRole`**

In `lib/auth/app_role.dart`:

```dart
enum AppRole {
  student,
  parent,
  teacher,
  securityPersonnel,
  guidanceCounselor,
  disciplineOfficer,
  registrar,
  administrator,
  itTechnician,
}
```

Add to `appRoleFromDbValue`'s switch:

```dart
    case 'IT_Technician':
      return AppRole.itTechnician;
```

Add to `appRoleToDbValue`'s switch:

```dart
    case AppRole.itTechnician:
      return 'IT_Technician';
```

Add to `staffAssignableRoles`:

```dart
const staffAssignableRoles = <AppRole>[
  AppRole.teacher,
  AppRole.registrar,
  AppRole.disciplineOfficer,
  AppRole.guidanceCounselor,
  AppRole.securityPersonnel,
  AppRole.administrator,
  AppRole.itTechnician,
];
```

Add to `AppRoleLabel.displayName`'s switch:

```dart
      case AppRole.itTechnician:
        return 'IT Technician';
```

- [ ] **Step 2: Update module access + module title**

In `lib/modules/module_access.dart`, change the `rfidManagement` case:

```dart
      case SystemModuleId.rfidManagement:
        return {
          AppRole.administrator,
          AppRole.registrar,
          AppRole.securityPersonnel,
          AppRole.itTechnician,
        }.contains(role);
```

In `lib/modules/system_module_id.dart`, change the title:

```dart
      case SystemModuleId.rfidManagement:
        return 'IT Technician Dashboard';
```

- [ ] **Step 3: Add a demo account**

In `lib/auth/static_demo_accounts.dart`, add to `_records` (after `'security.demo'`, before `'student.demo'`):

```dart
    'ittech.demo': _DemoRecord(
      password: 'ITTech2026!',
      user: AppUser(
        id: 'u_ittech',
        displayName: 'IT Technician',
        role: AppRole.itTechnician,
        username: 'ittech.demo',
      ),
    ),
```

Add to `demoAccountHelpText()`'s `lines` list (after the `security.demo` line):

```dart
      '  ittech.demo / ITTech2026!  → IT Technician Dashboard',
```

- [ ] **Step 4: Add the staff-facing role**

In `packages/admin_dashboard/lib/pages/staff_accounts/staff_accounts_page.dart`, add to the `StaffRole` enum:

```dart
enum StaffRole {
  systemAdmin,
  disciplineOfficer,
  guidanceCounselor,
  security,
  teacher,
  registrar,
  itTechnician;
```

Add to its `label` switch:

```dart
      case StaffRole.itTechnician:
        return 'IT Technician';
```

Add to its `colors` switch (a distinct color from the other six):

```dart
      case StaffRole.itTechnician:
        return (const Color(0xFFCCFBF1), const Color(0xFF0F766E));
```

- [ ] **Step 5: Wire the two-way mapping**

In `lib/ui/admin/staff_role_mapping.dart`, add to `staffRoleToAppRole`:

```dart
    case StaffRole.itTechnician:
      return AppRole.itTechnician;
```

Add to `appRoleToStaffRole`:

```dart
    case AppRole.itTechnician:
      return StaffRole.itTechnician;
```

- [ ] **Step 6: Write the test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/modules/module_access.dart';
import 'package:capstone_dashboard/modules/system_module_id.dart';

void main() {
  test('IT Technician role round-trips through the db-value mapping', () {
    expect(appRoleToDbValue(AppRole.itTechnician), 'IT_Technician');
    expect(appRoleFromDbValue('IT_Technician'), AppRole.itTechnician);
  });

  test('IT Technician can see the module; existing roles keep access', () {
    expect(
      ModuleAccess.canSeeModule(AppRole.itTechnician, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.administrator, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.registrar, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.securityPersonnel, SystemModuleId.rfidManagement),
      isTrue,
    );
    expect(
      ModuleAccess.canSeeModule(AppRole.teacher, SystemModuleId.rfidManagement),
      isFalse,
    );
  });

  test('The module title reflects the new dashboard name', () {
    expect(SystemModuleId.rfidManagement.title, 'IT Technician Dashboard');
  });
}
```

> The root `pubspec.yaml`'s `name:` is `capstone_dashboard` — confirmed by reading it directly, so the `package:capstone_dashboard/...` imports above are correct as written (double-check `test/widget_test.dart` still agrees before running, in case it changes later).

- [ ] **Step 7: Run the test**

Run: `flutter test test/app_role_it_technician_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 8: Commit**

```bash
git add lib/auth/app_role.dart lib/modules/module_access.dart lib/modules/system_module_id.dart lib/auth/static_demo_accounts.dart packages/admin_dashboard/lib/pages/staff_accounts/staff_accounts_page.dart lib/ui/admin/staff_role_mapping.dart test/app_role_it_technician_test.dart
git commit -m "Add IT Technician role, module access, and staff assignment wiring"
```

---

### Task 3: Extend `StudentsRepository.fetchPage` for the new filters

**Files:**
- Modify: `lib/data/students_repository.dart:91-120`
- Test: `test/students_repository_fetch_page_test.dart`

**Interfaces:**
- Consumes: nothing new (extends the existing `StudentsRepository` class).
- Produces: `StudentsRepository.fetchPage({required int page, int pageSize = 25, String? course, int? yearLevel, String? sectionId, String? studentNumberQuery})` — same return shape as today, `({List<StudentRecord> items, int totalCount})`.

- [ ] **Step 1: Extend the method**

Replace the existing `fetchPage` in `lib/data/students_repository.dart` (lines 91-120):

```dart
  /// One page of students (1-indexed) plus the total row count matching the
  /// given filters — used by the Student Directory and IT Technician
  /// Student Records tab so neither ever has to load the whole table
  /// (potentially hundreds of rows) just to show one screenful.
  ///
  /// [studentNumberQuery] is a server-side `ilike` prefix match on
  /// `student_number` only — matching [searchByStudentNumberPrefix]'s own
  /// documented caution, full-name search against the embedded `profiles`
  /// table needs PostgREST's inner-join hint syntax to apply correctly,
  /// which isn't worth risking a silently-wrong filter for here.
  Future<({List<StudentRecord> items, int totalCount})> fetchPage({
    required int page,
    int pageSize = 25,
    String? course,
    int? yearLevel,
    String? sectionId,
    String? studentNumberQuery,
  }) async {
    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;

    var query = _client.from('students').select(_selectEmbed);
    if (course != null && course.isNotEmpty) {
      query = query.eq('course', course);
    }
    if (yearLevel != null) {
      query = query.eq('year_level', yearLevel);
    }
    if (sectionId != null && sectionId.isNotEmpty) {
      query = query.eq('section_id', sectionId);
    }
    if (studentNumberQuery != null && studentNumberQuery.trim().isNotEmpty) {
      query = query.ilike('student_number', '${studentNumberQuery.trim()}%');
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final rows = response.data as List<dynamic>;
    return (
      items: rows
          .map((e) => StudentRecord.fromSupabase(e as Map<String, dynamic>))
          .toList(),
      totalCount: response.count,
    );
  }
```

- [ ] **Step 2: Write the test**

Full integration coverage (that the filters actually narrow results) needs a live/test Supabase project, which this codebase doesn't wire up for unit tests elsewhere either (no existing `*_repository_test.dart` was found), and actually *calling* `fetchPage` here would fire a real unawaited network request against a fake URL, which `flutter_test`'s guarded zone would report as a failure even though nothing in the test awaited it. So this test stays at the compile-time level only: tearing off the method with its full new signature proves it compiles with every new named parameter, without ever invoking it.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_dashboard/data/students_repository.dart';
import 'package:capstone_dashboard/models/student_record.dart';

void main() {
  test('fetchPage compiles with the new section/search filter parameters', () {
    final repo = StudentsRepository(SupabaseClient('https://example.invalid', 'anon-key'));

    // A tear-off with this exact signature only compiles if fetchPage still
    // accepts every one of these named parameters — a guard against a
    // future accidental signature break, without ever calling the method
    // (which would fire a real network request against a fake URL).
    final Future<({List<StudentRecord> items, int totalCount})> Function({
      required int page,
      int pageSize,
      String? course,
      int? yearLevel,
      String? sectionId,
      String? studentNumberQuery,
    }) fetchPage = repo.fetchPage;

    expect(fetchPage, isNotNull);
  });
}
```

> Uses the same `capstone_dashboard` import prefix confirmed in Task 2.

- [ ] **Step 3: Run the test**

Run: `flutter test test/students_repository_fetch_page_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/data/students_repository.dart test/students_repository_fetch_page_test.dart
git commit -m "Add section and student-number filters to StudentsRepository.fetchPage"
```

---

### Task 4: `TechnicalIssuesRepository`

**Files:**
- Create: `lib/data/technical_issues_repository.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `TechnicalIssueCategory` enum (`offlineDevice, offlineKiosk, classroomPc, other`), `TechnicalIssueStatus` enum (`open, inProgress, resolved`), `TechnicalIssueReport` (id, category, description, location, reportedBy, reportedByRole, status, createdAt, resolvedAt, resolvedBy), `TechnicalIssueComment` (id, reportId, authorId, authorRole, message, createdAt), `TechnicalIssuesRepository` with methods `fetchReports({TechnicalIssueStatus? status})`, `fetchComments(String reportId)`, `report({required TechnicalIssueCategory category, required String description, required String reporterId, required String reporterRole, String? location})`, `addComment({required String reportId, required String message, required String authorId, required String authorRole})`, `updateStatus({required String id, required TechnicalIssueStatus status, String? resolvedBy})`.

- [ ] **Step 1: Write the repository**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class TechnicalIssuesRepositoryException implements Exception {
  TechnicalIssuesRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum TechnicalIssueCategory { offlineDevice, offlineKiosk, classroomPc, other }

extension TechnicalIssueCategoryDb on TechnicalIssueCategory {
  String get dbValue {
    switch (this) {
      case TechnicalIssueCategory.offlineDevice:
        return 'offline_device';
      case TechnicalIssueCategory.offlineKiosk:
        return 'offline_kiosk';
      case TechnicalIssueCategory.classroomPc:
        return 'classroom_pc';
      case TechnicalIssueCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case TechnicalIssueCategory.offlineDevice:
        return 'Offline device/reader';
      case TechnicalIssueCategory.offlineKiosk:
        return 'Offline kiosk';
      case TechnicalIssueCategory.classroomPc:
        return 'Classroom PC problem';
      case TechnicalIssueCategory.other:
        return 'Other';
    }
  }
}

TechnicalIssueCategory technicalIssueCategoryFromDb(String value) {
  switch (value) {
    case 'offline_device':
      return TechnicalIssueCategory.offlineDevice;
    case 'offline_kiosk':
      return TechnicalIssueCategory.offlineKiosk;
    case 'classroom_pc':
      return TechnicalIssueCategory.classroomPc;
    default:
      return TechnicalIssueCategory.other;
  }
}

enum TechnicalIssueStatus { open, inProgress, resolved }

extension TechnicalIssueStatusDb on TechnicalIssueStatus {
  String get dbValue {
    switch (this) {
      case TechnicalIssueStatus.open:
        return 'open';
      case TechnicalIssueStatus.inProgress:
        return 'in_progress';
      case TechnicalIssueStatus.resolved:
        return 'resolved';
    }
  }

  String get label {
    switch (this) {
      case TechnicalIssueStatus.open:
        return 'Open';
      case TechnicalIssueStatus.inProgress:
        return 'In Progress';
      case TechnicalIssueStatus.resolved:
        return 'Resolved';
    }
  }
}

TechnicalIssueStatus technicalIssueStatusFromDb(String value) {
  switch (value) {
    case 'in_progress':
      return TechnicalIssueStatus.inProgress;
    case 'resolved':
      return TechnicalIssueStatus.resolved;
    default:
      return TechnicalIssueStatus.open;
  }
}

class TechnicalIssueReport {
  const TechnicalIssueReport({
    required this.id,
    required this.category,
    required this.description,
    required this.location,
    required this.reportedBy,
    required this.reportedByRole,
    required this.status,
    required this.createdAt,
    required this.resolvedAt,
    required this.resolvedBy,
  });

  final String id;
  final TechnicalIssueCategory category;
  final String description;
  final String? location;
  final String reportedBy;
  final String reportedByRole;
  final TechnicalIssueStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  factory TechnicalIssueReport.fromSupabase(Map<String, dynamic> row) {
    return TechnicalIssueReport(
      id: row['id'] as String,
      category: technicalIssueCategoryFromDb(row['category'] as String),
      description: row['description'] as String,
      location: row['location'] as String?,
      reportedBy: row['reported_by'] as String,
      reportedByRole: row['reported_by_role'] as String,
      status: technicalIssueStatusFromDb(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      resolvedAt: row['resolved_at'] == null
          ? null
          : DateTime.parse(row['resolved_at'] as String),
      resolvedBy: row['resolved_by'] as String?,
    );
  }
}

class TechnicalIssueComment {
  const TechnicalIssueComment({
    required this.id,
    required this.reportId,
    required this.authorId,
    required this.authorRole,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String reportId;
  final String authorId;
  final String authorRole;
  final String message;
  final DateTime createdAt;

  factory TechnicalIssueComment.fromSupabase(Map<String, dynamic> row) {
    return TechnicalIssueComment(
      id: row['id'] as String,
      reportId: row['report_id'] as String,
      authorId: row['author_id'] as String,
      authorRole: row['author_role'] as String,
      message: row['message'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

/// Reads/writes `technical_issue_reports` and `technical_issue_comments` —
/// see supabase/add_it_technician_schema.sql. Reporting and commenting go
/// through `report_technical_issue`/`add_technical_issue_comment` (which
/// also insert the routing `notifications` row in the same transaction);
/// status changes are a plain update, matching how
/// [RfidReaderRepository.setReaderActive] handles simple state changes.
class TechnicalIssuesRepository {
  TechnicalIssuesRepository(this._client);

  final SupabaseClient _client;

  static const _reportSelect =
      'id, category, description, location, reported_by, reported_by_role, status, created_at, resolved_at, resolved_by';

  Future<List<TechnicalIssueReport>> fetchReports({
    TechnicalIssueStatus? status,
  }) async {
    var query = _client.from('technical_issue_reports').select(_reportSelect);
    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => TechnicalIssueReport.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TechnicalIssueComment>> fetchComments(String reportId) async {
    final rows = await _client
        .from('technical_issue_comments')
        .select('id, report_id, author_id, author_role, message, created_at')
        .eq('report_id', reportId)
        .order('created_at');
    return (rows as List<dynamic>)
        .map((e) => TechnicalIssueComment.fromSupabase(e as Map<String, dynamic>))
        .toList();
  }

  Future<TechnicalIssueReport> report({
    required TechnicalIssueCategory category,
    required String description,
    required String reporterId,
    required String reporterRole,
    String? location,
  }) async {
    try {
      final rows = await _client.rpc('report_technical_issue', params: {
        'p_category': category.dbValue,
        'p_description': description,
        'p_reporter_id': reporterId,
        'p_reporter_role': reporterRole,
        if (location != null && location.isNotEmpty) 'p_location': location,
      });
      final row = rows is List ? rows.first as Map<String, dynamic> : rows as Map<String, dynamic>;
      return TechnicalIssueReport.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw TechnicalIssuesRepositoryException(e.message);
    }
  }

  Future<TechnicalIssueComment> addComment({
    required String reportId,
    required String message,
    required String authorId,
    required String authorRole,
  }) async {
    try {
      final rows = await _client.rpc('add_technical_issue_comment', params: {
        'p_report_id': reportId,
        'p_message': message,
        'p_author_id': authorId,
        'p_author_role': authorRole,
      });
      final row = rows is List ? rows.first as Map<String, dynamic> : rows as Map<String, dynamic>;
      return TechnicalIssueComment.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw TechnicalIssuesRepositoryException(e.message);
    }
  }

  Future<void> updateStatus({
    required String id,
    required TechnicalIssueStatus status,
    String? resolvedBy,
  }) async {
    try {
      await _client.from('technical_issue_reports').update({
        'status': status.dbValue,
        'resolved_at': status == TechnicalIssueStatus.resolved
            ? DateTime.now().toIso8601String()
            : null,
        'resolved_by': status == TechnicalIssueStatus.resolved ? resolvedBy : null,
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw TechnicalIssuesRepositoryException(e.message);
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/technical_issues_repository.dart
git commit -m "Add TechnicalIssuesRepository for the ticket queue"
```

---

### Task 5: `ReportTechnicalIssueDialog` shared widget

**Files:**
- Create: `packages/dashboard_layout/lib/src/report_technical_issue_dialog.dart`
- Modify: `packages/dashboard_layout/lib/dashboard_layout.dart`

**Interfaces:**
- Produces: `ReportTechnicalIssueCategory` enum (package-local, presentation-only — mirrors `TechnicalIssueCategory`'s four values so this package stays backend-agnostic, same reasoning as `RfidReaderRowModel`), `ReportTechnicalIssueDialog` widget with constructor `{required Future<void> Function({required ReportTechnicalIssueCategory category, required String description, String? location}) onSubmit}`, and a static helper `Future<void> showReportTechnicalIssueDialog(BuildContext context, {required Future<void> Function(...) onSubmit})`.

- [ ] **Step 1: Write the widget**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Package-local, presentation-only category list — mirrors the four
/// `technical_issue_category` Postgres enum values (see
/// supabase/add_it_technician_schema.sql) without this package depending on
/// Supabase, same reasoning as `rfid_management_module`'s
/// `RfidReaderRowModel`. Host apps map this to their own db-backed enum.
enum ReportTechnicalIssueCategory { offlineDevice, offlineKiosk, classroomPc, other }

extension ReportTechnicalIssueCategoryLabel on ReportTechnicalIssueCategory {
  String get label {
    switch (this) {
      case ReportTechnicalIssueCategory.offlineDevice:
        return 'Offline device/reader';
      case ReportTechnicalIssueCategory.offlineKiosk:
        return 'Offline kiosk';
      case ReportTechnicalIssueCategory.classroomPc:
        return 'Classroom PC problem';
      case ReportTechnicalIssueCategory.other:
        return 'Other';
    }
  }
}

/// Opens [ReportTechnicalIssueDialog] as a Material dialog. The shared entry
/// point Teacher's and Admin's dashboards both call, so the reporting form
/// is pixel-identical wherever it's opened from.
Future<void> showReportTechnicalIssueDialog(
  BuildContext context, {
  required Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) onSubmit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ReportTechnicalIssueDialog(onSubmit: onSubmit),
  );
}

/// Reports a technical issue (offline device/reader, offline kiosk,
/// classroom PC problem, or other) to IT Technician. Submitted via
/// [onSubmit] — the host app wires this to
/// `TechnicalIssuesRepository.report`.
class ReportTechnicalIssueDialog extends StatefulWidget {
  const ReportTechnicalIssueDialog({super.key, required this.onSubmit});

  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) onSubmit;

  @override
  State<ReportTechnicalIssueDialog> createState() =>
      _ReportTechnicalIssueDialogState();
}

class _ReportTechnicalIssueDialogState
    extends State<ReportTechnicalIssueDialog> {
  ReportTechnicalIssueCategory _category =
      ReportTechnicalIssueCategory.offlineDevice;
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Describe the problem before submitting.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        category: _category,
        description: description,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Preserves the entered description/location so nothing typed is
        // lost — the dialog stays open on failure.
        _error = 'Could not submit: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Report a Technical Issue',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<ReportTechnicalIssueCategory>(
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: ReportTechnicalIssueCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                hintText: 'e.g. Room 301, Floor 2 hallway',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe the problem',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Export it**

In `packages/dashboard_layout/lib/dashboard_layout.dart`, add:

```dart
export 'src/report_technical_issue_dialog.dart';
```

- [ ] **Step 3: Commit**

```bash
git add packages/dashboard_layout/lib/src/report_technical_issue_dialog.dart packages/dashboard_layout/lib/dashboard_layout.dart
git commit -m "Add shared ReportTechnicalIssueDialog to dashboard_layout"
```

---

### Task 6: `rfid_management_module` package setup (dependencies + exports)

**Files:**
- Modify: `packages/rfid_management_module/pubspec.yaml`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`

**Interfaces:**
- Produces: `rfid_management_module` gains `dashboard_layout` and `discipline_officer_module` as path dependencies (needed by Task 7's shell for `AppHeaderNavBar`, `AppBottomNavBar`, `DashboardPageWrapper`, `HeaderIconButton`, `ProfileAvatarButton`, `MobileMetricGrid`, `ResponsiveX`, `mouseDraggableScrollBehavior`, `NotificationItemModel`, `NotificationsPopover`, `EmailPopover`, `AccountProfileMenu`, `LogoutConfirmationDialog`, `ProfileScreen`, `showHeaderPopover`).

- [ ] **Step 1: Add the dependencies**

In `packages/rfid_management_module/pubspec.yaml`, change the `dependencies:` block to:

```yaml
dependencies:
  flutter:
    sdk: flutter

  cupertino_icons: ^1.0.8
  google_fonts: ^6.2.1
  dashboard_layout:
    path: ../dashboard_layout
  discipline_officer_module:
    path: ../discipline_officer_module
```

- [ ] **Step 2: Resolve dependencies**

Run: `cd packages/rfid_management_module && flutter pub get`
Expected: exits 0, `pubspec.lock` updated.

- [ ] **Step 3: Commit**

```bash
git add packages/rfid_management_module/pubspec.yaml packages/rfid_management_module/pubspec.lock
git commit -m "Add dashboard_layout and discipline_officer_module deps to rfid_management_module"
```

(Task 7 updates the package's export file once the new page files exist — kept there so the export list and the files it points to land in the same commit.)

---

### Task 7: IT Technician dashboard shell (Overview tab + navigation)

**Files:**
- Create: `packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`
- Test: `packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart`

**Interfaces:**
- Consumes: `AppHeaderNavBar`, `AppBottomNavBar`, `DashboardPageWrapper`, `HeaderIconButton`, `ProfileAvatarButton`, `MobileMetricGrid`, `ResponsiveX` (`context.isMobileWidth`), `mouseDraggableScrollBehavior` from `dashboard_layout`; `NotificationItemModel`, `NotificationsPopover`, `EmailPopover`, `AccountProfileMenu`, `LogoutConfirmationDialog`, `ProfileScreen`, `showHeaderPopover` from `discipline_officer_module` (all `show`-imported, matching `professor_dashboard_page.dart`'s import).
- Produces: `ItTechnicianDashboardTab` enum (`overview, studentRecords, readerDevices, technicalIssues`); `ItTechnicianDashboardPage` widget with constructor `{String technicianName = 'IT Technician', VoidCallback? onReturnToHub, VoidCallback? onSignOut, ItTechnicianOverviewStats? initialStats, List<NotificationItemModel>? initialNotifications, Future<void> Function()? onMarkNotificationsRead, required Widget Function(BuildContext) studentRecordsTabBuilder, required Widget Function(BuildContext) readerDevicesTabBuilder, required Widget Function(BuildContext) technicalIssuesTabBuilder}` — the three non-Overview tabs are supplied as builders from Task 8/9 rather than built inline, keeping this file focused on the shell/nav/header exactly as the spec's "one clear responsibility per file" calls for.
- Produces: `ItTechnicianOverviewStats` model (`{required int totalStudents, required int totalReaders, required int onlineReaders, required int openTicketCount}`).

- [ ] **Step 1: Write the shell**

```dart
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        EmailPopover,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ItTechnicianDashboardTab { overview, studentRecords, readerDevices, technicalIssues }

abstract final class ItTechnicianColors {
  static const navyBlue = Color(0xFF15253F);
  static const azureBlue = Color(0xFF2563EB);
  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE5E7EB);
  static const rowText = Color(0xFF111827);
  static const mutedText = Color(0xFF6B7280);
}

class ItTechnicianOverviewStats {
  const ItTechnicianOverviewStats({
    required this.totalStudents,
    required this.totalReaders,
    required this.onlineReaders,
    required this.openTicketCount,
  });

  final int totalStudents;
  final int totalReaders;
  final int onlineReaders;
  final int openTicketCount;
}

class ItTechnicianDashboardPage extends StatefulWidget {
  const ItTechnicianDashboardPage({
    super.key,
    this.technicianName = 'IT Technician',
    this.onReturnToHub,
    this.onSignOut,
    this.initialStats,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    required this.studentRecordsTabBuilder,
    required this.readerDevicesTabBuilder,
    required this.technicalIssuesTabBuilder,
    this.onReportIssue,
  });

  final String technicianName;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;
  final ItTechnicianOverviewStats? initialStats;
  final List<NotificationItemModel>? initialNotifications;
  final Future<void> Function()? onMarkNotificationsRead;

  final WidgetBuilder studentRecordsTabBuilder;
  final WidgetBuilder readerDevicesTabBuilder;
  final WidgetBuilder technicalIssuesTabBuilder;

  /// Unused by this shell directly (IT Technician doesn't file reports on
  /// itself) — kept for constructor symmetry with the Teacher/Admin entry
  /// points added in later tasks; always null from this page today.
  final VoidCallback? onReportIssue;

  @override
  State<ItTechnicianDashboardPage> createState() => _ItTechnicianDashboardPageState();
}

class _ItTechnicianDashboardPageState extends State<ItTechnicianDashboardPage> {
  ItTechnicianDashboardTab _activeTab = ItTechnicianDashboardTab.overview;
  late List<NotificationItemModel> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = List.of(widget.initialNotifications ?? const []);
  }

  @override
  void didUpdateWidget(covariant ItTechnicianDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fresh = widget.initialNotifications;
    if (fresh != null && !identical(fresh, oldWidget.initialNotifications)) {
      setState(() => _notifications = List.of(fresh));
    }
  }

  Future<void> _markNotificationsRead() async {
    if (_notifications.every((n) => n.isRead)) return;
    setState(() {
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  void _showNotificationsMenu(BuildContext context) {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: _notifications,
          accentColor: ItTechnicianColors.azureBlue,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            _markNotificationsRead();
          },
        );
      },
    );
  }

  void _showEmailMenu(BuildContext context) {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return EmailPopover(onViewAll: () => Navigator.of(popoverContext).pop());
      },
    );
  }

  void _openProfile(BuildContext context) {
    showHeaderPopover(
      context: context,
      cardWidth: 260,
      anchorAboveBottomNav: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          onViewProfile: () {
            Navigator.of(popoverContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          onToggleDarkMode: () {},
          onLogout: () {
            Navigator.of(popoverContext).pop();
            _confirmLogout(context);
          },
        );
      },
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobileWidth;

    final header = AppHeaderNavBar(
      title: 'IT Technician Dashboard',
      subtitle: 'Devices, RFID, and technical support',
      backgroundColor: ItTechnicianColors.navyBlue,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onReturnToHub != null) ...[
            HeaderIconButton(icon: Icons.arrow_back_rounded, onTap: widget.onReturnToHub!),
            const SizedBox(width: 12),
          ],
          Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              'STI',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 12 : 14,
                fontWeight: FontWeight.w800,
                color: ItTechnicianColors.navyBlue,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (!isMobile) ...[
          HeaderIconButton(icon: Icons.mail_outline_rounded, onTap: () => _showEmailMenu(context)),
          HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            badgeCount: _notifications.where((n) => !n.isRead).length,
            onTap: () => _showNotificationsMenu(context),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.technicianName,
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(width: 15),
              ProfileAvatarButton(onTap: () => _openProfile(context)),
              if (widget.onSignOut != null) ...[
                const SizedBox(width: 10),
                HeaderIconButton(icon: Icons.logout_rounded, onTap: widget.onSignOut!),
              ],
            ],
          ),
        ] else if (widget.onSignOut != null)
          HeaderIconButton(icon: Icons.logout_rounded, onTap: widget.onSignOut!),
      ],
    );

    final pageContent = DashboardPageWrapper(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 5 : 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SubNavBar(
            activeTab: _activeTab,
            onTabSelected: (tab) => setState(() => _activeTab = tab),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildTabContent(context)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: ItTechnicianColors.background,
      bottomNavigationBar: isMobile
          ? AppBottomNavBar(
              onEmailTap: () => _showEmailMenu(context),
              onNotificationTap: () => _showNotificationsMenu(context),
              onProfileTap: () => _openProfile(context),
              notificationBadgeCount: _notifications.where((n) => !n.isRead).length,
            )
          : null,
      body: isMobile
          ? SingleChildScrollView(child: Column(children: [header, pageContent]))
          : Column(children: [header, Expanded(child: pageContent)]),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    switch (_activeTab) {
      case ItTechnicianDashboardTab.overview:
        return _OverviewTab(stats: widget.initialStats);
      case ItTechnicianDashboardTab.studentRecords:
        return widget.studentRecordsTabBuilder(context);
      case ItTechnicianDashboardTab.readerDevices:
        return widget.readerDevicesTabBuilder(context);
      case ItTechnicianDashboardTab.technicalIssues:
        return widget.technicalIssuesTabBuilder(context);
    }
  }
}

class _SubNavBar extends StatelessWidget {
  const _SubNavBar({required this.activeTab, required this.onTabSelected});

  final ItTechnicianDashboardTab activeTab;
  final ValueChanged<ItTechnicianDashboardTab> onTabSelected;

  static const _labels = {
    ItTechnicianDashboardTab.overview: 'Overview',
    ItTechnicianDashboardTab.studentRecords: 'Student Records',
    ItTechnicianDashboardTab.readerDevices: 'Reader Devices',
    ItTechnicianDashboardTab.technicalIssues: 'Technical Issues',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ItTechnicianColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder),
      ),
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in ItTechnicianDashboardTab.values) ...[
                _SubNavItem(
                  label: _labels[tab]!,
                  isActive: activeTab == tab,
                  onTap: () => onTabSelected(tab),
                ),
                if (tab != ItTechnicianDashboardTab.values.last) const SizedBox(width: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: isActive ? ItTechnicianColors.azureBlue : Colors.transparent,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            fontWeight: FontWeight.w600,
            color: isActive ? ItTechnicianColors.azureBlue : ItTechnicianColors.mutedText,
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.stats});

  final ItTechnicianOverviewStats? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats ??
        const ItTechnicianOverviewStats(
          totalStudents: 0,
          totalReaders: 0,
          onlineReaders: 0,
          openTicketCount: 0,
        );

    final cards = [
      _StatCard(label: 'Total Students', value: '${s.totalStudents}', icon: Icons.school_outlined),
      _StatCard(
        label: 'Readers Online',
        value: '${s.onlineReaders}/${s.totalReaders}',
        icon: Icons.sensors,
      ),
      _StatCard(label: 'Open Technical Issues', value: '${s.openTicketCount}', icon: Icons.build_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return SingleChildScrollView(child: MobileMetricGrid(cards: cards));
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 18),
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 124,
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: ItTechnicianColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ItTechnicianColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.mutedText,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: ItTechnicianColors.mutedText),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Export it**

In `packages/rfid_management_module/lib/rfid_management_module.dart`, add:

```dart
export 'ui/it_technician_dashboard_page.dart';
```

(leave the existing three exports in place until Task 11 removes the old page).

- [ ] **Step 3: Write the tab-wiring test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  Widget buildPage() {
    return MaterialApp(
      home: ItTechnicianDashboardPage(
        studentRecordsTabBuilder: (_) => const Center(child: Text('Student Records Content')),
        readerDevicesTabBuilder: (_) => const Center(child: Text('Reader Devices Content')),
        technicalIssuesTabBuilder: (_) => const Center(child: Text('Technical Issues Content')),
      ),
    );
  }

  testWidgets('starts on Overview and switches tabs on tap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage());

    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('Student Records Content'), findsNothing);

    await tester.tap(find.text('Student Records'));
    await tester.pumpAndSettle();
    expect(find.text('Student Records Content'), findsOneWidget);
    expect(find.text('Total Students'), findsNothing);

    await tester.tap(find.text('Reader Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Reader Devices Content'), findsOneWidget);

    await tester.tap(find.text('Technical Issues'));
    await tester.pumpAndSettle();
    expect(find.text('Technical Issues Content'), findsOneWidget);
  });

  testWidgets('switches to bottom nav below the mobile breakpoint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage());

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/rfid_management_module && flutter test test/it_technician_dashboard_tab_wiring_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add packages/rfid_management_module/lib/ui/it_technician_dashboard_page.dart packages/rfid_management_module/lib/rfid_management_module.dart packages/rfid_management_module/test/it_technician_dashboard_tab_wiring_test.dart
git commit -m "Add IT Technician dashboard shell with Overview tab and navigation"
```

---

### Task 8: Student Records tab (filters, pagination, skeleton, danger-zone delete)

**Files:**
- Create: `packages/rfid_management_module/lib/ui/student_records_tab.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`
- Test: `packages/rfid_management_module/test/student_records_tab_test.dart`

**Interfaces:**
- Consumes: `RfidStudentRow`, `RfidRegistrationForm` (from `rfid_student_row.dart`, already in this package).
- Produces: `StudentRecordsTab` widget, constructor:

```dart
StudentRecordsTab({
  required List<RfidStudentRow> students,
  required bool isLoading,
  required bool isBusy,
  required int currentPage,
  required int totalPages,
  required int? totalCount,
  required String selectedCourse,       // 'All Courses' default
  required String selectedYearLevel,    // 'All Years' default
  required String selectedSection,      // 'All Sections' default
  required List<String> sectionOptions, // populated by host once course+year chosen
  required ValueChanged<String> onSearchChanged,
  required ValueChanged<String> onCourseChanged,
  required ValueChanged<String> onYearLevelChanged,
  required ValueChanged<String> onSectionChanged,
  required VoidCallback onPreviousPage,
  required VoidCallback onNextPage,
  required Future<void> Function(RfidRegistrationForm form, RfidStudentRow? editing) onSave,
  required Future<void> Function(RfidStudentRow student) onDelete,
})
```

- [ ] **Step 1: Write the tab**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../rfid_student_row.dart';

abstract final class _RecordsColors {
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const primaryButton = Color(0xFF27426D);
  static const dangerRed = Color(0xFFDC2626);
}

const _courseOptions = [
  'All Courses',
  'BS Business Administration',
  'BS Hospitality Management',
  'BS Information Technology',
  'BS Tourism Management',
];
const _yearLevelOptions = ['All Years', '1st Year', '2nd Year', '3rd Year', '4th Year'];

class StudentRecordsTab extends StatelessWidget {
  const StudentRecordsTab({
    super.key,
    required this.students,
    required this.isLoading,
    required this.isBusy,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.selectedCourse,
    required this.selectedYearLevel,
    required this.selectedSection,
    required this.sectionOptions,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onYearLevelChanged,
    required this.onSectionChanged,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onSave,
    required this.onDelete,
  });

  final List<RfidStudentRow> students;
  final bool isLoading;
  final bool isBusy;
  final int currentPage;
  final int totalPages;
  final int? totalCount;
  final String selectedCourse;
  final String selectedYearLevel;
  final String selectedSection;
  final List<String> sectionOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCourseChanged;
  final ValueChanged<String> onYearLevelChanged;
  final ValueChanged<String> onSectionChanged;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final Future<void> Function(RfidRegistrationForm form, RfidStudentRow? editing) onSave;
  final Future<void> Function(RfidStudentRow student) onDelete;

  void _openRegisterDialog(BuildContext context, {RfidStudentRow? editing}) {
    showDialog<void>(
      context: context,
      builder: (_) => _StudentFormDialog(editing: editing, onSave: onSave),
    );
  }

  void _confirmDelete(BuildContext context, RfidStudentRow student) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: _RecordsColors.dangerRed, size: 32),
        title: Text(
          'Delete ${student.fullName}?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This permanently removes student number ${student.studentNumber} and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _RecordsColors.dangerRed),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onDelete(student);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _RecordsColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _RecordsColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Student Records',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: _RecordsColors.primaryText),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openRegisterDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Register Student'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _YearLevelQuickTabs(selected: selectedYearLevel, onChanged: onYearLevelChanged),
          const SizedBox(height: 12),
          _FilterRow(
            selectedCourse: selectedCourse,
            selectedSection: selectedSection,
            sectionOptions: sectionOptions,
            onSearchChanged: onSearchChanged,
            onCourseChanged: onCourseChanged,
            onSectionChanged: onSectionChanged,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 460,
            child: isLoading && students.isEmpty
                ? const _SkeletonTableBody(rowCount: 8)
                : students.isEmpty
                    ? const Center(child: Text('No students match these filters.'))
                    : _StudentTable(
                        students: students,
                        isBusy: isBusy,
                        onEdit: (s) => _openRegisterDialog(context, editing: s),
                        onDelete: (s) => _confirmDelete(context, s),
                      ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalCount == null
                    ? 'Page $currentPage of $totalPages'
                    : 'Page $currentPage of $totalPages · $totalCount total',
                style: GoogleFonts.poppins(fontSize: 12, color: _RecordsColors.secondaryText),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (isLoading || currentPage <= 1) ? null : onPreviousPage,
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Previous'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: (isLoading || currentPage >= totalPages) ? null : onNextPage,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Next'),
                    iconAlignment: IconAlignment.end,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YearLevelQuickTabs extends StatelessWidget {
  const _YearLevelQuickTabs({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _yearLevelOptions.map((year) {
        final isSelected = year == selected;
        return ChoiceChip(
          label: Text(year),
          selected: isSelected,
          onSelected: (_) => onChanged(year),
        );
      }).toList(),
    );
  }
}

class _FilterRow extends StatefulWidget {
  const _FilterRow({
    required this.selectedCourse,
    required this.selectedSection,
    required this.sectionOptions,
    required this.onSearchChanged,
    required this.onCourseChanged,
    required this.onSectionChanged,
  });

  final String selectedCourse;
  final String selectedSection;
  final List<String> sectionOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCourseChanged;
  final ValueChanged<String> onSectionChanged;

  @override
  State<_FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends State<_FilterRow> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final search = TextField(
          controller: _searchController,
          onChanged: widget.onSearchChanged,
          decoration: const InputDecoration(
            hintText: 'Search by student number...',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        );
        final courseDropdown = DropdownButtonFormField<String>(
          value: widget.selectedCourse,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: _courseOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (value) {
            if (value != null) widget.onCourseChanged(value);
          },
        );
        final sectionOptions = ['All Sections', ...widget.sectionOptions];
        final sectionDropdown = DropdownButtonFormField<String>(
          value: sectionOptions.contains(widget.selectedSection) ? widget.selectedSection : 'All Sections',
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: sectionOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (value) {
            if (value != null) widget.onSectionChanged(value);
          },
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Row(children: [Expanded(child: courseDropdown), const SizedBox(width: 10), Expanded(child: sectionDropdown)]),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 3, child: search),
            const SizedBox(width: 10),
            SizedBox(width: 220, child: courseDropdown),
            const SizedBox(width: 10),
            SizedBox(width: 160, child: sectionDropdown),
          ],
        );
      },
    );
  }
}

class _SkeletonTableBody extends StatefulWidget {
  const _SkeletonTableBody({required this.rowCount});
  final int rowCount;

  @override
  State<_SkeletonTableBody> createState() => _SkeletonTableBodyState();
}

class _SkeletonTableBodyState extends State<_SkeletonTableBody> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final _opacity = Tween<double>(begin: 0.4, end: 0.9).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => ListView.builder(
        itemCount: widget.rowCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0).withOpacity(_opacity.value),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentTable extends StatelessWidget {
  const _StudentTable({required this.students, required this.isBusy, required this.onEdit, required this.onDelete});

  final List<RfidStudentRow> students;
  final bool isBusy;
  final ValueChanged<RfidStudentRow> onEdit;
  final ValueChanged<RfidStudentRow> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('RFID No.')),
                DataColumn(label: Text('Student Number')),
                DataColumn(label: Text('Full Name')),
                DataColumn(label: Text('Course')),
                DataColumn(label: Text('Year Level')),
                DataColumn(label: Text('Section')),
                DataColumn(label: Text('Actions')),
              ],
              rows: students
                  .map(
                    (student) => DataRow(
                      cells: [
                        DataCell(Text(student.rfidNo)),
                        DataCell(Text(student.studentNumber)),
                        DataCell(Text(student.fullName)),
                        DataCell(Text(student.course)),
                        DataCell(Text(student.yearLevel)),
                        DataCell(Text(student.section)),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit student',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => onEdit(student),
                              ),
                              IconButton(
                                tooltip: 'Delete student',
                                icon: const Icon(Icons.delete_outline, color: _RecordsColors.dangerRed),
                                onPressed: isBusy ? null : () => onDelete(student),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({required this.editing, required this.onSave});

  final RfidStudentRow? editing;
  final Future<void> Function(RfidRegistrationForm form, RfidStudentRow? editing) onSave;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  late final _rfidController = TextEditingController(text: widget.editing?.rfidNo ?? '');
  late final _studentNumberController = TextEditingController(text: widget.editing?.studentNumber ?? '');
  late final _firstNameController = TextEditingController(text: widget.editing?.firstName ?? '');
  late final _lastNameController = TextEditingController(text: widget.editing?.lastName ?? '');
  late final _middleInitialController = TextEditingController(text: widget.editing?.middleInitial ?? '');
  late final _sectionController = TextEditingController(text: widget.editing?.section ?? '');
  late final _guardianController = TextEditingController(text: widget.editing?.guardianName ?? '');
  String? _course;
  String? _yearLevel;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _course = widget.editing?.course;
    _yearLevel = widget.editing?.yearLevel;
  }

  @override
  void dispose() {
    _rfidController.dispose();
    _studentNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _sectionController.dispose();
    _guardianController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final course = _course;
    final yearLevel = _yearLevel;
    if (_rfidController.text.trim().isEmpty ||
        _studentNumberController.text.trim().isEmpty ||
        _firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _sectionController.text.trim().isEmpty ||
        course == null ||
        yearLevel == null) {
      setState(() => _error = 'Please complete all required fields.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        RfidRegistrationForm(
          rfidNo: _rfidController.text.trim(),
          studentNumber: _studentNumberController.text.trim(),
          firstName: _firstNameController.text.trim(),
          middleInitial: _middleInitialController.text.trim(),
          lastName: _lastNameController.text.trim(),
          course: course,
          yearLevel: yearLevel,
          section: _sectionController.text.trim(),
          guardianName: _guardianController.text.trim(),
        ),
        widget.editing,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseItems = _courseOptions.skip(1).toList();
    final yearItems = _yearLevelOptions.skip(1).toList();

    return AlertDialog(
      title: Text(widget.editing == null ? 'Register Student' : 'Edit Student'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: _RecordsColors.dangerRed)),
                const SizedBox(height: 12),
              ],
              TextField(controller: _rfidController, decoration: const InputDecoration(labelText: 'RFID No.')),
              const SizedBox(height: 10),
              TextField(controller: _studentNumberController, decoration: const InputDecoration(labelText: 'Student Number')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _course,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Course'),
                items: courseItems.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (value) => setState(() => _course = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _yearLevel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Year Level'),
                items: yearItems.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                onChanged: (value) => setState(() => _yearLevel = value),
              ),
              const SizedBox(height: 10),
              TextField(controller: _sectionController, decoration: const InputDecoration(labelText: 'Section')),
              const SizedBox(height: 10),
              TextField(controller: _firstNameController, decoration: const InputDecoration(labelText: 'First Name')),
              const SizedBox(height: 10),
              TextField(controller: _lastNameController, decoration: const InputDecoration(labelText: 'Last Name')),
              const SizedBox(height: 10),
              TextField(controller: _middleInitialController, decoration: const InputDecoration(labelText: 'M.I.')),
              const SizedBox(height: 10),
              TextField(controller: _guardianController, decoration: const InputDecoration(labelText: 'Parent/Guardian Name')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.editing == null ? 'Register' : 'Save Changes'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Export it**

In `packages/rfid_management_module/lib/rfid_management_module.dart`, add:

```dart
export 'ui/student_records_tab.dart';
```

- [ ] **Step 3: Write the test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  RfidStudentRow makeStudent() => const RfidStudentRow(
        id: 's1',
        rfidNo: 'RFID-001',
        studentNumber: '2024-0001',
        firstName: 'Juan',
        middleInitial: 'D',
        lastName: 'Cruz',
        course: 'BS Information Technology',
        yearLevel: '1st Year',
        section: 'IT-101',
        guardianName: 'Maria Cruz',
      );

  Widget buildTab({required List<RfidStudentRow> students, bool isLoading = false, VoidCallback? onDeleteCalled}) {
    return MaterialApp(
      home: Scaffold(
        body: StudentRecordsTab(
          students: students,
          isLoading: isLoading,
          isBusy: false,
          currentPage: 1,
          totalPages: 1,
          totalCount: students.length,
          selectedCourse: 'All Courses',
          selectedYearLevel: 'All Years',
          selectedSection: 'All Sections',
          sectionOptions: const [],
          onSearchChanged: (_) {},
          onCourseChanged: (_) {},
          onYearLevelChanged: (_) {},
          onSectionChanged: (_) {},
          onPreviousPage: () {},
          onNextPage: () {},
          onSave: (form, editing) async {},
          onDelete: (student) async => onDeleteCalled?.call(),
        ),
      ),
    );
  }

  testWidgets('shows skeleton rows while loading with no data yet', (tester) async {
    await tester.pumpWidget(buildTab(students: const [], isLoading: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No students match these filters.'), findsNothing);
  });

  testWidgets('delete requires tapping the destructive Delete button, not a bare tap', (tester) async {
    var deleteCalls = 0;
    await tester.pumpWidget(buildTab(students: [makeStudent()], onDeleteCalled: () => deleteCalls++));

    await tester.tap(find.byTooltip('Delete student'));
    await tester.pumpAndSettle();

    // The danger-zone dialog is open but nothing has been deleted yet.
    expect(deleteCalls, 0);
    expect(find.text('Delete Juan D. Cruz?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);

    await tester.tap(find.byTooltip('Delete student'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
  });
}
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/rfid_management_module && flutter test test/student_records_tab_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add packages/rfid_management_module/lib/ui/student_records_tab.dart packages/rfid_management_module/lib/rfid_management_module.dart packages/rfid_management_module/test/student_records_tab_test.dart
git commit -m "Add Student Records tab with filters, pagination, skeleton loading, and danger-zone delete"
```

---

### Task 9: Embed Reader Devices as a tab

**Files:**
- Modify: `packages/rfid_management_module/lib/ui/rfid_reader_management_page.dart`

**Interfaces:**
- Produces: `RfidReaderManagementPage` gains an `embedded` bool constructor param (default `false`) — when `true`, renders just the body content (no `Scaffold`/`AppBar`/floating action button), so it can sit inside the IT Technician dashboard's tab content area. Default `false` preserves every existing caller unchanged.

- [ ] **Step 1: Add the `embedded` flag**

In `packages/rfid_management_module/lib/ui/rfid_reader_management_page.dart`, add `this.embedded = false` to the constructor and a matching field:

```dart
  const RfidReaderManagementPage({
    super.key,
    required this.readers,
    required this.isBusy,
    required this.onAddReader,
    required this.onUpdateReader,
    required this.onSetActive,
    this.onReturnToHub,
    this.embedded = false,
  });

  // ...existing fields...
  final bool embedded;
```

Replace the `build` method's body to branch on `embedded`:

```dart
  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Every reader in the floor-attendance network, plus the '
                    'main kiosk\'s own reader. Deactivating a reader stops it '
                    'from recording new taps but keeps its history.',
                    style: TextStyle(fontSize: 13, color: _ReaderColors.secondaryText),
                  ),
                ),
                if (embedded)
                  FilledButton.icon(
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Reader'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: readers.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: readers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final reader = readers[index];
                        return _ReaderCard(
                          reader: reader,
                          busy: isBusy,
                          onEdit: () => _openForm(context, editing: reader),
                          onToggleActive: () => onSetActive(reader.id, !reader.isActive),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    if (embedded) {
      return ColoredBox(color: _ReaderColors.background, child: body);
    }

    return Scaffold(
      backgroundColor: _ReaderColors.background,
      appBar: AppBar(
        backgroundColor: _ReaderColors.header,
        foregroundColor: Colors.white,
        title: const Text('RFID Reader Devices'),
        leading: onReturnToHub == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onReturnToHub),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Reader'),
      ),
      body: body,
    );
  }
```

- [ ] **Step 2: Commit**

```bash
git add packages/rfid_management_module/lib/ui/rfid_reader_management_page.dart
git commit -m "Let RfidReaderManagementPage embed without its own Scaffold/AppBar"
```

---

### Task 10: Technical Issues tab (queue + detail + comment thread)

**Files:**
- Create: `packages/rfid_management_module/lib/ui/technical_issues_tab.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`

**Interfaces:**
- Produces: `TechnicalIssueRowModel` (package-local presentation model: `{id, categoryLabel, description, location, reportedByLabel, statusLabel, status (raw string 'open'/'in_progress'/'resolved'), createdAtLabel}`), `TechnicalIssueCommentRowModel` (`{id, authorLabel, message, createdAtLabel}`), `TechnicalIssuesTab` widget:

```dart
TechnicalIssuesTab({
  required List<TechnicalIssueRowModel> reports,
  required bool isLoading,
  required String statusFilter, // 'All' | 'Open' | 'In Progress' | 'Resolved'
  required ValueChanged<String> onStatusFilterChanged,
  required Future<List<TechnicalIssueCommentRowModel>> Function(String reportId) onLoadComments,
  required Future<void> Function(String reportId, String message) onAddComment,
  required Future<void> Function(String reportId, String newStatus) onChangeStatus,
})
```

- [ ] **Step 1: Write the tab**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class _IssueColors {
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
}

class TechnicalIssueRowModel {
  const TechnicalIssueRowModel({
    required this.id,
    required this.categoryLabel,
    required this.description,
    required this.location,
    required this.reportedByLabel,
    required this.status,
    required this.statusLabel,
    required this.createdAtLabel,
  });

  final String id;
  final String categoryLabel;
  final String description;
  final String? location;
  final String reportedByLabel;

  /// Raw db value: 'open' | 'in_progress' | 'resolved'.
  final String status;
  final String statusLabel;
  final String createdAtLabel;
}

class TechnicalIssueCommentRowModel {
  const TechnicalIssueCommentRowModel({
    required this.id,
    required this.authorLabel,
    required this.message,
    required this.createdAtLabel,
  });

  final String id;
  final String authorLabel;
  final String message;
  final String createdAtLabel;
}

const _statusFilters = ['All', 'Open', 'In Progress', 'Resolved'];
const _statusOptions = ['open', 'in_progress', 'resolved'];

class TechnicalIssuesTab extends StatelessWidget {
  const TechnicalIssuesTab({
    super.key,
    required this.reports,
    required this.isLoading,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onLoadComments,
    required this.onAddComment,
    required this.onChangeStatus,
  });

  final List<TechnicalIssueRowModel> reports;
  final bool isLoading;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final Future<List<TechnicalIssueCommentRowModel>> Function(String reportId) onLoadComments;
  final Future<void> Function(String reportId, String message) onAddComment;
  final Future<void> Function(String reportId, String newStatus) onChangeStatus;

  void _openDetail(BuildContext context, TechnicalIssueRowModel report) {
    showDialog<void>(
      context: context,
      builder: (_) => _TicketDetailDialog(
        report: report,
        onLoadComments: onLoadComments,
        onAddComment: onAddComment,
        onChangeStatus: onChangeStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _IssueColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _IssueColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Technical Issues',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: _IssueColors.primaryText),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _statusFilters.map((label) {
              return ChoiceChip(
                label: Text(label),
                selected: statusFilter == label,
                onSelected: (_) => onStatusFilterChanged(label),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator()))
          else if (reports.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No technical issues match this filter.')),
            )
          else
            ...reports.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TicketRow(report: report, onTap: () => _openDetail(context, report)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.report, required this.onTap});

  final TechnicalIssueRowModel report;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (report.status) {
      case 'resolved':
        return const Color(0xFF16A34A);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _IssueColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.categoryLabel,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _IssueColors.primaryText),
                    ),
                    Text(
                      report.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, color: _IssueColors.secondaryText),
                    ),
                  ],
                ),
              ),
              Text(report.statusLabel, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketDetailDialog extends StatefulWidget {
  const _TicketDetailDialog({
    required this.report,
    required this.onLoadComments,
    required this.onAddComment,
    required this.onChangeStatus,
  });

  final TechnicalIssueRowModel report;
  final Future<List<TechnicalIssueCommentRowModel>> Function(String reportId) onLoadComments;
  final Future<void> Function(String reportId, String message) onAddComment;
  final Future<void> Function(String reportId, String newStatus) onChangeStatus;

  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  List<TechnicalIssueCommentRowModel>? _comments;
  final _replyController = TextEditingController();
  late String _status = widget.report.status;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final comments = await widget.onLoadComments(widget.report.id);
    if (!mounted) return;
    setState(() => _comments = comments);
  }

  Future<void> _send() async {
    final message = _replyController.text.trim();
    if (message.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onAddComment(widget.report.id, message);
      _replyController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.report.categoryLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.report.description),
            if (widget.report.location != null) ...[
              const SizedBox(height: 4),
              Text('Location: ${widget.report.location}', style: const TextStyle(color: _IssueColors.secondaryText)),
            ],
            const SizedBox(height: 4),
            Text('Reported by ${widget.report.reportedByLabel}', style: const TextStyle(color: _IssueColors.secondaryText)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
              items: _statusOptions
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s == 'open' ? 'Open' : s == 'in_progress' ? 'In Progress' : 'Resolved'),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _status = value);
                widget.onChangeStatus(widget.report.id, value);
              },
            ),
            const Divider(height: 24),
            Expanded(
              child: _comments == null
                  ? const Center(child: CircularProgressIndicator())
                  : _comments!.isEmpty
                      ? const Center(child: Text('No replies yet.'))
                      : ListView.builder(
                          itemCount: _comments!.length,
                          itemBuilder: (context, index) {
                            final c = _comments![index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.authorLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                  Text(c.message),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    decoration: const InputDecoration(hintText: 'Reply...', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
```

- [ ] **Step 2: Export it**

In `packages/rfid_management_module/lib/rfid_management_module.dart`, add:

```dart
export 'ui/technical_issues_tab.dart';
```

- [ ] **Step 3: Commit**

```bash
git add packages/rfid_management_module/lib/ui/technical_issues_tab.dart packages/rfid_management_module/lib/rfid_management_module.dart
git commit -m "Add Technical Issues tab with ticket queue and comment thread"
```

---

### Task 11: `ItTechnicianConnectedPage` — wire everything to Supabase

**Files:**
- Create: `lib/ui/it_technician_connected_page.dart`
- Delete: `lib/ui/dashboard_page.dart`
- Delete: `lib/ui/admin/rfid_reader_management_connected_page.dart`

**Interfaces:**
- Consumes: `ItTechnicianDashboardPage`, `StudentRecordsTab`, `RfidReaderManagementPage`, `TechnicalIssuesTab`, `TechnicalIssueRowModel`, `TechnicalIssueCommentRowModel` (from `rfid_management_module`); `StudentsRepository`, `RfidReaderRepository`, `TechnicalIssuesRepository`, `NotificationsRepository` (from `lib/data/`).
- Produces: `ItTechnicianConnectedPage` widget, constructor `{String? technicianName, String? technicianProfileId, VoidCallback? onReturnToHub, VoidCallback? onSignOut}`.

- [ ] **Step 1: Write the connected page**

```dart
import 'dart:async';

import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_role.dart';
import '../data/notifications_repository.dart';
import '../data/rfid_reader_repository.dart';
import '../data/students_repository.dart';
import '../data/technical_issues_repository.dart';
import '../env.dart';
import '../models/student_record.dart';

/// Wires [ItTechnicianDashboardPage] and its three tabs to Supabase — the
/// student directory (paginated), the reader-device network, and the
/// technical-issue ticket queue, plus the shared notification bell.
class ItTechnicianConnectedPage extends StatefulWidget {
  const ItTechnicianConnectedPage({
    super.key,
    this.technicianName,
    this.technicianProfileId,
    this.onReturnToHub,
    this.onSignOut,
  });

  final String? technicianName;
  final String? technicianProfileId;
  final VoidCallback? onReturnToHub;
  final VoidCallback? onSignOut;

  @override
  State<ItTechnicianConnectedPage> createState() => _ItTechnicianConnectedPageState();
}

class _ItTechnicianConnectedPageState extends State<ItTechnicianConnectedPage> {
  // Student Records state
  List<StudentRecord> _students = [];
  bool _studentsLoading = false;
  bool _studentsBusy = false;
  int _page = 1;
  int _totalPages = 1;
  int? _totalCount;
  String _course = 'All Courses';
  String _yearLevel = 'All Years';
  String _section = 'All Sections';
  List<String> _sectionOptions = [];
  String _searchQuery = '';

  // Reader Devices state
  List<RfidReaderRecord> _readers = [];
  bool _readersBusy = false;

  // Technical Issues state
  List<TechnicalIssueReport> _reports = [];
  bool _reportsLoading = false;
  String _statusFilterLabel = 'All';

  // Notifications
  List<NotificationItemModel>? _notifications;
  RealtimeChannel? _notificationsChannel;
  Timer? _reloadDebounce;

  static const _demoTechnicianProfileId = '00000000-0000-4000-8000-000000000099';

  String get _effectiveTechnicianId {
    final id = widget.technicianProfileId;
    if (id == null || id.startsWith('u_')) return _demoTechnicianProfileId;
    return id;
  }

  StudentsRepository? get _studentsRepo =>
      AppEnv.supabaseConfigured ? StudentsRepository(Supabase.instance.client) : null;
  RfidReaderRepository? get _readerRepo =>
      AppEnv.supabaseConfigured ? RfidReaderRepository(Supabase.instance.client) : null;
  TechnicalIssuesRepository? get _issuesRepo =>
      AppEnv.supabaseConfigured ? TechnicalIssuesRepository(Supabase.instance.client) : null;
  NotificationsRepository? get _notifRepo =>
      AppEnv.supabaseConfigured ? NotificationsRepository(Supabase.instance.client) : null;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Student Records -------------------------------------------------

  Future<void> _loadStudents() async {
    final repo = _studentsRepo;
    if (repo == null) return;
    setState(() => _studentsLoading = true);
    try {
      final course = _course == 'All Courses' ? null : _course;
      final yearLevel = _yearLevel == 'All Years'
          ? null
          : _yearLevelOptionToInt(_yearLevel);
      String? sectionId;
      if (_section != 'All Sections' && course != null && yearLevel != null) {
        sectionId = await repo.findSectionId(program: course, yearLevel: yearLevel, sectionName: _section);
      }
      final result = await repo.fetchPage(
        page: _page,
        course: course,
        yearLevel: yearLevel,
        sectionId: sectionId,
        studentNumberQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (!mounted) return;
      setState(() {
        _students = result.items;
        _totalCount = result.totalCount;
        _totalPages = (result.totalCount / 25).ceil().clamp(1, 1 << 30);
      });
      if (course != null && yearLevel != null) {
        final sections = await repo.fetchSectionNames(program: course, yearLevel: yearLevel);
        if (mounted) setState(() => _sectionOptions = sections);
      }
    } catch (e) {
      _toast('Could not load students: $e');
    } finally {
      if (mounted) setState(() => _studentsLoading = false);
    }
  }

  int _yearLevelOptionToInt(String label) =>
      ['1st Year', '2nd Year', '3rd Year', '4th Year'].indexOf(label) + 1;

  List<RfidStudentRow> get _studentRows => _students
      .map((s) => RfidStudentRow(
            id: s.id,
            rfidNo: s.rfidNo,
            studentNumber: s.studentNumber,
            firstName: s.firstName,
            middleInitial: s.middleInitial,
            lastName: s.lastName,
            course: s.course,
            yearLevel: s.yearLevel,
            section: s.section,
            guardianName: s.guardianName,
          ))
      .toList();

  Future<void> _saveStudent(RfidRegistrationForm form, RfidStudentRow? editing) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    final yearLevelInt = StudentRecord.yearLabelToInt(form.yearLevel);
    setState(() => _studentsBusy = true);
    try {
      if (editing != null) {
        await repo.update(
          id: editing.id,
          studentNumber: form.studentNumber,
          rfidUid: form.rfidNo,
          firstName: form.firstName,
          middleInitial: form.middleInitial,
          lastName: form.lastName,
          course: form.course,
          yearLevel: yearLevelInt,
          sectionName: form.section,
        );
      } else {
        await repo.create(
          studentNumber: form.studentNumber,
          rfidUid: form.rfidNo,
          firstName: form.firstName,
          middleInitial: form.middleInitial,
          lastName: form.lastName,
          course: form.course,
          yearLevel: yearLevelInt,
          sectionName: form.section,
        );
      }
      await _loadStudents();
      // No catch here: `_StudentFormDialog.onSave`'s own try/catch (Task 8)
      // already displays the error inline and keeps the dialog open on
      // failure — catching and rethrowing here would add nothing.
    } finally {
      if (mounted) setState(() => _studentsBusy = false);
    }
  }

  Future<void> _deleteStudent(RfidStudentRow student) async {
    final repo = _studentsRepo;
    if (repo == null) return;
    setState(() => _studentsBusy = true);
    try {
      await repo.deleteById(student.id);
      await _loadStudents();
    } catch (e) {
      _toast('Could not delete: $e');
    } finally {
      if (mounted) setState(() => _studentsBusy = false);
    }
  }

  // --- Reader Devices ----------------------------------------------------

  Future<void> _loadReaders() async {
    final repo = _readerRepo;
    if (repo == null) return;
    try {
      final readers = await repo.fetchReaders(includeInactive: true);
      if (mounted) setState(() => _readers = readers);
    } catch (e) {
      _toast('Could not load readers: $e');
    }
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return 'never';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  RfidReaderRowModel _toReaderRow(RfidReaderRecord r) => RfidReaderRowModel(
        id: r.id,
        label: r.label,
        usbSerial: r.usbSerial,
        location: r.location,
        isKioskReader: r.isKioskReader,
        isActive: r.isActive,
        isOnline: r.isOnline,
        lastSeenLabel: _relativeTime(r.lastSeenAt),
      );

  Future<void> _addReader({required String label, required String usbSerial, String? location}) async {
    final repo = _readerRepo;
    if (repo == null) return;
    setState(() => _readersBusy = true);
    try {
      await repo.addReader(label: label, usbSerial: usbSerial, location: location);
      await _loadReaders();
    } finally {
      if (mounted) setState(() => _readersBusy = false);
    }
  }

  Future<void> _updateReader({
    required String id,
    required String label,
    required String usbSerial,
    String? location,
  }) async {
    final repo = _readerRepo;
    if (repo == null) return;
    setState(() => _readersBusy = true);
    try {
      await repo.updateReader(id: id, label: label, usbSerial: usbSerial, location: location);
      await _loadReaders();
    } finally {
      if (mounted) setState(() => _readersBusy = false);
    }
  }

  Future<void> _setReaderActive(String id, bool isActive) async {
    final repo = _readerRepo;
    if (repo == null) return;
    setState(() => _readersBusy = true);
    try {
      await repo.setReaderActive(id, isActive);
      await _loadReaders();
    } catch (e) {
      _toast('Could not update reader: $e');
    } finally {
      if (mounted) setState(() => _readersBusy = false);
    }
  }

  // --- Technical Issues ----------------------------------------------------

  TechnicalIssueStatus? _statusFilterValue() {
    switch (_statusFilterLabel) {
      case 'Open':
        return TechnicalIssueStatus.open;
      case 'In Progress':
        return TechnicalIssueStatus.inProgress;
      case 'Resolved':
        return TechnicalIssueStatus.resolved;
      default:
        return null;
    }
  }

  Future<void> _loadReports() async {
    final repo = _issuesRepo;
    if (repo == null) return;
    setState(() => _reportsLoading = true);
    try {
      final reports = await repo.fetchReports(status: _statusFilterValue());
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      _toast('Could not load technical issues: $e');
    } finally {
      if (mounted) setState(() => _reportsLoading = false);
    }
  }

  TechnicalIssueRowModel _toReportRow(TechnicalIssueReport r) => TechnicalIssueRowModel(
        id: r.id,
        categoryLabel: r.category.label,
        description: r.description,
        location: r.location,
        reportedByLabel: r.reportedByRole,
        status: r.status.dbValue,
        statusLabel: r.status.label,
        createdAtLabel: _relativeTime(r.createdAt),
      );

  Future<List<TechnicalIssueCommentRowModel>> _loadComments(String reportId) async {
    final repo = _issuesRepo;
    if (repo == null) return const [];
    final comments = await repo.fetchComments(reportId);
    return comments
        .map((c) => TechnicalIssueCommentRowModel(
              id: c.id,
              authorLabel: c.authorRole,
              message: c.message,
              createdAtLabel: _relativeTime(c.createdAt),
            ))
        .toList();
  }

  Future<void> _addComment(String reportId, String message) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    await repo.addComment(
      reportId: reportId,
      message: message,
      authorId: _effectiveTechnicianId,
      authorRole: 'IT_Technician',
    );
  }

  Future<void> _changeStatus(String reportId, String newStatusValue) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    final status = technicalIssueStatusFromDb(newStatusValue);
    await repo.updateStatus(id: reportId, status: status, resolvedBy: _effectiveTechnicianId);
    await _loadReports();
  }

  // --- Notifications ----------------------------------------------------

  Future<void> _loadNotifications() async {
    final notifications = await _notifRepo?.fetchForRole(
      AppRole.itTechnician,
      userId: _effectiveTechnicianId,
    );
    if (!mounted || notifications == null) return;
    setState(() => _notifications = notifications);
  }

  Future<void> _markNotificationsRead() async {
    await _notifRepo?.markAllReadForRole(AppRole.itTechnician, userId: _effectiveTechnicianId);
  }

  void _subscribeToNotificationChanges() {
    if (!AppEnv.supabaseConfigured) return;
    _notificationsChannel = Supabase.instance.client
        .channel('public:notifications:it_technician')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            _reloadDebounce?.cancel();
            _reloadDebounce = Timer(const Duration(milliseconds: 400), _loadNotifications);
          },
        )
        .subscribe();
  }

  // --- Lifecycle ----------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudents();
      _loadReaders();
      _loadReports();
      _loadNotifications();
    });
    _subscribeToNotificationChanges();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final channel = _notificationsChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ItTechnicianDashboardPage(
      technicianName: widget.technicianName ?? 'IT Technician',
      onReturnToHub: widget.onReturnToHub,
      onSignOut: widget.onSignOut,
      initialStats: ItTechnicianOverviewStats(
        totalStudents: _totalCount ?? _students.length,
        totalReaders: _readers.length,
        onlineReaders: _readers.where((r) => r.isOnline).length,
        openTicketCount: _reports.where((r) => r.status != TechnicalIssueStatus.resolved).length,
      ),
      initialNotifications: _notifications,
      onMarkNotificationsRead: _notifRepo == null ? null : _markNotificationsRead,
      studentRecordsTabBuilder: (_) => StudentRecordsTab(
        students: _studentRows,
        isLoading: _studentsLoading,
        isBusy: _studentsBusy,
        currentPage: _page,
        totalPages: _totalPages,
        totalCount: _totalCount,
        selectedCourse: _course,
        selectedYearLevel: _yearLevel,
        selectedSection: _section,
        sectionOptions: _sectionOptions,
        onSearchChanged: (value) {
          _searchQuery = value;
          _page = 1;
          _loadStudents();
        },
        onCourseChanged: (value) {
          setState(() {
            _course = value;
            _section = 'All Sections';
            _page = 1;
          });
          _loadStudents();
        },
        onYearLevelChanged: (value) {
          setState(() {
            _yearLevel = value;
            _section = 'All Sections';
            _page = 1;
          });
          _loadStudents();
        },
        onSectionChanged: (value) {
          setState(() {
            _section = value;
            _page = 1;
          });
          _loadStudents();
        },
        onPreviousPage: () {
          if (_page <= 1) return;
          setState(() => _page -= 1);
          _loadStudents();
        },
        onNextPage: () {
          if (_page >= _totalPages) return;
          setState(() => _page += 1);
          _loadStudents();
        },
        onSave: _saveStudent,
        onDelete: _deleteStudent,
      ),
      readerDevicesTabBuilder: (_) => RfidReaderManagementPage(
        embedded: true,
        readers: _readers.map(_toReaderRow).toList(),
        isBusy: _readersBusy,
        onAddReader: _addReader,
        onUpdateReader: _updateReader,
        onSetActive: _setReaderActive,
      ),
      technicalIssuesTabBuilder: (_) => TechnicalIssuesTab(
        reports: _reports.map(_toReportRow).toList(),
        isLoading: _reportsLoading,
        statusFilter: _statusFilterLabel,
        onStatusFilterChanged: (label) {
          setState(() => _statusFilterLabel = label);
          _loadReports();
        },
        onLoadComments: _loadComments,
        onAddComment: _addComment,
        onChangeStatus: _changeStatus,
      ),
    );
  }
}
```

- [ ] **Step 2: Remove the replaced files**

```bash
git rm lib/ui/dashboard_page.dart lib/ui/admin/rfid_reader_management_connected_page.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/ui/it_technician_connected_page.dart
git commit -m "Add ItTechnicianConnectedPage, replacing the old RFID dashboard/reader connected pages"
```

---

### Task 12: Routing — Admin Hub tile and direct-login landing

**Files:**
- Modify: `lib/ui/admin/admin_hub_page.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `ItTechnicianConnectedPage` (Task 11).
- Produces: the `rfidManagement` module tile opens `ItTechnicianConnectedPage`; `AppRole.itTechnician` logging in directly lands on it too (no hub).

- [ ] **Step 1: Update the Admin Hub tile**

In `lib/ui/admin/admin_hub_page.dart`, replace the `SystemModuleId.rfidManagement` case:

```dart
      case SystemModuleId.rfidManagement:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (routeContext) => ItTechnicianConnectedPage(
              technicianName: user.displayName,
              technicianProfileId: user.id,
              onReturnToHub: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
        return;
```

Update the import at the top (replace the `dashboard_page.dart` import):

```dart
import '../it_technician_connected_page.dart';
```

Add `SystemModuleId.rfidManagement` to the `isLive` check further down (it already is — it's the first entry in that boolean-or chain — no change needed there; just confirm it's still present after the edit).

- [ ] **Step 2: Update direct-login routing**

In `lib/main.dart`, add a case in `_homeForRole` (after the `teacher` block, before the `moduleId` switch):

```dart
  if (role == AppRole.itTechnician) {
    return ItTechnicianConnectedPage(
      technicianName: session.user!.displayName,
      technicianProfileId: session.user!.id,
      onSignOut: session.signOut,
    );
  }
```

Add the import:

```dart
import 'ui/it_technician_connected_page.dart';
```

Remove `AppRole.itTechnician` handling from the fallback `moduleId` switch's exhaustiveness — since it's now handled above, the switch's `disciplineOfficer || guidanceCounselor || teacher || administrator => throw StateError(...)` arm needs `itTechnician` added to that same throwing arm (Dart's exhaustiveness check requires every enum value be covered):

```dart
    AppRole.disciplineOfficer ||
    AppRole.guidanceCounselor ||
    AppRole.teacher ||
    AppRole.administrator ||
    AppRole.itTechnician =>
      throw StateError('handled above'),
```

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib/main.dart lib/ui/admin/admin_hub_page.dart`
Expected: no errors (confirms the exhaustiveness switch and imports are correct).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/admin/admin_hub_page.dart lib/main.dart
git commit -m "Route the IT Technician role and Admin Hub tile to the new dashboard"
```

---

### Task 13: Teacher entry point — report a technical issue

**Files:**
- Modify: `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart`
- Modify: `lib/ui/professor_connected_page.dart`
- Modify: `packages/professor_module/pubspec.yaml`

**Interfaces:**
- Consumes: `ReportTechnicalIssueDialog`, `showReportTechnicalIssueDialog`, `ReportTechnicalIssueCategory` (from `dashboard_layout`, Task 5).
- Produces: `ProfessorDashboardPage` gains `this.onReportTechnicalIssue` (`Future<void> Function({required ReportTechnicalIssueCategory category, required String description, String? location})?`) and a wrench header icon that opens the dialog when it's supplied.

- [ ] **Step 1: Add the dependency**

Confirm `packages/professor_module/pubspec.yaml` already depends on `dashboard_layout` (it does — see Task setup research; the existing `dependencies:` block already lists it). No change needed here.

- [ ] **Step 2: Add the constructor param and header icon**

In `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart`, add to the `ProfessorDashboardPage` constructor's param list (after `onSubmitAttendance`):

```dart
    this.onReportTechnicalIssue,
```

Add the field:

```dart
  /// Opens the shared technical-issue report dialog when supplied. Falls
  /// back to no header icon at all when omitted (demo behavior — nowhere to
  /// send the report).
  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  })? onReportTechnicalIssue;
```

Add the import at the top of the file:

```dart
import 'package:dashboard_layout/dashboard_layout.dart';
```

(the file already imports `dashboard_layout` for `AppHeaderNavBar` etc. — just confirm `showReportTechnicalIssueDialog`/`ReportTechnicalIssueCategory` come through that same import, since Task 5 exported them from the same package.)

In the `build` method's `actions:` list (inside the `if (!isMobile) ...` block, right after the notifications `HeaderIconButton`), add:

```dart
                if (widget.onReportTechnicalIssue != null)
                  HeaderIconButton(
                    icon: Icons.build_outlined,
                    onTap: () => showReportTechnicalIssueDialog(
                      context,
                      onSubmit: widget.onReportTechnicalIssue!,
                    ),
                  ),
```

- [ ] **Step 3: Wire it in the connected page**

In `lib/ui/professor_connected_page.dart`, add the import:

```dart
import 'package:dashboard_layout/dashboard_layout.dart' show ReportTechnicalIssueCategory;

import '../data/technical_issues_repository.dart';
```

Add a getter next to `_notifRepo`:

```dart
  TechnicalIssuesRepository? get _issuesRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return TechnicalIssuesRepository(Supabase.instance.client);
  }
```

Add a handler method (near `_markNotificationsRead`):

```dart
  Future<void> _reportTechnicalIssue({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) async {
    final repo = _issuesRepo;
    if (repo == null) return;
    await repo.report(
      category: _mapCategory(category),
      description: description,
      location: location,
      reporterId: _effectiveProfessorId,
      reporterRole: 'Teacher',
    );
  }

  TechnicalIssueCategory _mapCategory(ReportTechnicalIssueCategory category) {
    switch (category) {
      case ReportTechnicalIssueCategory.offlineDevice:
        return TechnicalIssueCategory.offlineDevice;
      case ReportTechnicalIssueCategory.offlineKiosk:
        return TechnicalIssueCategory.offlineKiosk;
      case ReportTechnicalIssueCategory.classroomPc:
        return TechnicalIssueCategory.classroomPc;
      case ReportTechnicalIssueCategory.other:
        return TechnicalIssueCategory.other;
    }
  }
```

Pass it to `ProfessorDashboardPage` in `build`:

```dart
      onReportTechnicalIssue: _issuesRepo == null ? null : _reportTechnicalIssue,
```

- [ ] **Step 4: Run the analyzer**

Run: `flutter analyze packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart lib/ui/professor_connected_page.dart`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart lib/ui/professor_connected_page.dart
git commit -m "Add Report Technical Issue entry point to the Professor dashboard header"
```

---

### Task 14: Admin entry point — report a technical issue

**Files:**
- Modify: `packages/admin_dashboard/lib/widgets/sidebar/sidebar_header.dart`
- Modify: `packages/admin_dashboard/lib/widgets/sidebar/sidebar.dart`
- Modify: `packages/admin_dashboard/lib/layout/dashboard_shell.dart`
- Modify: `packages/admin_dashboard/lib/admin_dashboard_page.dart`
- Modify: `lib/ui/admin/admin_dashboard_connected_page.dart`
- Modify: `packages/admin_dashboard/pubspec.yaml`

**Interfaces:**
- Consumes: `ReportTechnicalIssueDialog`, `ReportTechnicalIssueCategory` from `dashboard_layout` (Task 5) — `admin_dashboard` already depends on `dashboard_layout` (confirmed via `DashboardPageWrapper` usage in `dashboard_shell.dart`), so no pubspec change is actually needed; this file is listed only so the implementer double-checks it during the task rather than assuming.
- Produces: a wrench icon next to the sidebar's notification bell, opening the same shared dialog, wired to `TechnicalIssuesRepository.report` with `reporterRole: 'Admin'`.

- [ ] **Step 1: Add the icon to `SidebarHeader`**

In `packages/admin_dashboard/lib/widgets/sidebar/sidebar_header.dart`, add to the constructor:

```dart
    this.onReportIssueTap,
```

Add the field (after `onNotificationsTap`):

```dart
  /// Opens the shared technical-issue report dialog when supplied. Falls
  /// back to no icon at all when omitted.
  final VoidCallback? onReportIssueTap;
```

In `build`, add a second `InkWell` right after the notifications `InkWell` (inside the same trailing `Row`, before its closing bracket):

```dart
          if (onReportIssueTap != null)
            InkWell(
              onTap: onReportIssueTap,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.build_outlined, color: Colors.white, size: 22),
              ),
            ),
```

- [ ] **Step 2: Thread it through `Sidebar`**

In `packages/admin_dashboard/lib/widgets/sidebar/sidebar.dart`, add to the constructor:

```dart
    this.onReportIssueTap,
```

Add the field (after `onNotificationsTap`):

```dart
  final VoidCallback? onReportIssueTap;
```

Pass it through in the `SidebarHeader(...)` call inside `build`:

```dart
              SidebarHeader(
                onBackToHub: widget.onBackToHub,
                unreadNotificationCount: widget.unreadNotificationCount,
                onNotificationsTap: widget.onNotificationsTap,
                onReportIssueTap: widget.onReportIssueTap,
              ),
```

- [ ] **Step 3: Thread it through `DashboardShell`**

In `packages/admin_dashboard/lib/layout/dashboard_shell.dart`, add to the constructor:

```dart
    this.onReportTechnicalIssue,
```

Add the field (after `onMarkNotificationsRead`):

```dart
  /// Submits a technical-issue report when supplied — see
  /// [ReportTechnicalIssueDialog]. Falls back to no report-issue icon in
  /// the sidebar when omitted.
  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  })? onReportTechnicalIssue;
```

Add the import:

```dart
import 'package:dashboard_layout/dashboard_layout.dart';
```

(it's likely already imported for `DashboardPageWrapper` — confirm rather than duplicate.)

Add a method mirroring `_showNotificationsMenu`:

```dart
  void _showReportIssueDialog(BuildContext context) {
    showReportTechnicalIssueDialog(context, onSubmit: widget.onReportTechnicalIssue!);
  }
```

Wire it into the `Sidebar(...)` call inside `_buildScaffold`:

```dart
          Sidebar(
            selectedRoute: _selectedRoute,
            onRouteSelected: _selectRoute,
            userName: widget.userName,
            userEmail: widget.userEmail,
            onLogout: () => _confirmLogout(context),
            onBackToHub: widget.onReturnToHub,
            unreadNotificationCount: (widget.initialNotifications ?? const [])
                .where((n) => !n.isRead)
                .length,
            onNotificationsTap: () => _showNotificationsMenu(context),
            onReportIssueTap: widget.onReportTechnicalIssue == null
                ? null
                : () => _showReportIssueDialog(context),
          ),
```

- [ ] **Step 4: Thread it through `AdminDashboardPage`**

In `packages/admin_dashboard/lib/admin_dashboard_page.dart`, add to the constructor and field list (same pattern as `onMarkNotificationsRead`):

```dart
    this.onReportTechnicalIssue,
```

```dart
  final Future<void> Function({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  })? onReportTechnicalIssue;
```

Add the import (`package:dashboard_layout/dashboard_layout.dart`) and pass it through in `build`:

```dart
      onReportTechnicalIssue: onReportTechnicalIssue,
```

- [ ] **Step 5: Wire it in `AdminDashboardConnectedPage`**

In `lib/ui/admin/admin_dashboard_connected_page.dart`, add the import:

```dart
import 'package:dashboard_layout/dashboard_layout.dart' show ReportTechnicalIssueCategory;

import '../../data/technical_issues_repository.dart';
```

Add a getter next to `_notifRepo`:

```dart
  TechnicalIssuesRepository? get _issuesRepo {
    if (!AppEnv.supabaseConfigured) return null;
    return TechnicalIssuesRepository(Supabase.instance.client);
  }
```

Add a handler (near `_sendComposedNotification`):

```dart
  Future<void> _reportTechnicalIssue({
    required ReportTechnicalIssueCategory category,
    required String description,
    String? location,
  }) async {
    final repo = _issuesRepo;
    final user = widget.currentUser;
    if (repo == null || user == null) return;
    await repo.report(
      category: _mapCategory(category),
      description: description,
      location: location,
      reporterId: user.id.startsWith('u_') ? '00000000-0000-4000-8000-000000000001' : user.id,
      reporterRole: 'Admin',
    );
  }

  TechnicalIssueCategory _mapCategory(ReportTechnicalIssueCategory category) {
    switch (category) {
      case ReportTechnicalIssueCategory.offlineDevice:
        return TechnicalIssueCategory.offlineDevice;
      case ReportTechnicalIssueCategory.offlineKiosk:
        return TechnicalIssueCategory.offlineKiosk;
      case ReportTechnicalIssueCategory.classroomPc:
        return TechnicalIssueCategory.classroomPc;
      case ReportTechnicalIssueCategory.other:
        return TechnicalIssueCategory.other;
    }
  }
```

Pass it to `AdminDashboardPage` in `build`:

```dart
      onReportTechnicalIssue: _issuesRepo == null ? null : _reportTechnicalIssue,
```

> The fixed placeholder id `00000000-0000-4000-8000-000000000001` mirrors the `_demoProfessorProfileId`/`_demoTechnicianProfileId` convention from Tasks 11/13 for a demo Admin account with no real `profiles` row — confirm during implementation whether a real seeded demo Admin profile id already exists elsewhere in this codebase (e.g. `supabase/add_admin_dashboard_schema.sql`) and reuse that instead of inventing a new one, the same way Task 11/13 matched `add_professor_module_schema.sql`'s seeded id.

- [ ] **Step 6: Run the analyzer**

Run: `flutter analyze packages/admin_dashboard/lib lib/ui/admin/admin_dashboard_connected_page.dart`
Expected: no errors

- [ ] **Step 7: Commit**

```bash
git add packages/admin_dashboard/lib/widgets/sidebar/sidebar_header.dart packages/admin_dashboard/lib/widgets/sidebar/sidebar.dart packages/admin_dashboard/lib/layout/dashboard_shell.dart packages/admin_dashboard/lib/admin_dashboard_page.dart lib/ui/admin/admin_dashboard_connected_page.dart
git commit -m "Add Report Technical Issue entry point to the Admin sidebar"
```

---

### Task 15: Delete the old single-page RFID dashboard

**Files:**
- Delete: `packages/rfid_management_module/lib/ui/rfid_dashboard_page.dart`
- Modify: `packages/rfid_management_module/lib/rfid_management_module.dart`

**Interfaces:**
- Produces: nothing (removal only) — `RfidStudentRow`/`RfidRegistrationForm` (from `rfid_student_row.dart`) stay exported since Task 8's `StudentRecordsTab` still uses them.

- [ ] **Step 1: Confirm nothing else references the old page**

Run: `flutter analyze` at the repo root (or at minimum grep for `RfidDashboardPage` across `lib/` and `packages/`) and confirm the only remaining reference, if any, is the export line about to be removed. This project didn't have a workspace-wide `melos` config found during research — run the analyzer per-package if a root-level run isn't configured (`cd . && flutter analyze` for the root app; `cd packages/rfid_management_module && flutter analyze` for the package).

- [ ] **Step 2: Delete the file and its export**

```bash
git rm packages/rfid_management_module/lib/ui/rfid_dashboard_page.dart
```

In `packages/rfid_management_module/lib/rfid_management_module.dart`, remove the line:

```dart
export 'ui/rfid_dashboard_page.dart';
```

leaving:

```dart
library rfid_management_module;

export 'rfid_student_row.dart';
export 'ui/it_technician_dashboard_page.dart';
export 'ui/rfid_reader_management_page.dart';
export 'ui/student_records_tab.dart';
export 'ui/technical_issues_tab.dart';
```

- [ ] **Step 3: Run the full test suite for the touched packages**

Run: `cd packages/rfid_management_module && flutter test`
Expected: PASS (all tests from Tasks 7 and 8)

Run (from repo root): `flutter test test/app_role_it_technician_test.dart test/students_repository_fetch_page_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add packages/rfid_management_module/lib/rfid_management_module.dart
git commit -m "Remove the old single-page RFID Management dashboard, fully replaced by ItTechnicianDashboardPage"
```

---

## Manual steps after all tasks land (for the user, not an agent)

1. **Run the SQL migration.** Open `supabase/add_it_technician_schema.sql` in the Supabase SQL Editor for this project and run it. This adds the `IT_Technician` role value, the two ticket tables, their RLS policies, the two RPCs, and the realtime publication entries. Nothing in Tasks 2–15 will work end-to-end against a live Supabase project until this runs.
2. **Verify the demo account.** After the migration runs, sign in with `ittech.demo` / `ITTech2026!` (added in Task 2) to confirm the new role routes straight to the dashboard.
3. **Assign a real IT Technician account** (optional): from the Admin Dashboard's Staff Accounts page, approve a pending sign-in with the new "IT Technician" role, now that it's in the assignable list.
4. **Smoke-test the two report-issue entry points**: the wrench icon in the Professor dashboard header, and the wrench icon in the Admin sidebar — file a test report from each, then confirm it shows up in the IT Technician dashboard's Technical Issues tab and that a reply back to the reporter's own notification bell shows up too.
