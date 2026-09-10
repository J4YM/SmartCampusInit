-- supabase/add_enroll_section_rpc.sql
--
-- Minimal enrollment tool: bulk-enrolls every currently-active student in
-- a class_sections offering's home section into that offering. Not the
-- full irregular-student enrollment management UI
-- (docs/superpowers/specs/2026-09-04-irregular-students-schema-design.md's
-- deferred "Sub-project 3") — just enough that schedules aren't
-- permanently empty. Idempotent: re-running for the same offering only
-- enrolls students who joined the section since the last run, via the
-- existing enrollments(student_id, class_section_id) unique constraint.
--
-- Run in Supabase SQL Editor, after add_subjects_enrollments_schema.sql.

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
  on conflict (student_id, class_section_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.enroll_section_students(uuid) from public;
grant execute on function public.enroll_section_students(uuid) to authenticated;
