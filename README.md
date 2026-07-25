# STI Baliuag — Integrated Attendance & Discipline Monitoring System

A Flutter (web + Windows desktop) capstone project for STI College Baliuag,
backed by Supabase (Postgres + Auth + Row Level Security). It ties together
RFID-based campus attendance, discipline/violation tracking, an admin
dashboard, and role-specific portals behind a single Microsoft (Azure AD)
sign-in.

## What's in this repo

The root app (`lib/`) is the shell: authentication, session/role routing, and
an admin hub that opens each module. The modules themselves live as
independent packages under `packages/`, wired to Supabase from the root app
rather than depending on it directly.

| Package | Purpose |
| --- | --- |
| `login_module` | Sign-in screen UI (username/password + "Sign in with Microsoft"). |
| `admin_dashboard` | Admin shell: System Overview, Student Directory, RFID Mapping, Staff Accounts, ML Thresholds, Notifications, Reports & Exports, Audit Logs. |
| `rfid_management_module` | RFID card issuance UI used by the RFID Office to pre-register students and link card UIDs. |
| `discipline_officer_module` | Discipline Officer dashboard: violation approval queue, Good Moral / clearance requests, student directory. |
| `virtual_admission_slip` | Generated admission-slip view (QR-based gate/room admission). |
| `kiosk_home` / `student_kiosk_module` | Kiosk-mode entry points for gate/room scanning and student self-service. |

Supported roles (`app_role` in Postgres, `AppRole` in Dart): Admin, Student,
Parent, Teacher, Registrar, Guidance Counselor, Discipline Officer, Security.
Which modules a role can open is defined in `lib/modules/module_access.dart`.

## Authentication

Two sign-in paths feed the same [`SessionController`](lib/app/session_controller.dart):

1. **Microsoft (Azure AD) OAuth**, gated to `@baliuag.sti.edu.ph` accounts by
   the `handle_new_auth_user` Postgres trigger
   (`supabase/add_oauth_role_approval_schema.sql`), which classifies every
   new sign-in by email pattern:
   - `lastname.123456@baliuag.sti.edu.ph` → a **Student** profile, approved
     immediately. Since a `students` row (course/year/section) can't be
     inferred from an email address, first sign-in routes to
     [`StudentRegistrationGatePage`](lib/ui/student_registration_gate_page.dart),
     which either:
     - shows a short registration form (name, course, year, section) that
       creates the record — the student number itself is fixed server-side
       from the verified school email, never taken from the form; or
     - if the RFID Office already pre-registered that student number (see
       below), prompts the student to **claim** that existing record instead
       of creating a duplicate.
     Either way, an RFID card is linked afterward by an admin from the RFID
     Mapping page.
   - `firstname.lastname@baliuag.sti.edu.ph` → a staff profile, created
     `pending` with no role. An admin assigns a role and approves it from
     the **Staff Accounts** page (`awaiting_approval_page.dart` is shown to
     the staff member in the meantime).
   - Anything else is rejected at sign-in.
2. **Static demo accounts** (`lib/auth/static_demo_accounts.dart`) — fixed
   username/password pairs, one per role, for local development and demos
   without touching Supabase Auth at all.

Separately, the **RFID Management module** pre-registers students via
anonymous Supabase sign-ins (`StudentsRepository.create()`), so a student can
have an RFID card and attendance record before ever signing in themselves —
that's what the claim flow above reconciles once they do.

See `supabase/add_student_self_registration_schema.sql` for the
`complete_student_registration` / `claim_preregistered_student` RPCs behind
this flow.

## Getting started

1. **Install dependencies**

   ```bash
   flutter pub get
   ```

2. **Configure Supabase**

   Copy `.env.example` to `.env` in the project root and fill in your
   project's values (anon/public key only — never a service role key in a
   client app):

   ```
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key
   PROFILE_ROLE_STUDENT=Student
   ```

   `.env` is bundled as a web asset (see `pubspec.yaml`), so it must exist
   before `flutter run -d chrome`. `--dart-define` / `--dart-define-from-file`
   (see `supabase_dart_defines.json.example`) work as an alternative for CI
   or desktop builds.

3. **Apply the database schema**

   Run the SQL files in `supabase/` against your Supabase project (SQL
   Editor → paste → Run), in this order:

   1. Your base schema for `profiles`, `students`, `sections`,
      `parent_student_links`, `student_violations`, the `app_role` enum, and
      `current_user_role()` (created directly in the Supabase dashboard for
      this project; not versioned here yet).
   2. `add_oauth_role_approval_schema.sql` — Microsoft OAuth classification,
      staff approval queue, RFID card linking.
   3. `add_admin_dashboard_schema.sql` — staff profile fields + `audit_logs`.
   4. `add_discipline_officer_schema.sql`, `add_good_moral_requests_schema.sql`
      — Discipline Officer dashboard fields and the Good Moral request queue.
   5. `add_student_self_registration_schema.sql` — student self-registration
      + "claim my record" RPCs.
   6. `seed_sections.sql`, `rls_sections_select.sql`,
      `rls_student_self_insert.sql`, `rls_students_list_anon.sql`,
      `rls_discipline_demo_anon.sql` — section seed data and the RLS
      policies the RFID/admin/Discipline Officer modules need. The last one
      specifically covers `student_violations`/`good_moral_requests`/
      `handbook_offenses`/`profiles` for the static demo accounts (see
      `lib/auth/static_demo_accounts.dart`), which never establish a real
      Supabase session — without it, those tables look empty in the DO
      Dashboard and Admin Overview even when populated, since the
      role-gated policies on them key off `auth.uid()`.

   Then, optionally, `supabase/populating/populate_mock_data.sql` and
   `supabase/populating/populate_violations_and_good_moral.sql` to fill the
   dashboards with sample data for development (see below).

4. **Run the app**

   ```bash
   flutter run -d chrome    # web (recommended for this layout)
   flutter run -d windows   # Windows desktop, if enabled in your SDK
   ```

## Sample / mock data for development

`supabase/populating/populate_mock_data.sql` seeds a self-contained batch of
realistic-looking data — a few hundred students across all four programs and
year levels, sections, staff accounts (approved and pending), RFID gate scan
history, violations, Good Moral requests, and audit log entries — so every
dashboard has something to render without waiting on real enrollment or
hardware. It's idempotent (safe to re-run) and tags every row it creates so
it can be identified/cleaned up later; see the comments at the top of the
file for details and adjust any column names there to match your actual
`student_violations` schema if it differs.

## Deployment

`netlify.toml` + `scripts/netlify_build.sh` build the Flutter web target for
Netlify. Set `SUPABASE_URL` / `SUPABASE_ANON_KEY` (and optionally
`PROFILE_ROLE_STUDENT`) as Netlify build environment variables.

## Project layout

- `lib/main.dart` — app entry point, theme, Supabase initialization, and
  post-login routing per role.
- `lib/app/session_controller.dart` — auth/session state machine (signed
  out, awaiting staff approval, awaiting student setup, signed in).
- `lib/data/`, `lib/models/` — Supabase repositories and row models shared
  across the root app's connected pages.
- `lib/ui/admin/*_connected_page.dart` — wires the presentation-only pages
  in `packages/admin_dashboard` to Supabase via those repositories.
- `packages/*` — independently runnable/demoable UI packages (see table
  above).
- `supabase/` — SQL schema migrations, RLS policies, and seed/mock data.
