-- Assertions for add_enrollment_standing_guard.sql. Run in the Supabase SQL
-- Editor on a DEV project as an Admin session. Rolled back at the end.
-- Needs one student and one class_sections row.
-- Expected: final NOTICE "ALL PASSED".

begin;

do $$
declare
  v_student uuid;
  v_cs uuid;
  v_failed boolean;
begin
  select id into v_student from public.students limit 1;
  select id into v_cs from public.class_sections limit 1;

  -- Good standing: enrollment works.
  update public.students set enrollment_standing = 'Good' where id = v_student;
  insert into public.enrollments (student_id, class_section_id, status)
  values (v_student, v_cs, 'Active')
  on conflict (student_id, class_section_id) do update set status = 'Active';

  -- Non-readmission: a new Active enrollment is refused.
  delete from public.enrollments where student_id = v_student and class_section_id = v_cs;
  update public.students set enrollment_standing = 'Non_Readmission' where id = v_student;
  v_failed := false;
  begin
    insert into public.enrollments (student_id, class_section_id, status)
    values (v_student, v_cs, 'Active');
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'restricted student must not be enrolled';

  -- Registrar re-enrollment is refused with a readable message.
  v_failed := false;
  begin
    perform public.confirm_student_enrollment(array[v_student], 'registrar');
    v_failed := true;
  exception when others then
    assert sqlerrm like '%Not for Readmission%', 'message names the restriction: ' || sqlerrm;
  end;
  assert not v_failed, 'registrar confirm must raise';

  -- An import silently skips the restricted student.
  perform public.confirm_student_enrollment(array[v_student], 'import');

  -- Bulk section enroll skips them too.
  perform public.enroll_section_students(v_cs);
  assert not exists (
    select 1 from public.enrollments where student_id = v_student and class_section_id = v_cs),
    'bulk enroll must skip a restricted student';

  -- Lifting needs a reason, then enrollment works again.
  v_failed := false;
  begin perform public.lift_enrollment_standing(v_student, '  '); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'lift without a reason must raise';
  perform public.lift_enrollment_standing(v_student, 'Appeal granted');
  assert (select enrollment_standing from public.students where id = v_student) = 'Good';

  raise notice 'ALL PASSED';
end $$;

rollback;
