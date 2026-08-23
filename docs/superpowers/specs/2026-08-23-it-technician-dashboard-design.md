# IT Technician Dashboard — Design Spec

Date: 2026-08-23

## Purpose

Replace the current "RFID Management Dashboard" (a single cluttered
scroll-page reachable only as an Admin Hub tile) with a full **IT
Technician Dashboard** — a real staff role and dashboard, built to the
same visual/structural pattern as the Discipline Officer, Guidance
Counselor, and Professor dashboards. It keeps every capability the RFID
Management Dashboard has today (student RFID registration, student
records, reader device management), reorganizes them into clearly
separated sections, and adds a technical-issue reporting/ticketing
system fed by the Teacher and Admin modules.

Responsive-design fixes for the *other*, already-built dashboards
(Admin, Discipline Officer, Guidance Counselor, Professor) are
explicitly **out of scope** for this spec — this dashboard is built
responsive from day one; the others get their own follow-up spec.

## Non-goals

- No auto-detection/alerting when a reader or kiosk goes offline. This
  phase is manual reporting only (Teacher/Admin file a report same as
  a classroom PC problem). IT Technician's Reader Devices tab still
  shows live online/offline status via the existing `isOnline`
  computed field, so technicians can notice it themselves.
- No Registrar-side "new RFID card needed" sending UI — the Registrar
  dashboard doesn't exist yet. The ticket `category` enum just needs
  to be extensible enough to add that value later without a schema
  redesign.
- No changes to the separate RFID Card Mapping page
  (`packages/admin_dashboard/lib/pages/rfid_mapping/rfid_mapping_page.dart`)
  — it isn't part of the RFID Management Dashboard being replaced.
- No standalone "compose and send" tool for IT Technician (like
  Admin's Notifications & Reporting page) — ticket communication is a
  per-ticket comment thread only.

## Architecture

### Role & access

- Add `AppRole.itTechnician` to `lib/auth/app_role.dart`, DB value
  `'IT_Technician'`, added to `staffAssignableRoles` so Admin can
  assign it like any other staff role via the existing staff-approval
  flow (`staff_accounts_page.dart`).
- `lib/modules/module_access.dart`: the module (renamed from RFID
  Management) stays visible to Admin + Registrar (unchanged from
  today) and gains IT Technician.
- `lib/modules/system_module_id.dart`: keep the existing module id (or
  rename consistently — confirm naming during implementation), now
  resolving to the new dashboard shell instead of
  `rfid_dashboard_page.dart`.

### Navigation shell

Rebuilt using the shared `dashboard_layout` package pattern (matching
Discipline Officer/Guidance Counselor/Professor), not the current
single `SingleChildScrollView` page:

- `AppHeaderNavBar` — logo chip, title, and on desktop the standard
  inline mail/notification-bell/profile-avatar icons; on mobile
  (`kDashboardMobileBreakpoint` = 800px, `ResponsiveX.isMobileWidth`)
  those move into an `AppBottomNavBar`, same as every other
  role-dashboard.
- A secondary underline tab bar below the header (same widget family
  as Guidance Counselor's `DashboardHeaderNavBar` / Professor's
  `_SubNavBar`), four tabs:
  1. **Overview** — stat tiles: total students, total readers +
     online/offline counts, open technical-issue count. Uses
     `MobileMetricGrid` for the narrow-width fallback, consistent with
     Guidance Counselor/Professor.
  2. **Student Records** — see below.
  3. **Reader Devices** — today's `RfidReaderManagementPage` content
     folded in as a tab (drops the floating-action-button entry
     point).
  4. **Technical Issues** — the new ticket queue.
- Content wrapped in `DashboardPageWrapper` (1440px cap, 24h/16v
  padding), matching every other dashboard.
- Bell icon reuses the existing `NotificationsPopover` /
  `showHeaderPopover()` / `NotificationsRepository.fetchForRole`
  infrastructure unchanged — IT Technician notifications flow through
  the same generic `notifications` table as every other role.

### Student Records tab

- "Register New Student" moves from a permanent on-page form to a
  dialog/side-panel launched by an action button, so the records table
  isn't permanently sharing space with it (this is the main
  decluttering change from today's page).
- Filtering/sectioning, top to bottom:
  - Year-level quick-filter tabs (All / 1st / 2nd / 3rd / 4th) — lets
    someone browse by scope without typing anything ("sectioning").
  - Search box + Course dropdown + Section dropdown ("filtering").
  - All of the above combine into one server-side query — no more
    "fetch everything, filter in memory."
- Pagination + skeleton loading: copy Student Directory's proven
  pattern near-verbatim —
  `StudentsRepository.fetchPage({page, pageSize, course, yearLevel})`
  (`lib/data/students_repository.dart:91-120`) extended with a new
  `section` parameter and an `ilike` search parameter (so search
  becomes server-side, fixing Student Directory's known
  client-side-per-page limitation instead of copying it forward), the
  `_PaginationFooter` widget, and the `_SkeletonTableBody`/
  `_SkeletonRow` shimmer loader
  (`packages/admin_dashboard/lib/pages/student_directory/student_directory_page.dart`)
  — same visual language app-wide, no second loading-state style.
- Actions: Edit re-opens the registration dialog pre-filled. Delete
  opens a destructive-styled confirmation dialog (red header/icon,
  student name/number shown, requires tapping a red "Delete" button —
  not a generic confirm) — the "danger zone" requirement.

### Technical Issues tab & data model

New tables (SQL migration file, written for user review before
running in Supabase per this project's standing rule — see
`[[feedback_supabase_confirm_sql]]`):

```sql
create type technical_issue_category as enum (
  'offline_device', 'offline_kiosk', 'classroom_pc', 'other'
);
create type technical_issue_status as enum (
  'open', 'in_progress', 'resolved'
);

create table technical_issue_reports (
  id uuid primary key default gen_random_uuid(),
  category technical_issue_category not null,
  description text not null,
  location text,
  reported_by uuid not null references profiles(id),
  reported_by_role text not null,
  status technical_issue_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references profiles(id)
);

create table technical_issue_comments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references technical_issue_reports(id) on delete cascade,
  author_id uuid not null references profiles(id),
  author_role text not null,
  message text not null,
  created_at timestamptz not null default now()
);
```

RLS: insert on `technical_issue_reports` allowed for Teacher + Admin;
select/update allowed for IT Technician + Admin (+ the original
reporter, read-only, so they can see their own ticket's status).
Insert on `technical_issue_comments` allowed for the ticket's
`reported_by` or anyone with role IT_Technician/Admin.

RPC `report_technical_issue(category, description, location)` —
mirrors the existing `record_rfid_tap` RPC style already in this
codebase — inserts the ticket row *and* a `notifications` row
(`target_role = 'IT_Technician'`) in one call, reusing the existing
dual-targeting notification model
(`lib/data/notifications_repository.dart`) rather than building a
second alerting mechanism.

RPC `add_technical_issue_comment(report_id, message)` — inserts the
comment and routes a notification depending on who's posting: IT
Technician/Admin replying → `target_user_id = report.reported_by`
(goes straight back to whoever filed it); the original reporter
replying → `target_role = 'IT_Technician'` again. Every such
notification's message links back to the ticket id so tapping it opens
that ticket's detail view directly.

UI: a queue list (same search + filter-row + list card pattern as
every other dashboard's queue — Approval Queue, Validation Queue),
filterable by status and category. Tapping a ticket opens a detail
view: category/description/location/reporter, a status dropdown
(IT Technician moves it open → in progress → resolved, stamping
`resolved_at`/`resolved_by`), and the comment thread with a reply box.

### Report entry points (Teacher + Admin)

A shared `ReportTechnicalIssueDialog` widget built once in the
`dashboard_layout` package (alongside the other shared header widgets)
so Teacher and Admin both import the identical form instead of
duplicating it. Opened from a new wrench/tool header icon next to the
existing bell/mail icons in Teacher's dashboard header, and the
equivalent spot in Admin's header/sidebar. Fields: category dropdown,
location text field, description text field — submits via
`report_technical_issue`.

## Error handling

- RPC failures (network/RLS) surface as a snackbar/inline error on
  whichever dialog is open; form values are preserved, not cleared.
- Ticket list/detail use the same loading/empty/error triad already
  used elsewhere: skeleton while loading, an empty-state message when
  a filter yields zero tickets, a retry action on fetch failure.

## Testing

- Repository-level: `fetchPage`'s new `section`/search parameters, and
  the `report_technical_issue`/`add_technical_issue_comment` RPC
  wrappers, tested against this project's existing Supabase test
  setup (confirm exact harness during implementation).
- Widget-level: the danger-zone delete dialog only proceeds on the
  destructive button (not a generic tap); the skeleton-to-loaded
  transition swaps correctly once data arrives; year/course/section
  filter combinations produce the expected query parameters.

## Open items for the implementation plan

- Exact final module id / route naming for the renamed dashboard.
- Whether the existing `rfid_dashboard_page.dart`/`rfid_student_row.dart`
  are refactored in place or the new dashboard is built alongside and
  the old one deleted once parity is confirmed.
