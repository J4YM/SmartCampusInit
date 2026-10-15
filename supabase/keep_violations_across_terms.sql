-- Violations carry over to the next academic term.
--
-- add_academic_term_migration.sql archived AND deleted student_violations
-- when a new term started. Disciplinary history should follow the student, so
-- this redefines the two functions involved:
--   * _term_archive_order: student_violations joins the protected list, so it
--     is never reached (or deleted) through a foreign key from another root;
--   * start_new_academic_term: student_violations is no longer an archive root.
-- Everything else is identical to add_academic_term_migration.sql.
--
-- Run in Supabase SQL Editor after add_academic_term_migration.sql.
-- Idempotent.

create or replace function public._term_archive_order(p_roots text[])
returns text[]
language sql
stable
set search_path = public, pg_temp
as $$
  with recursive protected(name) as (
    values ('students'), ('profiles'), ('sections'), ('subjects'),
           ('class_sections'), ('class_assignments'),
           ('class_section_meetings'), ('curriculum_entries'), ('rooms'),
           ('room_aliases'), ('program_aliases'), ('parent_student_links'),
           ('student_gpa_records'), ('audit_logs'), ('academic_terms'),
           ('student_term_enrollments'), ('term_archive_records'),
           ('rfid_readers'), ('id_card_templates'),
           ('student_violations')
  ),
  fk as (
    select c.conrelid::regclass::text as child,
           c.confrelid::regclass::text as parent
      from pg_constraint c
     where c.contype = 'f'
       and c.connamespace = 'public'::regnamespace
  ),
  walk(tbl, depth) as (
    select r, 0 from unnest(p_roots) r
    union
    select fk.child, w.depth + 1
      from walk w
      join fk on fk.parent = w.tbl
     where w.depth < 8
       and fk.child not in (select name from protected)
  )
  select coalesce(array_agg(tbl order by depth desc, tbl), '{}')
    from (select tbl, max(depth) as depth from walk group by tbl) t;
$$;

create or replace function public.start_new_academic_term(
  p_school_year text,
  p_term text,
  p_started_by text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old uuid;
  v_new uuid;
  v_table text;
  v_count bigint;
  v_archived jsonb := '{}'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_deactivated bigint;
  v_tables text[];
begin
  if auth.role() = 'authenticated' and current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may start a new academic term.' using errcode = '42501';
  end if;

  if coalesce(trim(p_school_year), '') = '' or coalesce(trim(p_term), '') = '' then
    raise exception 'School year and term are required.';
  end if;

  select id into v_old from public.academic_terms where is_current;

  if exists (
    select 1 from public.academic_terms
     where is_current
       and school_year = trim(p_school_year) and term = trim(p_term)
  ) then
    raise exception '% — % is already the current term.',
      trim(p_school_year), trim(p_term);
  end if;

  insert into public.academic_terms (school_year, term, is_current, started_by)
  values (trim(p_school_year), trim(p_term), false, p_started_by)
  returning id into v_new;

  -- student_violations is deliberately NOT a root: it carries over.
  v_tables := public._term_archive_order(array[
    'counseling_archive_logs', 'attendance_records',
    'grades', 'enrollments', 'escalation_reports', 'parent_interventions',
    'risk_assessments', 'student_referrals', 'admission_slips'
  ]);

  foreach v_table in array v_tables loop
    if to_regclass(v_table) is null then
      continue;
    end if;
    begin
      execute format(
        'insert into public.term_archive_records (term_id, source_table, row_data)
         select $1, %L, to_jsonb(t) from %s t', v_table, v_table)
        using coalesce(v_old, v_new);
      get diagnostics v_count = row_count;
      execute format('delete from %s where true', v_table);
      v_archived := v_archived || jsonb_build_object(replace(v_table, 'public.', ''), v_count);
    exception when others then
      v_skipped := v_skipped || to_jsonb(v_table || ': ' || sqlerrm);
    end;
  end loop;

  update public.academic_terms
     set is_current = false,
         closed_at = now(),
         archived_counts = v_archived
   where id = v_old;

  update public.academic_terms set is_current = true where id = v_new;

  update public.profiles p
     set is_active = false
   where p.role = 'Student'::app_role
     and p.is_active is distinct from false;
  get diagnostics v_deactivated = row_count;

  return jsonb_build_object(
    'term_id', v_new,
    'archived', v_archived,
    'skipped', v_skipped,
    'students_deactivated', v_deactivated
  );
end;
$$;
