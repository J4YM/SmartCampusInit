-- Two Registrar fixes. Run in Supabase SQL Editor. Idempotent: safe to re-run.
--
-- 1. students.enrollment_year was only ever backfilled once (see
--    add_students_enrollment_year.sql); students created afterwards — batch
--    upload, Add New Student, self-registration — kept it NULL, so the
--    Overview tab's "New Students" never listed them. A BEFORE INSERT trigger
--    now fills it from the student's year level (same formula as that
--    backfill: this year for a 1st-year, one year earlier per level above),
--    and the existing NULL rows are backfilled again.
--
-- 2. update_student_guardian_email: lets the Registrar correct a guardian's
--    email from Edit Student. The email is also the guardian's Parent Portal
--    username (parent_credentials.email), so both are changed together and
--    the guardian's current password keeps working. A guardian shared by
--    siblings changes for all of them — it is one account.

-- ---------------------------------------------------------------------------
-- 1. enrollment_year default
-- ---------------------------------------------------------------------------

create or replace function public.students_set_enrollment_year()
returns trigger
language plpgsql
as $$
begin
  if new.enrollment_year is null then
    new.enrollment_year := extract(year from now())::int
      - (coalesce(new.year_level, 1) - 1);
  end if;
  return new;
end;
$$;

drop trigger if exists students_set_enrollment_year on public.students;
create trigger students_set_enrollment_year
  before insert on public.students
  for each row execute function public.students_set_enrollment_year();

update public.students s
set enrollment_year = extract(year from now())::int
  - (coalesce(s.year_level, sec.year_level, 1) - 1)
from public.sections sec
where s.section_id = sec.id
  and s.enrollment_year is null;

-- ---------------------------------------------------------------------------
-- 2. update_student_guardian_email
-- ---------------------------------------------------------------------------

create or replace function public.update_student_guardian_email(
  p_student_id uuid,
  p_email text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_parent_id uuid;
  v_clash uuid;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to change a guardian email.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Enter a valid guardian email address.';
  end if;

  select l.parent_id
    into v_parent_id
    from public.parent_student_links l
    join public.profiles p on p.id = l.parent_id
   where l.student_id = p_student_id
     and p.role = 'Parent'::app_role
   limit 1;

  if v_parent_id is null then
    return 'no_guardian';
  end if;

  select id into v_clash
    from public.profiles
   where lower(email) = v_email and id <> v_parent_id
   limit 1;
  if v_clash is not null then
    raise exception 'That email is already used by another account.';
  end if;

  update public.profiles set email = v_email where id = v_parent_id;
  update public.parent_credentials
     set email = v_email, updated_at = now()
   where parent_id = v_parent_id;

  return 'updated';
end;
$$;

revoke all on function public.update_student_guardian_email(uuid, text) from public;
grant execute on function public.update_student_guardian_email(uuid, text)
  to anon, authenticated;
