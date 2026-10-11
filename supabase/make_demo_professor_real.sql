-- Turns the `teacher.demo` account's profile into a real-looking professor
-- with real subjects.
--
-- Until now the demo professor was "Faculty Member" with only section
-- assignments (class_assignments) and no classes at all, so its Subjects /
-- Class Schedule / attendance views were empty and it could not be picked as a
-- professor on the kiosk in any believable way. This gives it:
--   * a real name and Employee ID (the kiosk professor picker lists every
--     non-placeholder Teacher, so it now appears there under that name);
--   * two real curriculum subjects per assigned section (class_sections),
--     matched on the section's program and year level.
--
-- The profile id is the fixed one seeded by add_professor_module_schema.sql
-- and referenced by lib/ui/professor_connected_page.dart — unchanged.
--
-- Run in Supabase SQL Editor after add_professor_module_schema.sql,
-- add_subjects_enrollments_schema.sql and seed_curriculum_subjects.sql.
-- Idempotent.

do $$
declare
  v_prof uuid := '00000000-0000-4000-8000-000000000002';
  v_year text;
  v_term text;
begin
  update public.profiles
     set first_name = 'Ramon',
         last_name = 'Villanueva',
         employee_id = coalesce(employee_id, 'DEMO-PROF-0001'),
         department = 'Information Technology',
         is_active = true
   where id = v_prof;

  -- name_key exists only once add_professor_identity_override.sql has run.
  if to_regproc('public.professor_name_key(text)') is not null then
    execute 'update public.profiles set name_key = public.professor_name_key($1) where id = $2'
      using 'Ramon Villanueva', v_prof;
  end if;

  -- Same school year / term as the rest of the schedule when there is one.
  select school_year, term into v_year, v_term
    from public.class_sections
   order by created_at desc
   limit 1;
  v_year := coalesce(v_year, '2026-2027');
  v_term := coalesce(v_term, '1st Semester');

  -- Two subjects per assigned section, from the curriculum for that
  -- section's program + year level (first term).
  insert into public.class_sections (
    subject_id, section_id, professor_id, room, schedule_days,
    start_time, end_time, school_year, term
  )
  select pick.subject_id, pick.section_id, v_prof,
         'Room ' || (100 + pick.rn)::text,
         case pick.rn when 1 then array['Mon', 'Wed'] else array['Tue', 'Thu'] end,
         case pick.rn when 1 then time '08:00' else time '10:00' end,
         case pick.rn when 1 then time '10:00' else time '12:00' end,
         v_year, v_term
    from (
      select s.id as section_id, ce.subject_id,
             row_number() over (partition by s.id order by sub.code) as rn
        from public.class_assignments ca
        join public.sections s on s.id = ca.section_id
        join public.curriculum_entries ce
          on ce.year_level = s.year_level
         and ce.term = 1
         and ce.program ilike case
               when s.name ilike 'BSIT%'  then '%Information Technology%'
               when s.name ilike 'BSHM%'  then '%Hospitality%'
               when s.name ilike 'BSBA%'  then '%Business Administration%'
               when s.name ilike 'BSTM%'  then '%Tourism%'
               else '%'
             end
        join public.subjects sub on sub.id = ce.subject_id
       where ca.professor_id = v_prof
    ) pick
   where pick.rn <= 2
     and not exists (
       select 1 from public.class_sections cs
        where cs.subject_id = pick.subject_id
          and cs.section_id = pick.section_id
          and cs.professor_id = v_prof
     );
end $$;
