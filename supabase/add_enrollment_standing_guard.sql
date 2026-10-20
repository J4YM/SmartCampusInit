-- A sanction that bars re-admission (students.enrollment_standing =
-- 'Non_Readmission' or 'Dismissed', set by record_sanction) must actually stop
-- the student being enrolled again:
--
--   * enrollments BEFORE INSERT trigger  - no new Active class enrollment
--   * confirm_student_enrollment         - the Registrar's per-term
--                                          re-enrollment refuses restricted
--                                          students (an import just skips them)
--   * enroll_section_students            - the bulk section enroll skips them
--   * lift_enrollment_standing           - Admin-only, with a written reason,
--                                          for an appeal or a mistaken sanction
--
-- Run in Supabase SQL Editor after add_sanctions_schema.sql,
-- add_incident_report_classification.sql (log_audit) and
-- add_academic_term_migration.sql. Idempotent.

-- ---------------------------------------------------------------------------
-- Helper: the readable restriction text for a student, or null when fine.
-- ---------------------------------------------------------------------------

create or replace function public.enrollment_restriction(p_student_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case s.enrollment_standing
           when 'Non_Readmission' then
             p.first_name || ' ' || p.last_name
             || ' is marked Not for Readmission by Student Affairs and cannot be enrolled.'
           when 'Dismissed' then
             p.first_name || ' ' || p.last_name
             || ' has been dismissed and cannot be enrolled.'
           else null
         end
    from public.students s
    join public.profiles p on p.id = s.id
   where s.id = p_student_id;
$$;

revoke all on function public.enrollment_restriction(uuid) from public;
grant execute on function public.enrollment_restriction(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- enrollments: refuse a new Active enrollment for a restricted student.
-- ---------------------------------------------------------------------------

create or replace function public.trg_enrollment_standing_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
begin
  if new.status is distinct from 'Active' then
    return new;
  end if;
  v_reason := public.enrollment_restriction(new.student_id);
  if v_reason is not null then
    raise exception '% An administrator must lift the restriction first.', v_reason
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists enrollments_standing_guard on public.enrollments;
create trigger enrollments_standing_guard
  before insert or update of status on public.enrollments
  for each row execute function public.trg_enrollment_standing_guard();

-- ---------------------------------------------------------------------------
-- confirm_student_enrollment: same as before, plus the guard.
-- ---------------------------------------------------------------------------

create or replace function public.confirm_student_enrollment(
  p_student_ids uuid[],
  p_source text default 'registrar'
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_term uuid;
  v_count integer;
  v_id uuid;
  v_reason text;
  v_allowed uuid[] := '{}';
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Only the registrar may confirm enrollment.' using errcode = '42501';
  end if;

  if p_source not in ('registrar', 'import') then
    p_source := 'registrar';
  end if;

  foreach v_id in array coalesce(p_student_ids, '{}'::uuid[]) loop
    v_reason := public.enrollment_restriction(v_id);
    if v_reason is null then
      v_allowed := v_allowed || v_id;
    elsif p_source = 'registrar' then
      raise exception '% An administrator must lift the restriction first.', v_reason
        using errcode = 'P0001';
    end if;
    -- An import silently skips restricted students.
  end loop;

  select id into v_term from public.academic_terms where is_current;

  if v_term is not null then
    insert into public.student_term_enrollments (term_id, student_id, source)
    select v_term, s.id, p_source
      from public.students s
     where s.id = any (v_allowed)
    on conflict (term_id, student_id) do nothing;
  end if;

  update public.profiles
     set is_active = true
   where id = any (v_allowed)
     and is_active is distinct from true;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke all on function public.confirm_student_enrollment(uuid[], text) from public;
grant execute on function public.confirm_student_enrollment(uuid[], text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- enroll_section_students: skip restricted students.
-- ---------------------------------------------------------------------------

create or replace function public.enroll_section_students(
  p_class_section_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_section_id uuid;
  v_count int;
begin
  select section_id into v_section_id
    from public.class_sections
    where id = p_class_section_id;

  if v_section_id is null then
    raise exception 'Unknown class_sections id: %', p_class_section_id;
  end if;

  insert into public.enrollments (student_id, class_section_id)
  select s.id, p_class_section_id
    from public.students s
    where s.section_id = v_section_id
      and s.enrollment_standing = 'Good'
  on conflict (student_id, class_section_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.enroll_section_students(uuid) from public;
grant execute on function public.enroll_section_students(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- lift_enrollment_standing: Admin only, reason required.
-- ---------------------------------------------------------------------------

create or replace function public.lift_enrollment_standing(
  p_student_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() is distinct from 'Admin'::app_role then
    raise exception 'Only an administrator can lift an enrollment restriction.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'A reason is required to lift the restriction.';
  end if;

  update public.students
     set enrollment_standing = 'Good'
   where id = p_student_id and enrollment_standing <> 'Good';
  if not found then
    raise exception 'This student has no enrollment restriction.';
  end if;

  perform public.log_audit(
    'Lifted enrollment restriction: ' || btrim(p_reason), p_student_id::text, 'WARN');
end;
$$;

revoke all on function public.lift_enrollment_standing(uuid, text) from public;
grant execute on function public.lift_enrollment_standing(uuid, text) to authenticated;
