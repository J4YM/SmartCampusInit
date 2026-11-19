-- Investigation meetings use the endorsement scheduling flow: the Discipline
-- Officer asks the parent for their availability, the parent offers times in the
-- Parent Portal, and the officer approves one. The Guidance Counselor is not
-- involved: an investigation the DO runs on its own needs no counselor approval,
-- so only the DO decides and nobody on the Guidance side is notified.
--
--   * meeting_availability_rounds may belong to an investigation instead of an
--     endorsement (exactly one of escalation_report_id / investigation_id).
--   * request_investigation_availability / decide_investigation_availability are
--     new, DO/Admin only. decide_parent_availability (Guidance, endorsements) is
--     untouched and refuses investigation rounds.
--   * submit_parent_availability (the parent), cancel_parent_availability and the
--     48-hour reminder job are updated to handle both kinds. They are generated
--     from their current definitions (add_parent_credential_access.sql and
--     add_parent_availability_scheduling.sql), so the endorsement behaviour is
--     unchanged.
--
-- Run in Supabase SQL Editor AFTER add_parent_availability_scheduling.sql,
-- add_parent_credential_access.sql and add_do_investigations.sql. Idempotent.

alter table public.meeting_availability_rounds
  alter column escalation_report_id drop not null;

alter table public.meeting_availability_rounds
  add column if not exists investigation_id uuid
    references public.guidance_investigations(id) on delete cascade;

alter table public.meeting_availability_rounds
  drop constraint if exists meeting_availability_rounds_one_subject_check;
alter table public.meeting_availability_rounds
  add constraint meeting_availability_rounds_one_subject_check
  check ((escalation_report_id is null) <> (investigation_id is null));

create unique index if not exists meeting_availability_rounds_investigation_round_key
  on public.meeting_availability_rounds (investigation_id, round_no)
  where investigation_id is not null;

create index if not exists meeting_availability_rounds_investigation_idx
  on public.meeting_availability_rounds (investigation_id)
  where investigation_id is not null;

-- ---------------------------------------------------------------------------
-- request_investigation_availability: the Discipline Officer asks the parent
-- ---------------------------------------------------------------------------
-- Same as request_parent_availability for an endorsement, except there is no
-- Guidance Counselor in the loop: investigations the DO runs on their own need
-- no counselor approval, so nobody on the Guidance side is notified.

create or replace function public.request_investigation_availability(
  p_investigation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  gi public.guidance_investigations;
  v_round_id uuid;
  v_round_no int;
  v_name text;
  v_school text;
  v_parent record;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can request the parent''s availability.'
      using errcode = '42501';
  end if;

  select * into gi from public.guidance_investigations
   where id = p_investigation_id for update;
  if not found then raise exception 'Investigation not found.'; end if;
  if gi.status <> 'Open' then
    raise exception 'This investigation is already complete.';
  end if;
  if exists (select 1 from public.meeting_availability_rounds r
              where r.investigation_id = p_investigation_id
                and r.status in ('Open', 'Offered')) then
    raise exception 'An availability request is already in progress for this investigation.';
  end if;
  if not exists (select 1 from public.parent_student_links l
                  where l.student_id = gi.student_id) then
    raise exception 'This student has no linked parent. Use Schedule meeting to arrange it directly.';
  end if;

  select coalesce(max(round_no), 0) + 1 into v_round_no
    from public.meeting_availability_rounds
   where investigation_id = p_investigation_id;

  insert into public.meeting_availability_rounds
    (investigation_id, student_id, round_no, status, requested_by)
  values (p_investigation_id, gi.student_id, v_round_no, 'Open', auth.uid())
  returning id into v_round_id;

  v_name := public.sms_student_name(gi.student_id);
  select school_name into v_school from public.sms_settings where id;

  for v_parent in
    select parent_id from public.parent_student_links where student_id = gi.student_id
  loop
    insert into public.notifications (target_role, user_id, title, message)
    values ('Parent'::app_role, v_parent.parent_id, 'Meeting availability requested',
            'Student Affairs would like to meet with you regarding ' || v_name
            || '. Please open the Parent Portal and share the times you are free.');
  end loop;

  begin
    perform public.queue_sms(
      'availability_request', gi.student_id, v_round_id,
      public.availability_request_sms(v_name, v_school));
  exception when others then
    raise warning 'request_investigation_availability sms failed: %', sqlerrm;
  end;

  perform public.log_audit('Requested parent availability', v_round_id::text);
  return v_round_id;
end;
$$;

revoke all on function public.request_investigation_availability(uuid)
  from public, anon;
grant execute on function public.request_investigation_availability(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- decide_investigation_availability: the Discipline Officer approves a time
-- ---------------------------------------------------------------------------
-- Approve one offered time (it becomes a 'Proposed' meeting for the parent) or
-- decline them all (a fresh round asks for other times). Only the DO decides:
-- decide_parent_availability, which Guidance uses for endorsements, finds no
-- endorsement behind an investigation round and refuses it.

create or replace function public.decide_investigation_availability(
  p_round_id uuid,
  p_slot_id uuid default null,
  p_location text default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.meeting_availability_rounds;
  gi public.guidance_investigations;
  sl public.meeting_availability_slots;
  v_where text;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_meeting_id uuid;
  v_new_round_id uuid;
  v_when text;
  v_name text;
  v_school text;
  v_parent record;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can decide on the offered times.'
      using errcode = '42501';
  end if;
  if length(coalesce(p_location, '')) > 120 then
    raise exception 'The location must be at most 120 characters.';
  end if;
  if length(coalesce(p_note, '')) > 500 then
    raise exception 'The note must be at most 500 characters.';
  end if;

  select * into r from public.meeting_availability_rounds
   where id = p_round_id for update;
  if not found then raise exception 'Availability request not found.'; end if;
  if r.investigation_id is null then
    raise exception 'This is not an investigation availability request.';
  end if;
  if r.status <> 'Offered' then
    raise exception 'This availability request is not waiting for a decision.';
  end if;

  select * into gi from public.guidance_investigations
   where id = r.investigation_id for update;
  if not found then raise exception 'Investigation not found.'; end if;

  v_name := public.sms_student_name(r.student_id);
  select school_name into v_school from public.sms_settings where id;

  if p_slot_id is not null then
    -- ---- approve ----
    if gi.status <> 'Open' then
      raise exception 'This investigation no longer needs a parent meeting.';
    end if;

    select * into sl from public.meeting_availability_slots
     where id = p_slot_id and round_id = p_round_id and status = 'Offered'
     for update;
    if not found then
      raise exception 'That time does not belong to this availability request.';
    end if;
    if sl.slot_at <= now() then
      raise exception 'That time has already passed.';
    end if;

    v_where := coalesce(nullif(btrim(coalesce(p_location, '')), ''),
                        'Guidance Office');

    -- The new invitation replaces the investigation's earlier live ones.
    update public.guidance_meetings
       set status = 'Cancelled'
     where investigation_id = r.investigation_id
       and status in ('Proposed', 'Confirmed', 'Reschedule_Requested');

    insert into public.guidance_meetings (
      investigation_id, student_id, scheduled_at, location, invitee,
      scheduled_by, status
    )
    values (r.investigation_id, r.student_id, sl.slot_at, v_where,
            'parent', auth.uid(), 'Proposed')
    returning id into v_meeting_id;

    update public.meeting_availability_slots
       set status = case when id = p_slot_id then 'Approved' else 'Not_Chosen' end
     where round_id = p_round_id;

    update public.meeting_availability_rounds
       set status = 'Approved', decided_at = now(), decision_note = v_note,
           meeting_id = v_meeting_id
     where id = p_round_id;

    v_when := to_char(sl.slot_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');

    for v_parent in
      select parent_id from public.parent_student_links
       where student_id = r.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Meeting scheduled',
              public.meeting_invitation_text(v_when, v_where, v_name));
    end loop;

    begin
      perform public.queue_sms(
        'guidance_meeting', r.student_id, v_meeting_id,
        public.meeting_scheduled_sms(v_when, v_where, v_name, v_school));
    exception when others then
      raise warning 'decide_investigation_availability sms failed: %', sqlerrm;
    end;

    perform public.log_audit('Approved parent availability', p_round_id::text);
  else
    -- ---- decline all ----
    update public.meeting_availability_slots
       set status = 'Declined'
     where round_id = p_round_id;

    update public.meeting_availability_rounds
       set status = 'Declined', decided_at = now(), decision_note = v_note
     where id = p_round_id;

    if gi.status = 'Open' then
      insert into public.meeting_availability_rounds
        (investigation_id, student_id, round_no, status, requested_by,
         requested_at)
      values (r.investigation_id, r.student_id,
              (select max(round_no) + 1 from public.meeting_availability_rounds
                where investigation_id = r.investigation_id),
              'Open', r.requested_by, now())
      returning id into v_new_round_id;

      for v_parent in
        select parent_id from public.parent_student_links
         where student_id = r.student_id
      loop
        insert into public.notifications (target_role, user_id, title, message)
        values ('Parent'::app_role, v_parent.parent_id,
                'Meeting availability requested',
                'The times you offered for the meeting regarding ' || v_name
                || ' did not work. Please open the Parent Portal and offer other times.'
                || coalesce(' Note from Student Affairs: ' || v_note, ''));
      end loop;

      begin
        perform public.queue_sms(
          'availability_retry', r.student_id, v_new_round_id,
          public.availability_retry_sms(v_name, v_school));
      exception when others then
        raise warning 'decide_investigation_availability sms failed: %', sqlerrm;
      end;
    end if;

    perform public.log_audit('Declined parent availability', p_round_id::text);
  end if;
end;
$$;

revoke all on function public.decide_investigation_availability(uuid, uuid, text, text)
  from public, anon;
grant execute on function public.decide_investigation_availability(uuid, uuid, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Shared functions, now handling both endorsement and investigation rounds
-- ---------------------------------------------------------------------------

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
  gi public.guidance_investigations;
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

  if r.investigation_id is not null then
    select * into gi from public.guidance_investigations
     where id = r.investigation_id;
    if not found or gi.status <> 'Open' then
      raise exception 'This investigation no longer needs your availability.';
    end if;
  else
    select * into e from public.escalation_reports
     where id = r.escalation_report_id;
    if not found or e.status <> 'Approved' or e.exclude_parent then
      raise exception 'This endorsement no longer needs your availability.';
    end if;
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
     where ((r.escalation_report_id is not null
             and r2.escalation_report_id = r.escalation_report_id)
         or (r.investigation_id is not null
             and r2.investigation_id = r.investigation_id))
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
          || case when r.investigation_id is not null
                  then '. Please choose one or decline them.'
                  else '. Guidance will review them.' end);
  -- Investigations the DO runs alone involve no counselor.
  if r.escalation_report_id is not null then
    insert into public.notifications (target_role, title, message)
    values ('Guidance_Counselor'::app_role, 'Parent offered meeting times',
            'Parent offered ' || v_count || ' time(s) for ' || v_name
            || '. Please approve one or decline.');
  end if;

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

grant execute on function public.submit_parent_availability(uuid, timestamptz[], uuid)
  to anon, authenticated;

create or replace function public.cancel_parent_availability(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.meeting_availability_rounds;
  v_role app_role := current_user_role();
  v_name text;
begin
  if not coalesce(v_role in
     ('Admin'::app_role, 'Discipline_Officer'::app_role,
      'Guidance_Counselor'::app_role), false) then
    raise exception 'Only staff can cancel an availability request.'
      using errcode = '42501';
  end if;

  select * into r from public.meeting_availability_rounds
   where id = p_round_id for update;
  if not found then raise exception 'Availability request not found.'; end if;
  if r.investigation_id is not null
     and not coalesce(v_role in
       ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can cancel an investigation availability request.'
      using errcode = '42501';
  end if;
  if r.status not in ('Open', 'Offered') then
    raise exception 'Only an open availability request can be cancelled.';
  end if;

  update public.meeting_availability_rounds
     set status = 'Cancelled', decided_at = now()
   where id = p_round_id;

  v_name := public.sms_student_name(r.student_id);

  if r.escalation_report_id is not null
     and v_role is distinct from 'Guidance_Counselor'::app_role then
    insert into public.notifications (target_role, title, message)
    values ('Guidance_Counselor'::app_role, 'Parent availability request cancelled',
            'The availability request for ' || v_name || ' was cancelled.');
  end if;
  if v_role is distinct from 'Discipline_Officer'::app_role then
    insert into public.notifications (target_role, title, message)
    values ('Discipline_Officer'::app_role, 'Parent availability request cancelled',
            'The availability request for ' || v_name || ' was cancelled.');
  end if;

  perform public.log_audit('Cancelled parent availability', p_round_id::text);
end;
$$;

revoke all on function public.cancel_parent_availability(uuid) from public, anon;
grant execute on function public.cancel_parent_availability(uuid) to authenticated;

create or replace function public.remind_stale_availability_rounds()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count int := 0;
  v_name text;
  v_school text;
  v_parent record;
begin
  select school_name into v_school from public.sms_settings where id;

  for r in
    select ro.id, ro.student_id
      from public.meeting_availability_rounds ro
      left join public.escalation_reports e on e.id = ro.escalation_report_id
      left join public.guidance_investigations gi on gi.id = ro.investigation_id
     where ro.status = 'Open'
       and ro.reminded_at is null
       and ro.requested_at < now() - interval '48 hours'
       and ((e.status = 'Approved' and not e.exclude_parent)
            or gi.status = 'Open')
     for update of ro skip locked
  loop
    update public.meeting_availability_rounds
       set reminded_at = now()
     where id = r.id;

    v_name := public.sms_student_name(r.student_id);

    for v_parent in
      select parent_id from public.parent_student_links
       where student_id = r.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id,
              'Reminder: meeting availability',
              'Student Affairs is still waiting for the times you are free to meet regarding '
              || v_name || '. Please open the Parent Portal and share them.');
    end loop;

    begin
      perform public.queue_sms(
        'availability_reminder', r.student_id, r.id,
        public.availability_request_sms(v_name, v_school));
    exception when others then
      raise warning 'remind_stale_availability_rounds sms failed: %', sqlerrm;
    end;

    insert into public.notifications (target_role, title, message)
    values ('Discipline_Officer'::app_role, 'Parent has not shared availability',
            'The parent of ' || v_name
            || ' has not answered the availability request after 48 hours. A reminder was sent.');

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.remind_stale_availability_rounds()
  from public, anon, authenticated;
