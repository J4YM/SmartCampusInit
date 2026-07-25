-- Self-service student registration + "claim my pre-registered record" flow
-- for Microsoft (Azure AD) sign-ins that resolve to a Student profile via
-- `handle_new_auth_user` (see add_oauth_role_approval_schema.sql).
--
-- Context: `handle_new_auth_user` inserts a `profiles` row for a
-- student-pattern email (e.g. cruz.204890@baliuag.sti.edu.ph) but does NOT
-- create a matching `students` row — there's no course/year/section to infer
-- from an email address alone. Two situations follow from that gap, both
-- handled by the RPCs below (called from the Flutter student-setup gate,
-- lib/ui/student_registration_gate_page.dart, the first time such a profile
-- signs in):
--
--   1. No `students` row exists yet for this student number anywhere — the
--      student fills in a short registration form (name, course, year,
--      section) and `complete_student_registration` creates it. The student
--      number itself is never taken from the form — it's re-derived from the
--      caller's own verified `profiles.email` (set by the trigger from their
--      actual Microsoft account), so it can only ever be the number embedded
--      in the account they signed in with, never an arbitrary client value.
--
--   2. A `students` row already exists for that number — most likely because
--      the RFID Management module (anonymous sign-in path,
--      `StudentsRepository.create()` in lib/data/students_repository.dart)
--      pre-registered the student before they ever signed in with Microsoft.
--      `claim_preregistered_student` re-homes that record onto the caller's
--      real, Microsoft-linked profile, then deletes the old anonymous one.
--      It refuses to touch a record that's already linked to a
--      *non-anonymous* account, so one Microsoft sign-in can never hijack a
--      student number another real account has already claimed.
--
-- Known limitation: claiming deletes the old (anonymous) `students`/
-- `profiles` rows outright, which cascades to anything already recorded
-- against that row (e.g. `student_violations`, `good_moral_requests`) per
-- their existing FK constraints. This is expected to be a no-op in practice
-- — a pre-registered record with no Microsoft sign-in yet should have no
-- history — but adjust here if your deployment ever pre-loads history
-- against unclaimed records.
--
-- Run in Supabase SQL Editor, after add_oauth_role_approval_schema.sql.

-- ---------------------------------------------------------------------------
-- 0. Natural-key guard: at most one `students` row per student number.
-- ---------------------------------------------------------------------------
do $$ begin
  alter table public.students
    add constraint students_student_number_key unique (student_number);
exception
  when duplicate_object or duplicate_table then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Shared helper — pulls the 6-digit student number out of a verified
--    @baliuag.sti.edu.ph student-pattern email. Mirrors the regex in
--    `handle_new_auth_user`; always derive the number this way server-side
--    rather than trusting one supplied by the client.
-- ---------------------------------------------------------------------------
create or replace function public._student_number_from_email(p_email text)
returns text
language sql
immutable
as $$
  select substring(lower(trim(p_email)) from '\.([0-9]{6})@baliuag\.sti\.edu\.ph$');
$$;

-- ---------------------------------------------------------------------------
-- 2. First-login self-registration
-- ---------------------------------------------------------------------------
create or replace function public.complete_student_registration(
  p_first_name text,
  p_middle_initial text,
  p_last_name text,
  p_course text,
  p_year_level int,
  p_section_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_email text;
  v_role public.app_role;
  v_student_number text;
  v_composed_first text;
begin
  if v_caller is null then
    raise exception 'Not authenticated.';
  end if;

  select email, role into v_email, v_role
    from public.profiles where id = v_caller;

  if v_role is distinct from 'Student'::public.app_role then
    raise exception 'Only student accounts can self-register.';
  end if;

  if exists (select 1 from public.students where id = v_caller) then
    raise exception 'This account already has a linked student record.';
  end if;

  v_student_number := public._student_number_from_email(v_email);
  if v_student_number is null then
    raise exception 'Could not determine a student number from %.', v_email;
  end if;

  if exists (select 1 from public.students where student_number = v_student_number) then
    raise exception 'Student number % is already registered. Use "Claim my record" instead.', v_student_number
      using errcode = 'P0002';
  end if;

  if not exists (select 1 from public.sections where id = p_section_id) then
    raise exception 'Unknown section.';
  end if;

  v_composed_first := trim(p_first_name) ||
    case when trim(p_middle_initial) = '' then ''
         else ' ' || upper(trim(p_middle_initial)) || '.' end;

  update public.profiles
    set first_name = v_composed_first, last_name = trim(p_last_name)
    where id = v_caller;

  insert into public.students (id, student_number, course, year_level, section_id)
  values (v_caller, v_student_number, p_course, p_year_level, p_section_id);
end;
$$;

revoke all on function public.complete_student_registration(text, text, text, text, int, uuid) from public;
grant execute on function public.complete_student_registration(text, text, text, text, int, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Claim a pre-registered (RFID-Manager-created) record
-- ---------------------------------------------------------------------------
create or replace function public.claim_preregistered_student()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_email text;
  v_role public.app_role;
  v_student_number text;
  v_old_id uuid;
  v_old_is_anonymous boolean;
  v_old_rfid_uid text;
  v_old_course text;
  v_old_year_level int;
  v_old_section_id uuid;
  v_old_first_name text;
  v_old_last_name text;
begin
  if v_caller is null then
    raise exception 'Not authenticated.';
  end if;

  select email, role into v_email, v_role
    from public.profiles where id = v_caller;

  if v_role is distinct from 'Student'::public.app_role then
    raise exception 'Only student accounts can claim a pre-registered record.';
  end if;

  if exists (select 1 from public.students where id = v_caller) then
    raise exception 'This account already has a linked student record.';
  end if;

  v_student_number := public._student_number_from_email(v_email);
  if v_student_number is null then
    raise exception 'Could not determine a student number from %.', v_email;
  end if;

  select s.id, s.rfid_uid, s.course, s.year_level, s.section_id,
         p.first_name, p.last_name
    into v_old_id, v_old_rfid_uid, v_old_course, v_old_year_level, v_old_section_id,
         v_old_first_name, v_old_last_name
    from public.students s
    join public.profiles p on p.id = s.id
    where s.student_number = v_student_number;

  if v_old_id is null then
    raise exception 'No pre-registered record found for student number %.', v_student_number
      using errcode = 'P0004';
  end if;

  select u.is_anonymous into v_old_is_anonymous
    from auth.users u where u.id = v_old_id;

  if coalesce(v_old_is_anonymous, false) is not true then
    raise exception 'Student number % is already linked to another account.', v_student_number;
  end if;

  -- Delete the old (anonymous-auth) rows first so the unique constraints on
  -- `rfid_uid`/`student_number` are free before the new ones are written
  -- (explicit child-then-parent order, independent of whatever ON DELETE
  -- behavior the base schema happens to use between these two tables).
  delete from public.students where id = v_old_id;
  delete from public.profiles where id = v_old_id;

  insert into public.students (id, student_number, rfid_uid, course, year_level, section_id)
  values (v_caller, v_student_number, v_old_rfid_uid, v_old_course, v_old_year_level, v_old_section_id);

  update public.profiles
    set first_name = coalesce(nullif(trim(v_old_first_name), ''), first_name),
        last_name = coalesce(nullif(trim(v_old_last_name), ''), last_name)
    where id = v_caller;
end;
$$;

revoke all on function public.claim_preregistered_student() from public;
grant execute on function public.claim_preregistered_student() to authenticated;
