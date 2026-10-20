-- The kiosk's Security / Teacher report flow no longer picks a violation:
-- it files WHAT happened and WHEN. submit_admission_slip therefore accepts an
-- empty offense list as long as incident notes are given, and stores one
-- unclassified student_violations row (offense_id null) that the Discipline
-- Officer classifies later (classify_violation). The student kiosk
-- self-report still passes real offense ids and behaves exactly as before.
--
-- New optional p_incident_at records when the incident happened (defaults to
-- now() when omitted, e.g. offline-queued slips from older kiosk builds).
--
-- NOTE: a different parameter list makes `create or replace` add an OVERLOAD,
-- which makes PostgREST fail with PGRST203, so the previous 7-argument
-- version is dropped first.
--
-- Run in Supabase SQL Editor after add_incident_report_classification.sql.
-- Idempotent.

drop function if exists public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text, uuid
);

create or replace function public.submit_admission_slip(
  p_slip_id uuid,
  p_student_id uuid,
  p_reported_by uuid,
  p_offense_ids uuid[],
  p_is_escalated boolean default false,
  p_incident_notes text default null,
  p_professor_id uuid default null,
  p_incident_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_incident_at timestamptz := coalesce(p_incident_at, now());
begin
  if v_incident_at > now() + interval '1 minute' then
    raise exception 'Incident date and time cannot be in the future.';
  end if;

  if array_length(p_offense_ids, 1) is null
     and btrim(coalesce(p_incident_notes, '')) = '' then
    raise exception 'Describe what happened, or choose at least one offense.';
  end if;

  insert into public.admission_slips (id, student_id, reported_by)
  values (p_slip_id, p_student_id, p_reported_by);

  if array_length(p_offense_ids, 1) is null then
    insert into public.student_violations (
      student_id, offense_id, reported_by, status, admission_slip_id,
      is_escalated, incident_notes, professor_id, incident_at
    )
    values (
      p_student_id, null, p_reported_by, 'Pending', p_slip_id,
      false, btrim(p_incident_notes), p_professor_id, v_incident_at
    );

    begin
      insert into public.notifications (target_role, title, message)
      values (
        'Discipline_Officer'::app_role,
        'New incident report to classify',
        public.sms_student_name(p_student_id)
          || ' has a new incident report awaiting classification.'
      );
    exception when others then
      raise warning 'submit_admission_slip notify failed: %', sqlerrm;
    end;
  else
    insert into public.student_violations (
      student_id, offense_id, reported_by, status, admission_slip_id,
      is_escalated, incident_notes, professor_id, incident_at
    )
    select
      p_student_id, offense_id, p_reported_by, 'Pending', p_slip_id,
      p_is_escalated, p_incident_notes, p_professor_id, v_incident_at
    from unnest(p_offense_ids) as offense_id;
  end if;
end;
$$;

revoke all on function public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text, uuid, timestamptz
) from public;
grant execute on function public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text, uuid, timestamptz
) to anon, authenticated;
