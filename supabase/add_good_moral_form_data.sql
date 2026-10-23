-- Good Moral request slip as structured data, with flag / send back / resubmit.
--
--   * form_data  the slip field by field (jsonb), next to the old `remarks`
--                text block, so the Discipline Officer can compare each answer
--                with the student's record.
--   * flag_note / flagged_at  the DO's note when a slip does not match.
--   * history    earlier submissions, kept when a returned slip is resubmitted.
--   * status     gains 'Returned' (sent back to the student).
--
--   flag_good_moral_request(request, note, send_back)   DO / Admin
--   resubmit_good_moral_request(request, purpose, remarks, form_data)
--                                                        the student or a linked parent
--
-- The DO never edits the student's answers; corrections to the certificate
-- itself happen in the exported .docx. A flagged request can still be exported.
--
-- Run in Supabase SQL Editor after add_good_moral_status_and_insert_policies.sql.
-- Idempotent.

alter table public.good_moral_requests
  add column if not exists form_data jsonb,
  add column if not exists flag_note text,
  add column if not exists flagged_at timestamptz,
  add column if not exists history jsonb not null default '[]'::jsonb;

alter table public.good_moral_requests
  drop constraint if exists good_moral_requests_status_check;
alter table public.good_moral_requests
  add constraint good_moral_requests_status_check
  check (status in ('Pending', 'Fulfilled', 'Returned'));

create or replace function public.flag_good_moral_request(
  p_request_id uuid,
  p_note text,
  p_send_back boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.good_moral_requests;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can flag a request.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'A note is required.';
  end if;

  select * into r from public.good_moral_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.status = 'Fulfilled' then
    raise exception 'This request was already fulfilled.';
  end if;

  update public.good_moral_requests
     set flag_note = btrim(p_note),
         flagged_at = now(),
         status = case when p_send_back then 'Returned' else status end,
         updated_at = now()
   where id = p_request_id;

  if p_send_back then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, r.student_id,
            'Good Moral request needs changes',
            'The Discipline Office sent your request back: ' || btrim(p_note)
            || ' Open your document requests to edit and resubmit it.');
  end if;

  perform public.log_audit(
    case when p_send_back then 'Sent a Good Moral request back'
         else 'Flagged a Good Moral request' end,
    p_request_id::text);
end;
$$;

revoke all on function public.flag_good_moral_request(uuid, text, boolean) from public, anon;
grant execute on function public.flag_good_moral_request(uuid, text, boolean) to authenticated;

create or replace function public.resubmit_good_moral_request(
  p_request_id uuid,
  p_purpose text,
  p_remarks text,
  p_form_data jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.good_moral_requests;
  v_allowed boolean := false;
begin
  select * into r from public.good_moral_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found.'; end if;

  -- The student, a linked parent, or (SQL editor / Admin) a staff session.
  if auth.uid() is not null and auth.uid() = r.student_id then
    v_allowed := true;
  elsif exists (
    select 1 from public.parent_student_links l
     where l.student_id = r.student_id and l.parent_id = auth.uid()) then
    v_allowed := true;
  elsif coalesce(current_user_role() in ('Admin'::app_role), false)
        or auth.uid() is null then
    v_allowed := true;
  end if;
  if not v_allowed then
    raise exception 'This is not your request.' using errcode = '42501';
  end if;
  if r.status <> 'Returned' then
    raise exception 'Only a request the Discipline Office sent back can be resubmitted.';
  end if;
  if btrim(coalesce(p_purpose, '')) = '' then
    raise exception 'A purpose is required.';
  end if;

  update public.good_moral_requests
     set history = history || jsonb_build_array(jsonb_build_object(
           'submitted_at', coalesce(r.flagged_at, r.request_date),
           'purpose', r.purpose,
           'remarks', r.remarks,
           'form_data', r.form_data,
           'returned_note', r.flag_note,
           'returned_at', r.flagged_at)),
         purpose = btrim(p_purpose),
         remarks = p_remarks,
         form_data = p_form_data,
         status = 'Pending',
         flag_note = null,
         flagged_at = null,
         updated_at = now()
   where id = p_request_id;

  insert into public.notifications (target_role, title, message)
  values ('Discipline_Officer'::app_role, 'Good Moral request resubmitted',
          public.sms_student_name(r.student_id) || ' resubmitted a Good Moral request.');
end;
$$;

revoke all on function public.resubmit_good_moral_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.resubmit_good_moral_request(uuid, text, text, jsonb) to authenticated;
