-- Meetings for an endorsement: the Discipline Officer arranges, Guidance
-- confirms, then the invitees are told.
--
--   1. Once Guidance has accepted an endorsement, the DO proposes a meeting
--      (student, parent or both). It is saved as 'Awaiting_Guidance'. Nobody
--      outside the two offices hears about it yet.
--   2. Guidance confirms it (optionally changing the time or place) or
--      returns it to the DO with a recommendation ('Returned').
--   3. On confirmation the invitees get the invitation (student: portal
--      notification; parent: notification and SMS) and the meeting becomes
--      'Proposed', exactly like any other meeting: the invitee confirms or
--      declines in their own portal.
--
-- Students and parents cannot read a meeting that is awaiting Guidance or was
-- returned. An endorsement with exclude_parent only ever invites the student.
-- Guidance no longer schedules when approving an endorsement (see
-- add_endorsement_other_kind.sql). Meetings that do not belong to an
-- endorsement (investigations, self referrals) are unchanged.
--
-- Run in Supabase SQL Editor after add_endorsement_other_kind.sql and
-- reword_meeting_invitations.sql. Idempotent. Re-running add_do_investigations.sql
-- or add_referral_meetings.sql afterwards restores their respond_to_meeting /
-- set_meeting_outcome: run this file again.

-- ---------------------------------------------------------------------------
-- 1. Statuses, note, who can read
-- ---------------------------------------------------------------------------

alter table public.guidance_meetings
  drop constraint if exists guidance_meetings_status_check;
alter table public.guidance_meetings
  add constraint guidance_meetings_status_check
  check (status in (
    'Awaiting_Guidance', 'Returned',
    'Proposed', 'Confirmed', 'Declined', 'Reschedule_Requested',
    'Completed', 'Missed', 'Cancelled'));

alter table public.guidance_meetings
  add column if not exists guidance_note text;

drop policy if exists "guidance_meetings_student_select" on public.guidance_meetings;
create policy "guidance_meetings_student_select"
  on public.guidance_meetings for select to authenticated
  using (student_id = auth.uid()
         and invitee in ('student', 'both')
         and status not in ('Awaiting_Guidance', 'Returned'));

drop policy if exists "guidance_meetings_parent_select" on public.guidance_meetings;
create policy "guidance_meetings_parent_select"
  on public.guidance_meetings for select to authenticated
  using (invitee in ('parent', 'both')
         and status not in ('Awaiting_Guidance', 'Returned')
         and exists (
           select 1 from public.parent_student_links l
            where l.student_id = guidance_meetings.student_id
              and l.parent_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- 2. The Discipline Officer proposes
-- ---------------------------------------------------------------------------

create or replace function public.propose_endorsement_meeting(
  p_escalation_id uuid,
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
  e public.escalation_reports;
  v_id uuid;
  v_where text := nullif(btrim(coalesce(p_location, '')), '');
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can arrange an endorsement meeting.'
      using errcode = '42501';
  end if;
  if p_scheduled_at <= now() then
    raise exception 'The meeting must be scheduled in the future.';
  end if;
  if p_invitee not in ('student', 'parent', 'both') then
    raise exception 'Invitee must be student, parent or both.';
  end if;

  select * into e from public.escalation_reports where id = p_escalation_id for update;
  if not found then raise exception 'Endorsement not found.'; end if;
  if e.status <> 'Approved' then
    raise exception 'Guidance has not accepted this endorsement yet.';
  end if;
  if e.exclude_parent and p_invitee <> 'student' then
    raise exception 'The parent is excluded from this endorsement: invite the student only.';
  end if;

  -- A new proposal replaces an earlier one still waiting for Guidance. A live
  -- invitation (Proposed / Confirmed) stays until Guidance confirms the new
  -- time, so an invitee is never left with a silently cancelled meeting.
  update public.guidance_meetings
     set status = 'Cancelled'
   where escalation_report_id = p_escalation_id
     and status = 'Awaiting_Guidance';

  insert into public.guidance_meetings (
    escalation_report_id, student_id, scheduled_at, location, invitee,
    scheduled_by, status
  )
  values (p_escalation_id, e.student_id, p_scheduled_at, v_where, p_invitee,
          auth.uid(), 'Awaiting_Guidance')
  returning id into v_id;

  insert into public.notifications (target_role, title, message)
  values ('Guidance_Counselor'::app_role, 'Meeting awaiting your confirmation',
          'Student Affairs arranged a meeting for ' || public.sms_student_name(e.student_id)
          || ' on '
          || to_char(p_scheduled_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM')
          || coalesce(' at ' || v_where, '')
          || '. Confirm it under Referrals.');

  perform public.log_audit('Proposed endorsement meeting', v_id::text);
  return v_id;
end;
$$;

revoke all on function public.propose_endorsement_meeting(uuid, timestamptz, text, text)
  from public, anon;
grant execute on function public.propose_endorsement_meeting(uuid, timestamptz, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Guidance confirms (optionally changing time / place) ...
-- ---------------------------------------------------------------------------

create or replace function public.confirm_endorsement_meeting(
  p_meeting_id uuid,
  p_scheduled_at timestamptz default null,
  p_location text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.guidance_meetings;
  v_at timestamptz;
  v_where text;
  v_changed boolean;
  v_when text;
  v_name text;
  v_school text;
  v_parent record;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Guidance_Counselor'::app_role), false) then
    raise exception 'Only the Guidance Associate can confirm this meeting.'
      using errcode = '42501';
  end if;

  select * into m from public.guidance_meetings where id = p_meeting_id for update;
  if not found then raise exception 'Meeting not found.'; end if;
  if m.escalation_report_id is null or m.status <> 'Awaiting_Guidance' then
    raise exception 'This meeting is not waiting for your confirmation.';
  end if;

  v_at := coalesce(p_scheduled_at, m.scheduled_at);
  v_where := coalesce(nullif(btrim(coalesce(p_location, '')), ''), m.location);
  if v_at <= now() then
    raise exception 'The meeting must be scheduled in the future.';
  end if;
  v_changed := v_at is distinct from m.scheduled_at
               or v_where is distinct from m.location;

  -- The new invitation replaces the endorsement's earlier live one (the
  -- invitees get the new time right below).
  update public.guidance_meetings
     set status = 'Cancelled'
   where escalation_report_id = m.escalation_report_id
     and id <> p_meeting_id
     and status in ('Proposed', 'Confirmed', 'Reschedule_Requested');

  update public.guidance_meetings
     set status = 'Proposed', scheduled_at = v_at, location = v_where,
         guidance_note = null
   where id = p_meeting_id;

  v_when := to_char(v_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');
  v_name := public.sms_student_name(m.student_id);
  select school_name into v_school from public.sms_settings where id;

  if m.invitee in ('student', 'both') then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, m.student_id, 'Meeting invitation',
            public.meeting_invitation_text(v_when, v_where));
  end if;

  if m.invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = m.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Meeting invitation',
              public.meeting_invitation_text(v_when, v_where, v_name));
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', m.student_id, p_meeting_id,
        public.meeting_invitation_sms(v_when, v_where, v_name, v_school));
    exception when others then
      raise warning 'confirm_endorsement_meeting sms failed: %', sqlerrm;
    end;
  end if;

  insert into public.notifications (target_role, title, message)
  values ('Discipline_Officer'::app_role, 'Meeting confirmed by Guidance',
          'Guidance confirmed the meeting for ' || v_name || ' on ' || v_when
          || coalesce(' at ' || v_where, '')
          || case when v_changed then ' (changed from your proposal)' else '' end
          || '. The invitees have been notified.');

  perform public.log_audit('Confirmed endorsement meeting', p_meeting_id::text);
end;
$$;

revoke all on function public.confirm_endorsement_meeting(uuid, timestamptz, text)
  from public, anon;
grant execute on function public.confirm_endorsement_meeting(uuid, timestamptz, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. ... or returns it to the Discipline Officer with a recommendation
-- ---------------------------------------------------------------------------

create or replace function public.return_endorsement_meeting(
  p_meeting_id uuid,
  p_note text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.guidance_meetings;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Guidance_Counselor'::app_role), false) then
    raise exception 'Only the Guidance Associate can return this meeting.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'A recommendation is required.';
  end if;

  select * into m from public.guidance_meetings where id = p_meeting_id for update;
  if not found then raise exception 'Meeting not found.'; end if;
  if m.escalation_report_id is null or m.status <> 'Awaiting_Guidance' then
    raise exception 'This meeting is not waiting for your confirmation.';
  end if;

  update public.guidance_meetings
     set status = 'Returned', guidance_note = btrim(p_note)
   where id = p_meeting_id;

  insert into public.notifications (target_role, title, message)
  values ('Discipline_Officer'::app_role, 'Meeting returned by Guidance',
          'Guidance returned the meeting for ' || public.sms_student_name(m.student_id)
          || ': ' || btrim(p_note) || ' Please arrange another time.');

  perform public.log_audit('Returned endorsement meeting', p_meeting_id::text);
end;
$$;

revoke all on function public.return_endorsement_meeting(uuid, text) from public, anon;
grant execute on function public.return_endorsement_meeting(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Replies: an endorsement meeting tells the DO and Guidance
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
  v_title text;
  v_text text;
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

  v_title := case when p_accept then 'Meeting confirmed' else 'Meeting declined' end;
  v_text := public.sms_student_name(m.student_id)
    || case when p_accept then ' confirmed' else ' cannot attend' end
    || ' the meeting.'
    || coalesce(' Note: ' || nullif(btrim(coalesce(p_note, '')), ''), '');

  begin
    -- Investigation meetings belong to the DO, self referral meetings to
    -- Guidance, endorsement meetings to both.
    if m.referral_id is null then
      insert into public.notifications (target_role, title, message)
      values ('Discipline_Officer'::app_role, v_title, v_text);
    end if;
    if m.referral_id is not null or m.escalation_report_id is not null then
      insert into public.notifications (target_role, title, message)
      values ('Guidance_Counselor'::app_role, v_title, v_text);
    end if;
  exception when others then
    raise warning 'respond_to_meeting notify failed: %', sqlerrm;
  end;
end;
$$;

revoke all on function public.respond_to_meeting(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_meeting(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Outcomes: Guidance closes out the meetings it confirmed
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
declare
  v_guidance_owned boolean;
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
end;
$$;

revoke all on function public.set_meeting_outcome(uuid, text) from public, anon;
grant execute on function public.set_meeting_outcome(uuid, text) to authenticated;
