-- Attendance per class (subject), not just per section.
--
-- attendance_records was unique on (student_id, section_id, session_date), so a
-- section with several subjects could hold only one status per day. This adds
-- class_section_id (class_sections already carries subject + professor), so
-- "absent in which subject" and "earlier classes today" are answerable.
--
-- Legacy rows: backfilled where the section has exactly ONE class_sections
-- row. Rows in sections with several classes keep class_section_id = null;
-- they stay in the table (and in term archives) but per-class views ignore
-- them and the weekly SMS reports them as "a class".
--
-- Run in Supabase SQL Editor after add_professor_module_schema.sql and
-- add_subjects_enrollments_schema.sql. Idempotent.

alter table public.attendance_records
  add column if not exists class_section_id uuid
    references public.class_sections(id) on delete cascade;

-- Backfill: sections with exactly one class_sections row.
update public.attendance_records ar
   set class_section_id = one.id
  from (
    select section_id, (array_agg(id))[1] as id
      from public.class_sections
     group by section_id
    having count(*) = 1
  ) one
 where ar.class_section_id is null
   and ar.section_id = one.section_id;

-- Drop the old (student_id, section_id, session_date) unique constraint
-- whatever its auto-generated name is.
do $$
declare
  c record;
begin
  for c in
    select conname
      from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (student_id, section_id, session_date)'
  loop
    execute format('alter table public.attendance_records drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.attendance_records
  drop constraint if exists attendance_records_student_class_date_key;
alter table public.attendance_records
  add constraint attendance_records_student_class_date_key
  unique nulls not distinct (student_id, section_id, class_section_id, session_date);

create index if not exists attendance_records_class_date_idx
  on public.attendance_records (class_section_id, session_date);
