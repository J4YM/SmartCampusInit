-- Manual incident reports: the Discipline Officer (Student Affairs) records an
-- incident or violation for a specific student without a report or scan.
--
--   * student_violations gets source / concern_id / location.
--   * report_incident(...) creates the violation. It is QUIET: nothing is sent
--     to the parent or student unless the officer asks (p_notify_parent, or
--     notify_parent_of_incident later). Saving also writes the audit log.
--   * The same function is what "Send to investigation" on a concern calls
--     (add_concern_investigations.sql), with p_concern_id set.
--
-- Run in Supabase SQL Editor after add_do_investigations.sql and
-- add_concern_reports.sql. Idempotent: safe to re-run.

alter table public.student_violations
  add column if not exists source text,
  add column if not exists concern_id uuid
    references public.concern_reports(id) on delete set null,
  add column if not exists location text;

create index if not exists student_violations_concern_idx
  on public.student_violations (concern_id) where concern_id is not null;

-- ---------------------------------------------------------------------------
-- notify_parent_of_incident: the officer's explicit "tell the parent".
-- ---------------------------------------------------------------------------

create or replace function public.notify_parent_of_incident(p_violation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.student_violations;
  v_name text;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can notify the parent.'
      using errcode = '42501';
  end if;

  select * into v from public.student_violations where id = p_violation_id;
  if not found then raise exception 'Incident not found.'; end if;
  if not exists (select 1 from public.parent_student_links l
                  where l.student_id = v.student_id) then
    raise exception 'This student has no linked parent.';
  end if;

  v_name := public.sms_student_name(v.student_id);
  insert into public.parent_interventions
    (student_id, title, message, kind, sent_by, action_required)
  values (v.student_id, 'Incident reported',
          'Student Affairs recorded an incident involving ' || v_name
            || '. Please contact the school if you have any questions.',
          'conduct', 'Student Affairs', false);

  perform public.log_audit('Notified parent of incident', p_violation_id::text);
end;
$$;

revoke all on function public.notify_parent_of_incident(uuid) from public, anon;
grant execute on function public.notify_parent_of_incident(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- report_incident
-- ---------------------------------------------------------------------------

create or replace function public.report_incident(
  p_student_id uuid,
  p_offense_id uuid,
  p_description text,
  p_occurred_at timestamptz,
  p_location text default null,
  p_notify_parent boolean default false,
  p_concern_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can report an incident.'
      using errcode = '42501';
  end if;

  if not exists (select 1 from public.students where id = p_student_id) then
    raise exception 'Student not found.';
  end if;
  if not exists (select 1 from public.handbook_offenses where id = p_offense_id) then
    raise exception 'Choose an offense from the handbook.';
  end if;
  if nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Describe the incident.';
  end if;
  if p_occurred_at is null then
    raise exception 'Enter when the incident happened.';
  end if;
  if p_concern_id is not null
     and not exists (select 1 from public.concern_reports where id = p_concern_id) then
    raise exception 'Concern report not found.';
  end if;

  insert into public.student_violations
    (student_id, offense_id, status, incident_at, incident_notes, reported_by,
     source, concern_id, location)
  values (p_student_id, p_offense_id, 'Pending', p_occurred_at,
          btrim(p_description), auth.uid(), 'student_affairs', p_concern_id,
          nullif(btrim(coalesce(p_location, '')), ''))
  returning id into v_id;

  perform public.log_audit('Reported incident', v_id::text);

  if p_notify_parent then
    perform public.notify_parent_of_incident(v_id);
  end if;
  return v_id;
end;
$$;

revoke all on function public.report_incident(uuid, uuid, text, timestamptz, text, boolean, uuid)
  from public, anon;
grant execute on function public.report_incident(uuid, uuid, text, timestamptz, text, boolean, uuid)
  to authenticated;
