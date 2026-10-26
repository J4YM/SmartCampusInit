-- Meetings scheduled from a Guidance Referral.
--
-- The Guidance Associate invites the student, the parent, or both, exactly
-- like an investigation meeting (add_do_investigations.sql):
--   * the invitee confirms or declines in their own dashboard
--     (respond_to_meeting), and the reply goes to Guidance;
--   * student invited -> portal notification only;
--   * parent invited  -> portal notification AND an SMS;
--   * a student-only meeting never reaches the parent (private cases).
--
-- Run in Supabase SQL Editor after add_guidance_referrals.sql and
-- add_do_investigations.sql. Idempotent. Re-running add_do_investigations.sql
-- afterwards restores its respond_to_meeting / set_meeting_outcome: run this
-- file again.

-- ---------------------------------------------------------------------------
-- 1. Meetings that belong to a referral
-- ---------------------------------------------------------------------------

alter table public.guidance_meetings
  add column if not exists referral_id uuid
    references public.student_referrals(id) on delete cascade;

alter table public.guidance_meetings
  drop constraint if exists guidance_meetings_has_parent_check;
alter table public.guidance_meetings
  add constraint guidance_meetings_has_parent_check
  check (investigation_id is not null
         or escalation_report_id is not null
         or referral_id is not null);

create index if not exists guidance_meetings_referral_idx
  on public.guidance_meetings (referral_id);

drop policy if exists "guidance_meetings_staff_select" on public.guidance_meetings;
create policy "guidance_meetings_staff_select"
  on public.guidance_meetings for select to authenticated
  using (
    current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role)
    or (current_user_role() = 'Guidance_Counselor'::app_role
        and (escalation_report_id is not null or referral_id is not null))
  );

-- ---------------------------------------------------------------------------
-- 2. schedule_referral_meeting
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

  if p_invitee in ('student', 'both') then
    insert into public.notifications (target_role, user_id, title, message)
    values ('Student'::app_role, ref.student_id, 'Guidance meeting scheduled',
      'You are invited to a guidance meeting on ' || v_when
      || coalesce(' at ' || v_where, '')
      || '. Please confirm in your dashboard.');
  end if;

  if p_invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = ref.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Guidance meeting scheduled',
        public.sms_student_name(ref.student_id) || '''s guidance meeting is on ' || v_when
        || coalesce(' at ' || v_where, '')
        || '. Please confirm in the Parent Portal.');
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', ref.student_id, v_id,
        'STI Baliuag: a guidance meeting for ' || public.sms_student_name(ref.student_id)
        || ' is set for ' || v_when || '. Please confirm in the Parent Portal.');
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

-- ---------------------------------------------------------------------------
-- 3. Replies reach Guidance for referral and endorsement meetings
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
      case when m.escalation_report_id is not null or m.referral_id is not null
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
-- 4. set_meeting_outcome: Guidance closes out its own referral meetings
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
  v_is_referral boolean;
begin
  select (referral_id is not null) into v_is_referral
    from public.guidance_meetings where id = p_meeting_id;

  if not coalesce(
       current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role)
       or (coalesce(v_is_referral, false)
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
