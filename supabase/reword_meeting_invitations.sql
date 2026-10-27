-- Meeting invitations open with "You are invited to a meeting on ...".
--
-- One helper builds the sentence so every scheduler says it the same way, in
-- the portal notification and in the SMS:
--
--   student: You are invited to a meeting on Oct 30, 2026 09:00 AM at
--            Guidance Office. Please confirm in your dashboard.
--   parent:  You are invited to a meeting on Oct 30, 2026 09:00 AM at
--            Guidance Office regarding Ana Cruz. Please confirm in the
--            Parent Portal.
--   SMS:     the parent sentence followed by " - STI Baliuag", at most 300
--            characters.
--
-- The investigation scheduler (schedule_guidance_meeting) and the referral
-- scheduler (schedule_referral_meeting) are replaced to use it;
-- confirm_endorsement_meeting (add_endorsement_meetings.sql) uses it too.
--
-- Run in Supabase SQL Editor after add_do_investigations.sql and
-- add_referral_meetings.sql. Idempotent. Re-running either of those files
-- restores the old wording: run this file again.

create or replace function public.meeting_invitation_text(
  p_when text,
  p_where text default null,
  p_student_name text default null
)
returns text
language sql
immutable
as $$
  select 'You are invited to a meeting on ' || p_when
         || coalesce(' at ' || nullif(btrim(coalesce(p_where, '')), ''), '')
         || case when p_student_name is null
                 then '. Please confirm in your dashboard.'
                 else ' regarding ' || p_student_name
                      || '. Please confirm in the Parent Portal.'
            end;
$$;

create or replace function public.meeting_invitation_sms(
  p_when text,
  p_where text default null,
  p_student_name text default null,
  p_school text default null
)
returns text
language sql
immutable
as $$
  select left(
    public.meeting_invitation_text(p_when, p_where, p_student_name)
      || ' - ' || coalesce(p_school, 'STI Baliuag'),
    300);
$$;

-- ---------------------------------------------------------------------------
-- Investigation meetings (the Discipline Officer schedules)
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
  v_where text := nullif(btrim(coalesce(p_location, '')), '');
  v_name text;
  v_school text;
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
  values (p_investigation_id, inv.student_id, p_scheduled_at, v_where, p_invitee, auth.uid())
  returning id into v_id;

  v_when := to_char(p_scheduled_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');
  v_name := public.sms_student_name(inv.student_id);
  select school_name into v_school from public.sms_settings where id;

  if p_invitee in ('student', 'both') then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, inv.student_id, 'Meeting invitation',
            public.meeting_invitation_text(v_when, v_where));
  end if;

  if p_invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = inv.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Meeting invitation',
              public.meeting_invitation_text(v_when, v_where, v_name));
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', inv.student_id, v_id,
        public.meeting_invitation_sms(v_when, v_where, v_name, v_school));
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
-- Referral meetings (Guidance schedules, self referrals only)
-- ---------------------------------------------------------------------------

create or replace function public.schedule_referral_meeting(
  p_referral_id uuid,
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
  ref public.student_referrals;
  v_id uuid;
  v_parent record;
  v_when text;
  v_where text := nullif(btrim(coalesce(p_location, '')), '');
  v_name text;
  v_school text;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Guidance_Counselor'::app_role), false) then
    raise exception 'Only the Guidance Associate can schedule a referral meeting.'
      using errcode = '42501';
  end if;
  if p_scheduled_at <= now() then
    raise exception 'The meeting must be scheduled in the future.';
  end if;
  if p_invitee not in ('student', 'parent', 'both') then
    raise exception 'Invitee must be student, parent or both.';
  end if;

  select * into ref from public.student_referrals where id = p_referral_id for update;
  if not found then raise exception 'Referral not found.'; end if;
  if ref.status = 'Closed' then
    raise exception 'This referral is already closed.';
  end if;
  -- Meetings for an endorsement are arranged by Student Affairs and only
  -- confirmed here (add_endorsement_meetings.sql).
  if ref.source = 'endorsement' then
    raise exception 'Student Affairs arranges meetings for an endorsement.';
  end if;

  -- A new invitation replaces any earlier one still open.
  update public.guidance_meetings
     set status = 'Cancelled'
   where referral_id = p_referral_id
     and status in ('Proposed', 'Confirmed', 'Reschedule_Requested');

  insert into public.guidance_meetings (
    referral_id, student_id, scheduled_at, location, invitee, scheduled_by
  )
  values (p_referral_id, ref.student_id, p_scheduled_at, v_where, p_invitee, auth.uid())
  returning id into v_id;

  update public.student_referrals
     set status = 'In_Progress',
         handled_by = coalesce(handled_by, auth.uid()),
         handled_at = coalesce(handled_at, now())
   where id = p_referral_id and status = 'Pending';

  v_when := to_char(p_scheduled_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');
  v_name := public.sms_student_name(ref.student_id);
  select school_name into v_school from public.sms_settings where id;

  if p_invitee in ('student', 'both') then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, ref.student_id, 'Meeting invitation',
            public.meeting_invitation_text(v_when, v_where));
  end if;

  if p_invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = ref.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Meeting invitation',
              public.meeting_invitation_text(v_when, v_where, v_name));
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', ref.student_id, v_id,
        public.meeting_invitation_sms(v_when, v_where, v_name, v_school));
    exception when others then
      raise warning 'schedule_referral_meeting sms failed: %', sqlerrm;
    end;
  end if;

  perform public.log_audit('Scheduled referral meeting', v_id::text);
  return v_id;
end;
$$;

revoke all on function public.schedule_referral_meeting(uuid, timestamptz, text, text)
  from public, anon;
grant execute on function public.schedule_referral_meeting(uuid, timestamptz, text, text)
  to authenticated;
