-- The Discipline Office owns investigations.
--
-- The DO starts an investigation (escalate_to_guidance keeps its name), then
-- schedules the meetings, records how they went and completes it with
-- findings. The Guidance Associate no longer reads investigations or their
-- meetings and is no longer notified about them. Students and parents still
-- confirm or decline their invitations in their own dashboards.
--
--   * schedule_guidance_meeting / set_meeting_outcome / complete_investigation:
--     Admin and Discipline_Officer only (were Guidance_Counselor and Admin).
--   * respond_to_meeting tells the DO; a meeting that belongs to an
--     endorsement (escalation_report_id set) still tells Guidance.
--   * escalate_to_guidance and complete_investigation notify nobody (the DO
--     did it); record_sanction no longer sends Guidance the override reason.
--   * guidance_investigations: Admin + DO read. guidance_meetings: Admin + DO,
--     plus Guidance for endorsement meetings only.
--
-- Existing investigations and meetings keep their rows; every DO account can
-- act on all of them.
--
-- Run in Supabase SQL Editor after add_guidance_investigations.sql,
-- add_sanctions_schema.sql and add_endorsements.sql. Idempotent. Re-running
-- add_guidance_investigations.sql or add_sanctions_schema.sql afterwards
-- restores the old behaviour: run this file again.

-- ---------------------------------------------------------------------------
-- Who can read
-- ---------------------------------------------------------------------------

drop policy if exists "guidance_investigations_staff_select" on public.guidance_investigations;
create policy "guidance_investigations_staff_select"
  on public.guidance_investigations for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role));

drop policy if exists "guidance_meetings_staff_select" on public.guidance_meetings;
create policy "guidance_meetings_staff_select"
  on public.guidance_meetings for select to authenticated
  using (
    current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role)
    or (current_user_role() = 'Guidance_Counselor'::app_role
        and escalation_report_id is not null)
  );

-- ---------------------------------------------------------------------------
-- escalate_to_guidance: the DO starts the investigation, nobody is notified
-- ---------------------------------------------------------------------------

create or replace function public.escalate_to_guidance(p_violation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.student_violations;
  v_id uuid;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can start an investigation.'
      using errcode = '42501';
  end if;

  select * into v from public.student_violations
   where id = p_violation_id for update;
  if not found then raise exception 'Report not found.'; end if;
  if v.offense_id is null then
    raise exception 'Classify the report before starting an investigation.';
  end if;
  -- A Pending case, or a case an older build already marked
  -- Under_Investigation that never got an investigation row.
  if v.status <> 'Pending'
     and not (v.status = 'Under_Investigation'
              and not exists (select 1 from public.guidance_investigations gi
                               where gi.violation_id = p_violation_id)) then
    raise exception 'Only a pending case can be investigated.';
  end if;

  insert into public.guidance_investigations (violation_id, student_id, escalated_by)
  values (p_violation_id, v.student_id, auth.uid())
  returning id into v_id;

  update public.student_violations
     set status = 'Under_Investigation', is_escalated = true
   where id = p_violation_id;

  perform public.log_audit('Started investigation', p_violation_id::text);
  return v_id;
end;
$$;

revoke all on function public.escalate_to_guidance(uuid) from public, anon;
grant execute on function public.escalate_to_guidance(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- schedule_guidance_meeting: the DO schedules
-- ---------------------------------------------------------------------------

create or replace function public.schedule_guidance_meeting(
  p_investigation_id uuid,
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
  inv public.guidance_investigations;
  v_id uuid;
  v_parent record;
  v_when text;
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

  select * into inv from public.guidance_investigations
   where id = p_investigation_id for update;
  if not found then raise exception 'Investigation not found.'; end if;
  if inv.status <> 'Open' then
    raise exception 'This investigation is already complete.';
  end if;

  -- A new invitation replaces any earlier one that is still open, so nobody
  -- is asked to confirm two meetings for one case.
  update public.guidance_meetings
     set status = 'Cancelled'
   where investigation_id = p_investigation_id
     and status in ('Proposed', 'Confirmed', 'Reschedule_Requested');

  insert into public.guidance_meetings (
    investigation_id, student_id, scheduled_at, location, invitee, scheduled_by
  )
  values (
    p_investigation_id, inv.student_id, p_scheduled_at,
    nullif(btrim(coalesce(p_location, '')), ''), p_invitee, auth.uid()
  )
  returning id into v_id;

  v_when := to_char(p_scheduled_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');

  if p_invitee in ('student', 'both') then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, inv.student_id, 'Meeting scheduled',
      'You are invited to a meeting on ' || v_when
      || coalesce(' at ' || nullif(btrim(coalesce(p_location, '')), ''), '')
      || '. Please confirm in your dashboard.');
  end if;

  if p_invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = inv.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Meeting scheduled',
        public.sms_student_name(inv.student_id) || '''s meeting is on ' || v_when
        || coalesce(' at ' || nullif(btrim(coalesce(p_location, '')), ''), '')
        || '. Please confirm in the Parent Portal.');
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', inv.student_id, v_id,
        'STI Baliuag: a meeting for ' || public.sms_student_name(inv.student_id)
        || ' is set for ' || v_when || '. Please confirm in the Parent Portal.');
    exception when others then
      raise warning 'schedule_guidance_meeting sms failed: %', sqlerrm;
    end;
  end if;

  perform public.log_audit('Scheduled meeting', v_id::text);
  return v_id;
end;
$$;

revoke all on function public.schedule_guidance_meeting(uuid, timestamptz, text, text) from public, anon;
grant execute on function public.schedule_guidance_meeting(uuid, timestamptz, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- respond_to_meeting: replies reach the DO (Guidance for endorsement meetings)
-- ---------------------------------------------------------------------------

create or replace function public.respond_to_meeting(
  p_meeting_id uuid,
  p_accept boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.guidance_meetings;
  v_allowed boolean := false;
begin
  select * into m from public.guidance_meetings where id = p_meeting_id for update;
  if not found then raise exception 'Meeting not found.'; end if;

  if m.invitee in ('student', 'both') and auth.uid() = m.student_id then
    v_allowed := true;
  end if;
  if m.invitee in ('parent', 'both') and exists (
    select 1 from public.parent_student_links l
     where l.student_id = m.student_id and l.parent_id = auth.uid()) then
    v_allowed := true;
  end if;
  if not v_allowed then
    raise exception 'You are not invited to this meeting.' using errcode = '42501';
  end if;
  if m.status not in ('Proposed', 'Confirmed', 'Declined', 'Reschedule_Requested') then
    raise exception 'This meeting can no longer be changed.';
  end if;
  if m.scheduled_at <= now() then
    raise exception 'This meeting has already passed.';
  end if;

  update public.guidance_meetings
     set status = case when p_accept then 'Confirmed' else 'Declined' end,
         response_by = auth.uid(),
         responded_at = now(),
         response_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_meeting_id;

  begin
    insert into public.notifications (target_role, title, message)
    values (
      case when m.escalation_report_id is not null
           then 'Guidance_Counselor'::app_role
           else 'Discipline_Officer'::app_role end,
      case when p_accept then 'Meeting confirmed' else 'Meeting declined' end,
      public.sms_student_name(m.student_id)
        || case when p_accept then ' confirmed' else ' cannot attend' end
        || ' the meeting.'
        || coalesce(' Note: ' || nullif(btrim(coalesce(p_note, '')), ''), '')
    );
  exception when others then
    raise warning 'respond_to_meeting notify failed: %', sqlerrm;
  end;
end;
$$;

revoke all on function public.respond_to_meeting(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_meeting(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- set_meeting_outcome / complete_investigation: the DO
-- ---------------------------------------------------------------------------

create or replace function public.set_meeting_outcome(
  p_meeting_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can set a meeting outcome.'
      using errcode = '42501';
  end if;
  if p_status not in ('Completed', 'Missed', 'Cancelled') then
    raise exception 'Outcome must be Completed, Missed or Cancelled.';
  end if;
  update public.guidance_meetings
     set status = p_status
   where id = p_meeting_id
     and status in ('Proposed', 'Confirmed', 'Declined', 'Reschedule_Requested');
  if not found then
    if exists (select 1 from public.guidance_meetings where id = p_meeting_id) then
      raise exception 'This meeting can no longer be changed.';
    end if;
    raise exception 'Meeting not found.';
  end if;
  perform public.log_audit('Set meeting outcome: ' || p_status, p_meeting_id::text);
end;
$$;

revoke all on function public.set_meeting_outcome(uuid, text) from public, anon;
grant execute on function public.set_meeting_outcome(uuid, text) to authenticated;

create or replace function public.complete_investigation(
  p_investigation_id uuid,
  p_findings text,
  p_recommendation text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  inv public.guidance_investigations;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can complete an investigation.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_findings, '')) = '' then
    raise exception 'Findings are required.';
  end if;

  -- Lock the violation BEFORE the investigation: record_sanction locks them in
  -- that order.
  perform 1 from public.student_violations v
    join public.guidance_investigations gi on gi.violation_id = v.id
   where gi.id = p_investigation_id
   for update of v;

  select * into inv from public.guidance_investigations
   where id = p_investigation_id for update;
  if not found then raise exception 'Investigation not found.'; end if;
  if inv.status <> 'Open' then
    raise exception 'This investigation is already complete.';
  end if;

  update public.guidance_investigations
     set status = 'Complete',
         findings = btrim(p_findings),
         recommendation = nullif(btrim(coalesce(p_recommendation, '')), ''),
         assigned_to = coalesce(assigned_to, auth.uid()),
         completed_at = now()
   where id = p_investigation_id;

  update public.student_violations
     set status = 'Investigation_Complete'
   where id = inv.violation_id and status = 'Under_Investigation';

  update public.guidance_meetings
     set status = 'Cancelled'
   where investigation_id = p_investigation_id
     and status in ('Proposed', 'Confirmed', 'Reschedule_Requested', 'Declined')
     and scheduled_at > now();

  perform public.log_audit('Completed investigation', inv.violation_id::text);
end;
$$;

revoke all on function public.complete_investigation(uuid, text, text) from public, anon;
grant execute on function public.complete_investigation(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- record_sanction: Guidance is no longer told about an early sanction
-- ---------------------------------------------------------------------------

create or replace function public.record_sanction(
  p_violation_id uuid,
  p_basis text,
  p_handbook_offense_id uuid,
  p_sanction_type text,
  p_description text,
  p_effective_on date,
  p_ends_on date,
  p_affects_enrollment boolean,
  p_override_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.student_violations;
  v_id uuid;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can record a sanction.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_description, '')) = '' then
    raise exception 'A sanction description is required.';
  end if;

  select * into v from public.student_violations
   where id = p_violation_id for update;
  if not found then
    raise exception 'Report not found.';
  end if;
  if v.offense_id is null then
    raise exception 'Classify the report before sanctioning it.';
  end if;
  if v.status = 'Resolved' then
    raise exception 'This case already has a sanction.';
  end if;

  if v.status = 'Under_Investigation' then
    if btrim(coalesce(p_override_reason, '')) = '' then
      raise exception 'This case is still under investigation. Enter a reason to sanction it before findings are filed.';
    end if;
    update public.guidance_investigations
       set status = 'Complete', completed_at = now()
     where violation_id = p_violation_id and status = 'Open';
    -- Close the meetings too, so nobody is still asked to confirm one for a
    -- case that no longer needs it.
    update public.guidance_meetings
       set status = 'Cancelled'
     where investigation_id in (
             select id from public.guidance_investigations
              where violation_id = p_violation_id)
       and status in ('Proposed', 'Confirmed', 'Reschedule_Requested', 'Declined')
       and scheduled_at > now();
  end if;

  v_id := public._apply_sanction(
    p_violation_id, p_basis, p_handbook_offense_id, p_sanction_type,
    p_description, p_effective_on, p_ends_on, p_affects_enrollment,
    p_override_reason);

  perform public.log_audit('Recorded sanction', p_violation_id::text,
    case when p_affects_enrollment then 'WARN' else 'INFO' end);
  return v_id;
end;
$$;

revoke all on function public.record_sanction(
  uuid, text, uuid, text, text, date, date, boolean, text) from public, anon;
grant execute on function public.record_sanction(
  uuid, text, uuid, text, text, date, date, boolean, text) to authenticated;
