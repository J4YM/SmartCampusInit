-- Assertions for add_referral_form.sql. Run in the Supabase SQL Editor on a DEV
-- project as an Admin session, AFTER add_referral_form.sql. It needs one
-- student. Rolled back at the end. Prints "ALL PASSED".

begin;

do $$
declare
  v_student uuid; v_id uuid; v_failed boolean;
  v_form jsonb := '{"address":"12 Rizal St","referral_to":["Guidance Counselor"],"academic":["Test anxiety"]}';
begin
  select id into v_student from public.students limit 1;
  assert v_student is not null, 'need a student';

  -- The form is stored with the referral.
  v_id := public.submit_student_referral(
    v_student, 'academic', 'I cannot focus on my exams.', false, v_form);
  assert (select form from public.student_referrals where id = v_id) = v_form,
    'the form is stored as sent';
  assert (select source from public.student_referrals where id = v_id) = 'self';

  -- Without a form it is an empty object, never null.
  v_id := public.submit_student_referral(
    v_student, 'other', 'Something is wrong at home.', false);
  assert (select form from public.student_referrals where id = v_id) = '{}'::jsonb,
    'no form gives an empty object';

  -- A form that is not an object is ignored, not stored.
  v_id := public.submit_student_referral(
    v_student, 'other', 'Another thing to share.', false, '"nope"'::jsonb);
  assert (select form from public.student_referrals where id = v_id) = '{}'::jsonb,
    'a non-object form is replaced by {}';

  -- The column refuses an oversized form.
  v_failed := false;
  begin
    update public.student_referrals
       set form = jsonb_build_object('x', repeat('a', 30000))
     where id = v_id;
  exception when check_violation then v_failed := true; end;
  assert v_failed, 'an oversized form is refused';

  -- The student's list carries the details and the form.
  assert exists (
    select 1 from public.my_student_referrals(v_student) m
     where m.form = v_form and m.details = 'I cannot focus on my exams.'),
    'my_student_referrals returns details and form';

  raise notice 'ALL PASSED';
end $$;

rollback;
