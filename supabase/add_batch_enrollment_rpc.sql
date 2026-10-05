-- Replaces the batch-enrollment flow's use of signInAnonymously() (one
-- real HTTP call to Supabase's GoTrue Auth service per new student, and
-- again per new guardian) with two `security definer` RPCs that insert
-- directly into `auth.users` + `public.profiles` (+ `public.students` for
-- the student one) in a single Postgres transaction — exactly the same
-- technique `create_auto_professor_profile` already uses
-- (add_scheduling_officer_role.sql) and for the identical underlying
-- reason (see that function's own doc comment): `profiles.id`/
-- `students.id` have no default and are tied 1:1 to a real `auth.users`
-- row throughout this schema, and anon/authenticated callers can't insert
-- into `auth.users` directly from a client app. A `security definer`
-- function is the one way to do all of those writes from a single
-- client-side RPC call, and because it's a plain SQL insert — not an
-- HTTP call to GoTrue's /signup endpoint — it is NOT subject to
-- Supabase Auth's anonymous-sign-in rate limit.
--
-- That rate limit (commonly ~30/hour on a default project) is exactly
-- what made a batch of ~500 students stall after only 9-16 successes:
-- every new student AND every new guardian each fired their own
-- signInAnonymously() call, sequentially, with no way around the limit
-- from the client. See EnrollmentImportRepository.upsertStudent/
-- _linkGuardian in lib/data/enrollment_import_repository.dart, which this
-- migration's RPCs are called from instead.
--
-- Run in Supabase SQL Editor, after add_scheduling_officer_role.sql
-- (for current_user_role()) and add_subjects_enrollments_schema.sql
-- (for public.students/public.profiles).

create or replace function public.create_batch_student_account(
  p_student_number text,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_course text,
  p_year_level int,
  p_section_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to batch-create a student account.';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    -- '' not a real password hash: this row is_anonymous and never meant
    -- to authenticate directly — same reasoning
    -- create_auto_professor_profile's own comment gives for the same
    -- literal. is_anonymous = true is also what
    -- claim_preregistered_student (add_student_self_registration_schema.sql)
    -- checks for before letting a real Microsoft sign-in take over this
    -- placeholder row later.
    v_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    null, '', now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, true, now(), now()
  );

  insert into public.profiles (id, first_name, last_name, role, email, created_at)
  values (v_id, p_first_name, p_last_name, 'Student'::app_role, p_email, now());

  insert into public.students (id, student_number, course, year_level, section_id)
  values (v_id, p_student_number, p_course, p_year_level, p_section_id);

  return v_id;
end;
$$;

revoke all on function public.create_batch_student_account(text, text, text, text, text, int, uuid) from public;
grant execute on function public.create_batch_student_account(text, text, text, text, text, int, uuid)
  to anon, authenticated;

create or replace function public.create_batch_guardian_account(
  p_email text,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_first_name text := case
    when p_name is not null and p_name <> '' then p_name
    else 'Guardian'
  end;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to batch-create a guardian account.';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    v_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    null, '', now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, true, now(), now()
  );

  insert into public.profiles (id, first_name, last_name, role, email, created_at)
  values (v_id, v_first_name, '', 'Parent'::app_role, p_email, now());

  return v_id;
end;
$$;

revoke all on function public.create_batch_guardian_account(text, text) from public;
grant execute on function public.create_batch_guardian_account(text, text)
  to anon, authenticated;
