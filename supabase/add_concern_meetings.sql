-- A Discipline Officer-only meeting about a concern.
--
-- The officer can meet the student who filed a concern, their parent, or both,
-- without Guidance and without opening an investigation. It works like an
-- investigation meeting: the officer schedules it, the invitee confirms or
-- declines in their portal (respond_to_meeting), and the officer records how it
-- went (set_meeting_outcome). Only Student Affairs is involved: nobody on the
-- Guidance side is notified and nothing is written to the counselor archive
-- (set_meeting_outcome only logs guidance-owned meetings).
--
--   * guidance_meetings.concern_id ties the meeting to the concern; the meeting's
--     student is the student who filed it.
--   * schedule_concern_meeting(...) schedules it (DO / Admin only) and notifies
--     the invitees. A new invitation replaces an earlier live one.
--   * concern_case_file now also lists the concern's own meetings.
--
-- Run in Supabase SQL Editor AFTER add_concern_investigations.sql. Idempotent.

alter table public.guidance_meetings
  add column if not exists concern_id uuid
    references public.concern_reports(id) on delete cascade;

create index if not exists guidance_meetings_concern_idx
  on public.guidance_meetings (concern_id) where concern_id is not null;

alter table public.guidance_meetings
  drop constraint if exists guidance_meetings_has_parent_check;
alter table public.guidance_meetings
  add constraint guidance_meetings_has_parent_check
  check (investigation_id is not null
         or escalation_report_id is not null
         or referral_id is not null
         or concern_id is not null);

create or replace function public.schedule_concern_meeting(
  p_concern_id uuid,
  p_scheduled_at timestamptz,
  p_location text,
  p_invitee text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.concern_reports;
  v_id uuid;
  v_parent record;
  v_when text;
  v_where text := nullif(btrim(coalesce(p_location, '')), '');
  v_name text;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can schedule a meeting.'
      using errcode = '42501';
  end if;
  if p_scheduled_at <= now() then
    raise exception 'The meeting must be scheduled in the future.';
  end if;
  if p_invitee not in ('student', 'parent', 'both') then
    raise exception 'Invitee must be student, parent or both.';
  end if;
  if length(coalesce(p_location, '')) > 120 then
    raise exception 'The location must be at most 120 characters.';
  end if;

  select * into c from public.concern_reports where id = p_concern_id for update;
  if not found then raise exception 'Concern report not found.'; end if;
  if c.status = 'Closed' then
    raise exception 'This concern report is already closed.';
  end if;
  if p_invitee in ('parent', 'both')
     and not exists (select 1 from public.parent_student_links l
                      where l.student_id = c.student_id) then
    raise exception 'This student has no linked parent. Invite the student only.';
  end if;

  -- A new invitation replaces any earlier one still open, so nobody is asked to
  -- confirm two meetings for one concern.
  update public.guidance_meetings
     set status = 'Cancelled'
   where concern_id = p_concern_id
     and status in ('Proposed', 'Confirmed', 'Reschedule_Requested');

  insert into public.guidance_meetings (
    concern_id, student_id, scheduled_at, location, invitee, scheduled_by, status
  )
  values (p_concern_id, c.student_id, p_scheduled_at, v_where, p_invitee,
          auth.uid(), 'Proposed')
  returning id into v_id;

  -- Working a concern moves it along, as endorsing it does.
  update public.concern_reports
     set status = case when status = 'Pending' then 'In_Progress' else status end,
         handled_by = coalesce(handled_by, auth.uid()),
         handled_at = coalesce(handled_at, now())
   where id = p_concern_id;

  v_name := public.sms_student_name(c.student_id);
  v_when := to_char(p_scheduled_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');

  if p_invitee in ('student', 'both') then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, c.student_id, 'Meeting scheduled',
      'You are invited to a meeting on ' || v_when
      || coalesce(' at ' || v_where, '')
      || '. Please confirm in your dashboard.');
  end if;

  if p_invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = c.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Meeting scheduled',
              public.meeting_invitation_text(v_when, v_where, v_name));
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', c.student_id, v_id,
        'STI Baliuag: a meeting for ' || v_name || ' is set for ' || v_when
        || '. Please confirm in the Parent Portal.');
    exception when others then
      raise warning 'schedule_concern_meeting sms failed: %', sqlerrm;
    end;
  end if;

  perform public.log_audit('Scheduled concern meeting', v_id::text);
  return v_id;
end;
$$;

revoke all on function public.schedule_concern_meeting(uuid, timestamptz, text, text)
  from public, anon;
grant execute on function public.schedule_concern_meeting(uuid, timestamptz, text, text)
  to authenticated;

-- The case file, now with the concern's own meetings (generated from the
-- definition in add_concern_investigations.sql).
create or replace function public.concern_case_file(p_concern_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c public.concern_reports;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only Student Affairs can read a concern case file.'
      using errcode = '42501';
  end if;
  select * into c from public.concern_reports where id = p_concern_id;
  if not found then raise exception 'Concern report not found.'; end if;

  return jsonb_build_object(
    'endorsements', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id,
               'status', e.status,
               'decision_note', e.decision_note,
               'summary', e.summary,
               'decided_at', e.decided_at,
               'meetings', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', m.id,
                          'scheduled_at', m.scheduled_at,
                          'status', m.status,
                          'response_note', m.response_note,
                          'guidance_note', m.guidance_note,
                          'location', m.location)
                        order by m.scheduled_at)
                   from public.guidance_meetings m
                  where m.escalation_report_id = e.id), '[]'::jsonb))
             order by e.created_at)
        from public.escalation_reports e
       where e.concern_id = p_concern_id), '[]'::jsonb),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id,
               'scheduled_at', m.scheduled_at,
               'status', m.status,
               'invitee', m.invitee,
               'response_note', m.response_note,
               'location', m.location)
             order by m.scheduled_at)
        from public.guidance_meetings m
       where m.concern_id = p_concern_id), '[]'::jsonb),
    'investigation', (
      select jsonb_build_object(
               'id', gi.id,
               'status', gi.status,
               'outcome', gi.outcome,
               'findings', gi.findings,
               'recommendation', gi.recommendation,
               'completed_at', gi.completed_at,
               'sanction', (
                 select jsonb_build_object('type', s.sanction_type,
                                           'description', s.description)
                   from public.sanctions s
                  where s.violation_id = gi.violation_id))
        from public.guidance_investigations gi
       where gi.violation_id = c.violation_id)
  );
end;
$$;

revoke all on function public.concern_case_file(uuid) from public, anon;
grant execute on function public.concern_case_file(uuid) to authenticated;
