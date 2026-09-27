-- Scheduling Officer role — the person who receives the Confirmation of
-- Faculty Loading (CFL) and Room Schedule files from the school and turns
-- them into the finished per-section Class Schedule. See
-- docs/superpowers/specs/2026-09-16-registrar-batch-schedule-import-design.md
-- for the original plan, and docs/superpowers/specs/2026-09-21-scheduling-
-- officer-dashboard-design.md for what actually shipped.
--
-- Run in Supabase SQL Editor, after add_schedule_import_commit_support.sql.
-- Idempotent: safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. New role value on the shared app_role enum.
--
-- IMPORTANT — do not remove the `commit;`/`begin;` pair below. PostgreSQL
-- refuses to *use* an enum value added by the current, still-open
-- transaction (SQLSTATE 55P04, "unsafe use of new value ... of enum type
-- app_role"), and the Supabase SQL Editor runs a pasted multi-statement
-- script as ONE implicit transaction. Everything after this point casts to
-- 'Scheduling_Officer'::app_role, so the enum addition has to be committed
-- on its own first (same shape as add_it_technician_schema.sql's own
-- role addition).
-- ---------------------------------------------------------------------------

alter type public.app_role add value if not exists 'Scheduling_Officer';

commit;
begin;

-- ---------------------------------------------------------------------------
-- 2. Widen the existing Registrar-only write policies this role also needs.
-- add_class_section_meetings_schema.sql's own comment already flagged this
-- as a follow-up: "a later plan adds 'Scheduling_Officer'::app_role to this
-- policy alongside introducing that role."
-- ---------------------------------------------------------------------------

drop policy if exists "class_section_meetings_write" on public.class_section_meetings;
create policy "class_section_meetings_write"
on public.class_section_meetings for all
to authenticated
using (current_user_role() in (
  'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
))
with check (current_user_role() in (
  'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
));

drop policy if exists "class_sections_registrar_insert" on public.class_sections;
create policy "class_sections_registrar_insert"
on public.class_sections for insert
to authenticated
with check (current_user_role() in (
  'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
));

-- ---------------------------------------------------------------------------
-- 3. subjects/sections have never had an INSERT policy at all — only SELECT
-- (add_subjects_enrollments_schema.sql, rls_sections_select.sql). This was
-- never hit before because the only import path exercised so far (the
-- Registrar's Classes+Professor list) either matches an existing subject by
-- code or throws asking for one — it never silently created a new subjects/
-- sections row. CFL/Room Schedule import (ScheduleImportRepository.
-- resolveSubjectId/resolveSectionId) does create new rows when nothing
-- matches, for both Registrar and Scheduling Officer, so both need this.
-- ---------------------------------------------------------------------------

drop policy if exists "subjects_staff_insert" on public.subjects;
create policy "subjects_staff_insert"
on public.subjects for insert
to authenticated
with check (current_user_role() in (
  'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
));

drop policy if exists "sections_staff_insert" on public.sections;
create policy "sections_staff_insert"
on public.sections for insert
to authenticated
with check (current_user_role() in (
  'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
));

-- ---------------------------------------------------------------------------
-- 4. ScheduleImportRepository.resolveProfessorId auto-creates a stub
-- professor for a recognized placeholder name (e.g. "New IT Faculty 2",
-- status 'Placeholder') AND, as of the fix for the Classes+Professor
-- list's roster-upload flow, for any real professor named with a real
-- Instructor ID that doesn't match an existing profile (status 'approved'
-- — they're a real, already-employed professor, not an unfilled slot).
--
-- This can't be a plain client-side `insert into profiles` (an earlier
-- version of this file tried that): `profiles.id` has no default and is
-- tied 1:1 to an `auth.users` row throughout this codebase (every other
-- profiles insert in supabase/*.sql, e.g. add_it_technician_schema.sql's
-- demo seed, creates both rows together) — a bare profiles insert with no
-- id fails NOT NULL, and a client-supplied random id would have no
-- matching auth.users row. Anon/authenticated callers also can't insert
-- into `auth.users` directly (outside PostgREST's exposed schema). A
-- `security definer` function is the one way to do both writes from a
-- single client-side RPC call. Scoped tight regardless: it only ever
-- creates a Teacher row in one of the two statuses above, nothing else.
-- ---------------------------------------------------------------------------

drop policy if exists "profiles_staff_insert_placeholder_professor" on public.profiles;
drop policy if exists "profiles_staff_insert_auto_professor" on public.profiles;

create or replace function public.create_auto_professor_profile(
  p_employee_id text,
  p_full_name text,
  p_is_placeholder boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  -- Human-readable, kept on public.profiles.email only (see below) — NOT
  -- on auth.users.email, which drives handle_new_auth_user()
  -- (add_oauth_role_approval_schema.sql): that trigger raises an
  -- exception for any non-anonymous auth.users insert whose email isn't
  -- an exact `...@baliuag.sti.edu.ph` match, which this synthetic address
  -- deliberately isn't. Marking this row is_anonymous (below) makes the
  -- trigger skip entirely instead — the same bypass real anonymous
  -- student-registration sign-ins already rely on elsewhere in this
  -- schema — so auth.users.email is left null, matching that trigger's
  -- own "anonymous sign-ins ... have no email" comment.
  v_email text := 'auto.professor.' || v_id::text || '@placeholder.baliuag.sti.edu.ph';
  v_status public.approval_status;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to auto-create a professor profile.';
  end if;

  v_status := case when p_is_placeholder
    then 'Placeholder'::approval_status
    else 'approved'::approval_status
  end;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    -- '' not crypt(...)/gen_salt('bf'): pgcrypto installs into Supabase's
    -- `extensions` schema, not `public` — this function's own `set
    -- search_path = public` (needed so unqualified calls like
    -- current_user_role() below resolve correctly) makes gen_salt/crypt
    -- invisible to it even with the extension enabled (42883, "function
    -- gen_salt(unknown) does not exist"). A real password hash serves no
    -- purpose here anyway: this row is is_anonymous and never meant to
    -- authenticate, matching how Supabase's own anonymous sign-ins leave
    -- encrypted_password as ''.
    v_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    null, '', now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, true, now(), now()
  );

  insert into public.profiles (
    id, email, first_name, last_name, employee_id, role, status, created_at
  )
  values (
    v_id, v_email, p_full_name, '', p_employee_id, 'Teacher'::app_role, v_status, now()
  );

  return v_id;
end;
$$;

revoke all on function public.create_auto_professor_profile(text, text, boolean) from public;
grant execute on function public.create_auto_professor_profile(text, text, boolean)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Anon equivalents of (3) — every demo account (lib/auth/
-- static_demo_accounts.dart, including the new scheduling.demo) is a purely
-- client-side check with no real Supabase Auth session, same reasoning as
-- add_schedule_import_commit_support.sql's anon policies. Without these, a
-- demo-account CFL/Room Schedule upload that needs to create a new subject
-- or section silently writes nothing. (profiles no longer needs an anon
-- insert policy here — (4)'s function is granted to anon directly and
-- bypasses RLS via security definer.) Tighten before production the same
-- way that file already flags.
-- ---------------------------------------------------------------------------

drop policy if exists "subjects_anon_insert" on public.subjects;
create policy "subjects_anon_insert"
on public.subjects for insert
to anon
with check (true);

drop policy if exists "sections_anon_insert" on public.sections;
create policy "sections_anon_insert"
on public.sections for insert
to anon
with check (true);

drop policy if exists "profiles_anon_insert_placeholder_professor" on public.profiles;
drop policy if exists "profiles_anon_insert_auto_professor" on public.profiles;

commit;
