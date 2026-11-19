-- Concerns can be sent to investigation, and show what came back.
--
--   * concern_reports.violation_id remembers the incident a concern became.
--   * send_concern_to_investigation(...): the officer names the student the
--     concern is about (the reporter's form never asks). It records the incident
--     quietly through report_incident (add_manual_incident_reports.sql), starts
--     the investigation (escalate_to_guidance) and moves the concern to
--     In_Progress. A concern can only be sent once, and only while it is open.
--   * concern_case_file(concern_id): the endorsement(s) made from the concern,
--     their meetings (status and the invitee's reply) and, once there is one,
--     the investigation's findings and the sanction. Read-only; Student Affairs
--     and Admin only.
--
-- The status picker is not touched: a concern can always be updated or closed
-- through concern_reports_staff_update, even with an investigation still open.
--
-- Run in Supabase SQL Editor after add_manual_incident_reports.sql and
-- add_do_investigations.sql. Idempotent: safe to re-run.

alter table public.concern_reports
  add column if not exists violation_id uuid
    references public.student_violations(id) on delete set null;

create or replace function public.send_concern_to_investigation(
  p_concern_id uuid,
  p_student_id uuid,
  p_offense_id uuid,
  p_description text,
  p_occurred_at timestamptz,
  p_location text default null,
  p_notify_parent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.concern_reports;
  v_violation uuid;
  v_investigation uuid;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can start an investigation.'
      using errcode = '42501';
  end if;

  select * into c from public.concern_reports where id = p_concern_id for update;
  if not found then raise exception 'Concern report not found.'; end if;
  if c.status = 'Closed' then
    raise exception 'This concern report is already closed.';
  end if;
  if c.violation_id is not null then
    raise exception 'This concern is already under investigation.';
  end if;

  v_violation := public.report_incident(
    p_student_id, p_offense_id, p_description, p_occurred_at,
    p_location, p_notify_parent, p_concern_id);
  v_investigation := public.escalate_to_guidance(v_violation);

  update public.concern_reports
     set violation_id = v_violation,
         status = 'In_Progress',
         handled_by = coalesce(handled_by, auth.uid()),
         handled_at = coalesce(handled_at, now())
   where id = p_concern_id;

  perform public.log_audit('Sent concern to investigation', p_concern_id::text);
  return v_investigation;
end;
$$;

revoke all on function public.send_concern_to_investigation(
  uuid, uuid, uuid, text, timestamptz, text, boolean) from public, anon;
grant execute on function public.send_concern_to_investigation(
  uuid, uuid, uuid, text, timestamptz, text, boolean) to authenticated;

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
