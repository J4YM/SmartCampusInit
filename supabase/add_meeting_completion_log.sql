-- Completed guidance meetings are written to the intervention log.
--
-- The Guidance Counselor's confidential Student Archive
-- (counseling_archive_logs, add_counseling_archive_logs.sql) is the intervention
-- log. When a guidance-owned meeting (an endorsement meeting or a self-referral
-- meeting) is marked Completed through set_meeting_outcome, one archive entry is
-- added for the student automatically:
--
--   * log type: parent_conference when the parent is invited (parent or both),
--     counseling when only the student is.
--   * notes: who was invited, when, where, the invitee's reply and, for an
--     endorsement, Guidance's decision note.
--   * counseling_archive_logs.meeting_id (unique) links the entry to its meeting,
--     so completing or re-saving never creates a duplicate.
--   * Written by this security-definer function, so it works whoever completes
--     the meeting (counselor, Discipline Officer or Admin) while the archive stays
--     readable only to the Guidance Counselor and Admin.
--
-- Missed and Cancelled meetings, and investigation meetings the DO runs without a
-- counselor, are not logged. Meetings completed before this runs are not
-- back-filled.
--
-- set_meeting_outcome below is the definition in add_endorsement_meetings.sql
-- (the most complete one: DO and Admin for any meeting, Guidance for its own)
-- plus the log entry. Run in Supabase SQL Editor AFTER add_endorsement_meetings.sql
-- and add_referral_meetings.sql. Idempotent: safe to re-run. Running an older
-- add_*_meetings.sql afterwards restores the old function: run this file again.

alter table public.counseling_archive_logs
  add column if not exists meeting_id uuid
    references public.guidance_meetings(id) on delete set null;

create unique index if not exists counseling_archive_logs_meeting_key
  on public.counseling_archive_logs (meeting_id)
  where meeting_id is not null;

create or replace function public.set_meeting_outcome(
  p_meeting_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_guidance_owned boolean;
  m public.guidance_meetings;
  v_decision text;
  v_name text;
  v_kind text;
  v_invited text;
  v_notes text;
begin
  select (referral_id is not null or escalation_report_id is not null)
    into v_guidance_owned
    from public.guidance_meetings where id = p_meeting_id;

  if not coalesce(
       current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role)
       or (coalesce(v_guidance_owned, false)
           and current_user_role() = 'Guidance_Counselor'::app_role),
       false) then
    raise exception 'You cannot set the outcome of this meeting.'
      using errcode = '42501';
  end if;
  if p_status not in ('Completed', 'Missed', 'Cancelled') then
    raise exception 'Outcome must be Completed, Missed or Cancelled.';
  end if;
  update public.guidance_meetings
     set status = p_status
   where id = p_meeting_id
     and status in ('Awaiting_Guidance', 'Proposed', 'Confirmed', 'Declined',
                    'Reschedule_Requested');
  if not found then
    if exists (select 1 from public.guidance_meetings where id = p_meeting_id) then
      raise exception 'This meeting can no longer be changed.';
    end if;
    raise exception 'Meeting not found.';
  end if;
  perform public.log_audit('Set meeting outcome: ' || p_status, p_meeting_id::text);

  -- A completed guidance meeting goes into the student's intervention log.
  if p_status = 'Completed' and coalesce(v_guidance_owned, false) then
    select * into m from public.guidance_meetings where id = p_meeting_id;

    if m.escalation_report_id is not null then
      v_kind := 'endorsement meeting';
      select nullif(btrim(coalesce(decision_note, '')), '') into v_decision
        from public.escalation_reports where id = m.escalation_report_id;
    else
      v_kind := 'referral meeting';
    end if;

    v_invited := case m.invitee
                   when 'both' then 'Parent and student'
                   when 'parent' then 'Parent'
                   else 'Student' end;

    select nullif(btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), '')
      into v_name from public.profiles where id = auth.uid();

    v_notes := concat_ws(E'\n',
      'Invited: ' || v_invited,
      'Held: ' || to_char(m.scheduled_at at time zone 'Asia/Manila',
                          'Mon DD, YYYY HH12:MI AM'),
      case when nullif(btrim(coalesce(m.location, '')), '') is not null
           then 'Location: ' || btrim(m.location) end,
      case when nullif(btrim(coalesce(m.response_note, '')), '') is not null
           then 'Reply to the invitation: ' || btrim(m.response_note) end,
      case when v_decision is not null
           then 'Guidance note: ' || v_decision end);

    insert into public.counseling_archive_logs
      (student_id, log_type, occurred_on, title, notes, created_by,
       created_by_name, meeting_id)
    values (m.student_id,
            case when m.invitee in ('parent', 'both')
                 then 'parent_conference' else 'counseling' end,
            (m.scheduled_at at time zone 'Asia/Manila')::date,
            'Meeting completed: ' || v_kind,
            v_notes, auth.uid(), v_name, p_meeting_id)
    on conflict (meeting_id) where meeting_id is not null do nothing;
  end if;
end;
$$;

revoke all on function public.set_meeting_outcome(uuid, text) from public, anon;
grant execute on function public.set_meeting_outcome(uuid, text) to authenticated;
