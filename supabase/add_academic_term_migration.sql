-- Academic term migration: lets the Admin close the current school year /
-- semester and start a new one.
--
-- Starting a new term (start_new_academic_term):
--   1. closes the current term and opens the new one;
--   2. SNAPSHOTS the closed term's records into term_archive_records (one
--      jsonb row per source row, tagged with the term) and then removes them
--      from the live tables so every dashboard starts the new term clean;
--   3. deactivates every Student account (profiles.is_active = false) so
--      nobody signs in until they are confirmed as enrolled.
--
-- A student is re-activated when EITHER
--   * the Registrar confirms them (Student Profile -> Confirm Enrollment), or
--   * they appear in a batch enrollment upload (EnrollmentImportRepository)
-- — both call confirm_student_enrollment(), which records the confirmation
-- in student_term_enrollments and flips is_active back on.
--
-- Tables archived: the roots below plus, automatically, every table that has
-- a foreign key pointing at them (found from pg_constraint, children first,
-- so deletes never trip a foreign key). Roots:
--   student_violations, counseling_archive_logs, attendance_records, grades,
--   enrollments, escalation_reports, parent_interventions, risk_assessments,
--   student_referrals, admission_slips.
-- Dependency discovery never walks through (or deletes from) the protected
-- list in _term_archive_order(), so a dependent can't drag students, staff
-- or the schedule into the purge. Each table runs in its own savepoint: if
-- one still can't be cleared its snapshot is rolled back and it is listed
-- under "skipped" with the database's reason.
-- Not touched: students, profiles (other than is_active), sections,
-- subjects, class_sections, curriculum, student_gpa_records (already
-- per-term).
--
-- Like the rest of the demo environment (rls_discipline_demo_anon.sql) the
-- admin console can be signed in through a static demo account that talks to
-- the database as `anon`, so these objects are open to anon + authenticated.
--
-- Run in Supabase SQL Editor after add_subjects_enrollments_schema.sql.
-- Idempotent.

create table if not exists public.academic_terms (
  id uuid primary key default gen_random_uuid(),
  school_year text not null,
  term text not null,
  is_current boolean not null default false,
  started_at timestamptz not null default now(),
  closed_at timestamptz,
  started_by text,
  archived_counts jsonb
);

-- At most one current term.
create unique index if not exists academic_terms_one_current
  on public.academic_terms ((true)) where is_current;

create table if not exists public.student_term_enrollments (
  term_id uuid not null references public.academic_terms(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  source text not null default 'registrar'
    check (source in ('registrar', 'import')),
  confirmed_at timestamptz not null default now(),
  primary key (term_id, student_id)
);

create table if not exists public.term_archive_records (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references public.academic_terms(id) on delete cascade,
  source_table text not null,
  row_data jsonb not null,
  archived_at timestamptz not null default now()
);

create index if not exists term_archive_records_term_idx
  on public.term_archive_records (term_id, source_table);

alter table public.academic_terms enable row level security;
alter table public.student_term_enrollments enable row level security;
alter table public.term_archive_records enable row level security;

drop policy if exists "academic_terms_all" on public.academic_terms;
create policy "academic_terms_all" on public.academic_terms
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "student_term_enrollments_all" on public.student_term_enrollments;
create policy "student_term_enrollments_all" on public.student_term_enrollments
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "term_archive_records_select" on public.term_archive_records;
create policy "term_archive_records_select" on public.term_archive_records
  for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- _term_archive_order: the roots plus everything that references them,
-- children first.
-- ---------------------------------------------------------------------------

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
           ('rfid_readers'), ('id_card_templates')
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
-- ---------------------------------------------------------------------------
-- start_new_academic_term
-- ---------------------------------------------------------------------------

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

  -- Archive under the closing term, or under the new one on first use (no
  -- term has ever been started, so there is nothing "closed" to tag).
  insert into public.academic_terms (school_year, term, is_current, started_by)
  values (trim(p_school_year), trim(p_term), false, p_started_by)
  returning id into v_new;

  -- Children before parents so deletes don't trip foreign keys.
  v_tables := public._term_archive_order(array[
    'student_violations', 'counseling_archive_logs', 'attendance_records',
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
      -- "where true": API roles run with pg_safeupdate, which rejects a bare DELETE.
      execute format('delete from %s where true', v_table);
      v_archived := v_archived || jsonb_build_object(replace(v_table, 'public.', ''), v_count);
    exception when others then
      -- The block is its own savepoint: the snapshot above is rolled back.
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

-- ---------------------------------------------------------------------------
-- confirm_student_enrollment — Registrar action and import hook
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
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Only the registrar may confirm enrollment.' using errcode = '42501';
  end if;

  if p_source not in ('registrar', 'import') then
    p_source := 'registrar';
  end if;

  select id into v_term from public.academic_terms where is_current;

  if v_term is not null then
    insert into public.student_term_enrollments (term_id, student_id, source)
    select v_term, s.id, p_source
      from public.students s
     where s.id = any (p_student_ids)
    on conflict (term_id, student_id) do nothing;
  end if;

  update public.profiles
     set is_active = true
   where id = any (p_student_ids)
     and is_active is distinct from true;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke all on function public.start_new_academic_term(text, text, text) from public;
grant execute on function public.start_new_academic_term(text, text, text)
  to anon, authenticated;

revoke all on function public.confirm_student_enrollment(uuid[], text) from public;
grant execute on function public.confirm_student_enrollment(uuid[], text)
  to anon, authenticated;
