-- Sample attendance for the Professor Dashboard's demo sections (the same
-- 5 sections add_professor_module_schema.sql assigns to the "Faculty
-- Member" demo professor: BSIT-1A, BSIT-2A, BSHM-1A, BSBA-1A, BSTM-1A).
--
-- Generates the last 10 weekdays of attendance for every student already
-- enrolled in those sections (from populate_mock_data.sql's 250 mock
-- students, or real enrollment if you have it), weighted mostly Present
-- with some Absent/Late so the dashboard's stat cards and per-student
-- table aren't all-100%/all-zero.
--
-- Idempotent: attendance_records has a unique (student_id, section_id,
-- session_date) constraint, so rerunning this is a no-op.
--
-- Run in Supabase SQL Editor, after add_professor_module_schema.sql and
-- populate_mock_data.sql (or any real student enrollment in those
-- sections).

do $$
declare
  v_professor_id uuid := '00000000-0000-4000-8000-000000000002';
  v_section record;
  v_student record;
  v_day date;
  v_roll numeric;
  v_status public.attendance_status;
  v_days_back int;
begin
  for v_section in
    select s.id, s.name
    from public.sections s
    join public.class_assignments ca on ca.section_id = s.id
    where ca.professor_id = v_professor_id
  loop
    for v_student in
      select id from public.students where section_id = v_section.id
    loop
      v_days_back := 0;
      v_day := current_date;
      while v_days_back < 14 loop
        -- Skip weekends; stop once 10 weekday sessions are generated.
        if extract(isodow from v_day) < 6 then
          v_roll := random();
          v_status := case
            when v_roll < 0.85 then 'Present'::public.attendance_status
            when v_roll < 0.93 then 'Late'::public.attendance_status
            else 'Absent'::public.attendance_status
          end;

          insert into public.attendance_records
            (student_id, section_id, session_date, status, recorded_by)
          values
            (v_student.id, v_section.id, v_day, v_status, v_professor_id)
          on conflict (student_id, section_id, session_date) do nothing;
        end if;

        v_day := v_day - 1;
        v_days_back := v_days_back + 1;
      end loop;
    end loop;
  end loop;
end $$;
