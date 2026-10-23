-- Assertions for add_good_moral_form_data.sql. Run in the Supabase SQL Editor on
-- a DEV project as an Admin session (like the other test_*.sql files it needs a
-- session whose current_user_role() resolves). Rolled back at the end. Run it
-- once BEFORE the migration (it fails at the first assertion) and once AFTER
-- (it prints "ALL PASSED"). The student/parent-only resubmit permission needs
-- a real login as that user; here we assert the state rules only.

begin;

do $$
declare
  v_student uuid; v_req uuid; v_failed boolean;
begin
  select id into v_student from public.students limit 1;

  insert into public.good_moral_requests
    (student_id, document_type, purpose, requested_by, remarks, form_data)
  values (v_student, 'Certificate of Good Moral', 'Employment', 'Test student',
          'Name: Cruz, Ana', '{"last_name":"Cruz","first_name":"Ana"}'::jsonb)
  returning id into v_req;

  -- Flag only: stays Pending, the note is kept.
  perform public.flag_good_moral_request(v_req, 'Section does not match.', false);
  assert (select status from public.good_moral_requests where id = v_req) = 'Pending',
    'flag alone keeps the request Pending';
  assert (select flag_note from public.good_moral_requests where id = v_req)
    = 'Section does not match.';

  -- A note is required.
  v_failed := false;
  begin perform public.flag_good_moral_request(v_req, '  ', true); v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'a flag needs a note';

  -- Resubmitting a request that was not sent back is refused.
  v_failed := false;
  begin
    perform public.resubmit_good_moral_request(v_req, 'Employment', 'x', '{}'::jsonb);
    v_failed := true;
  exception when others then null; end;
  assert not v_failed, 'only a Returned request can be resubmitted';

  -- Send back, then resubmit: history keeps the earlier submission.
  perform public.flag_good_moral_request(v_req, 'Section does not match.', true);
  assert (select status from public.good_moral_requests where id = v_req) = 'Returned';
  perform public.resubmit_good_moral_request(
    v_req, 'Employment', 'Name: Cruz, Ana (fixed)', '{"last_name":"Cruz"}'::jsonb);
  assert (select status from public.good_moral_requests where id = v_req) = 'Pending';
  assert (select jsonb_array_length(history) from public.good_moral_requests where id = v_req) = 1;
  assert (select flag_note from public.good_moral_requests where id = v_req) is null,
    'resubmitting clears the note';

  -- Twice: both earlier submissions are kept.
  perform public.flag_good_moral_request(v_req, 'Again.', true);
  perform public.resubmit_good_moral_request(v_req, 'Employment', 'v3', '{}'::jsonb);
  assert (select jsonb_array_length(history) from public.good_moral_requests where id = v_req) = 2;

  raise notice 'ALL PASSED';
end $$;

rollback;
