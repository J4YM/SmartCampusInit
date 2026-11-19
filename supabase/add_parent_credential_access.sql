-- TEST-ONLY: let registrar-issued (credential) parents use the availability
-- and meeting-response features.
--
-- Credential parents have no Supabase Auth user; they run on the `anon` role
-- (see add_parent_credentials.sql), so auth.uid() is null for them and the
-- authenticated-only policies / functions hide everything. This mirrors what
-- parent_interventions already does for the demo environment:
--
--   * anon SELECT on the availability tables and guidance_meetings
--   * submit_parent_availability / respond_to_meeting take an optional
--     p_parent_id, used when there is no signed-in user, and are granted to
--     anon.
--
-- NOT PRODUCTION-SAFE: anyone with the anon key who knows a parent's id can act
-- as that parent. Tighten before production (e.g. a real session per parent).
--
-- Run in Supabase SQL Editor AFTER add_parent_availability_scheduling.sql.
-- Idempotent: safe to re-run.

drop policy if exists "meeting_availability_rounds_anon_select"
  on public.meeting_availability_rounds;
create policy "meeting_availability_rounds_anon_select"
  on public.meeting_availability_rounds for select to anon using (true);

drop policy if exists "meeting_availability_slots_anon_select"
  on public.meeting_availability_slots;
create policy "meeting_availability_slots_anon_select"
  on public.meeting_availability_slots for select to anon using (true);

drop policy if exists "guidance_meetings_anon_select" on public.guidance_meetings;
create policy "guidance_meetings_anon_select"
  on public.guidance_meetings for select to anon
  using (invitee in ('parent', 'both')
         and status not in ('Awaiting_Guidance', 'Returned'));

-- Replace the old signatures (a different argument list would otherwise add an
-- overload and make named-argument calls ambiguous).
drop function if exists public.submit_parent_availability(uuid, timestamptz[]);
drop function if exists public.respond_to_meeting(uuid, boolean, text);

create or replace function public.submit_parent_availability(
  p_round_id uuid,
  p_slots timestamptz[],
  p_parent_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.meeting_availability_rounds;
  e public.escalation_reports;
  v_slots timestamptz[];
  v_count int;
  v_name text;
  v_parent record;
begin
  select * into r from public.meeting_availability_rounds
   where id = p_round_id for update;
  -- Same error whether the round does not exist or the caller is not linked,
  -- so round ids cannot be probed.
  if not found or not exists (
       select 1 from public.parent_student_links l
        where l.student_id = r.student_id and l.parent_id = coalesce(auth.uid(), p_parent_id)) then
    raise exception 'Availability request not found.' using errcode = '42501';
  end if;
  if r.status <> 'Open' then
    raise exception 'This availability request is no longer open.';
  end if;

  select * into e from public.escalation_reports
   where id = r.escalation_report_id;
  if not found or e.status <> 'Approved' or e.exclude_parent then
    raise exception 'This endorsement no longer needs your availability.';
  end if;

  v_count := coalesce(cardinality(p_slots), 0);
  if v_count < 1 or v_count > 10 then
    raise exception 'Offer between 1 and 10 times.';
  end if;
  if exists (select 1 from unnest(p_slots) s where s is null) then
    raise exception 'Every time must have a value.';
  end if;
  -- Times are compared and stored to the minute, so 3:00:30 is the same
  -- offer as 3:00:00.
  select array_agg(date_trunc('minute', s)) into v_slots from unnest(p_slots) s;
  if (select count(distinct s) from unnest(v_slots) s) <> v_count then
    raise exception 'The same time was offered twice.';
  end if;
  if exists (select 1 from unnest(v_slots) s where s <= now()) then
    raise exception 'Every time must be in the future.';
  end if;
  if exists (
    select 1
      from public.meeting_availability_slots sl
      join public.meeting_availability_rounds r2 on r2.id = sl.round_id
     where r2.escalation_report_id = r.escalation_report_id
       and sl.status = 'Declined'
       and date_trunc('minute', sl.slot_at) in (select s from unnest(v_slots) s)) then
    raise exception 'A time Guidance already declined cannot be offered again.';
  end if;

  insert into public.meeting_availability_slots (round_id, slot_at, status)
  select p_round_id, s, 'Offered' from unnest(v_slots) s;

  update public.meeting_availability_rounds
     set status = 'Offered', offered_at = now()
   where id = p_round_id;

  v_name := public.sms_student_name(r.student_id);

  insert into public.notifications (target_role, title, message)
  values ('Discipline_Officer'::app_role, 'Parent offered meeting times',
          'Parent offered ' || v_count || ' time(s) for ' || v_name
          || '. Guidance will review them.');
  insert into public.notifications (target_role, title, message)
  values ('Guidance_Counselor'::app_role, 'Parent offered meeting times',
          'Parent offered ' || v_count || ' time(s) for ' || v_name
          || '. Please approve one or decline.');

  for v_parent in
    select parent_id from public.parent_student_links
     where student_id = r.student_id and parent_id <> coalesce(auth.uid(), p_parent_id)
  loop
    insert into public.notifications (target_role, user_id, title, message)
    values ('Parent'::app_role, v_parent.parent_id, 'Meeting availability answered',
            'Another guardian already shared the available times for ' || v_name || '.');
  end loop;

  perform public.log_audit('Parent offered availability', p_round_id::text);
end;
$$;

create or replace function public.respond_to_meeting(
  p_meeting_id uuid,
  p_accept boolean,
  p_note text default null,
  p_parent_id uuid default null
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
     where l.student_id = m.student_id and l.parent_id = coalesce(auth.uid(), p_parent_id)) then
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
         response_by = coalesce(auth.uid(), p_parent_id),
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
grant execute on function public.submit_parent_availability(uuid, timestamptz[], uuid)
  to anon, authenticated;
grant execute on function public.respond_to_meeting(uuid, boolean, text, uuid)
  to anon, authenticated;
