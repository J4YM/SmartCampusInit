-- Run AFTER add_attendance_per_class_section.sql and add_weekly_absence_sms.sql.
-- Rollback-only: leaves no data behind. Every `do` block raises on failure.
begin;

-- A. attendance_records has class_section_id and the new unique key.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'attendance_records'
       and column_name = 'class_section_id'
  ) then
    raise exception 'FAIL A1: attendance_records.class_section_id missing';
  end if;

  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (student_id, section_id, session_date)'
  ) then
    raise exception 'FAIL A2: old unique (student_id, section_id, session_date) still present';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) like '%class_section_id%session_date%'
  ) then
    raise exception 'FAIL A3: new unique key missing';
  end if;
end $$;

rollback;
