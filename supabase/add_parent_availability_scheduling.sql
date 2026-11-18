-- Parent availability scheduling for endorsement meetings.
--
--   1. After Guidance accepts an endorsement, the Discipline Officer asks the
--      parent for the times they are free (request_parent_availability). The
--      parent is told by Parent Portal notification and SMS. A "round" is one
--      such request.
--   2. The parent opens the Parent Portal and offers 1 to 10 future times
--      (submit_parent_availability). The round becomes 'Offered' and the DO and
--      Guidance are told.
--   3. (Later tasks) Guidance approves one time or declines, and the meeting
--      is created; a declined time is never offered again for the same
--      endorsement.
--
-- Tables are written only through the RPCs: there are no insert/update/delete
-- policies. Staff and the parents linked to the student can read.
--
-- Run in Supabase SQL Editor after add_endorsement_meetings.sql and
-- reword_meeting_invitations.sql. Idempotent.

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.meeting_availability_rounds (
  id uuid primary key default gen_random_uuid(),
  escalation_report_id uuid not null
    references public.escalation_reports(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  round_no int not null default 1,
  status text not null default 'Open',
  requested_by uuid references public.profiles(id) on delete set null,
  requested_at timestamptz not null default now(),
  reminded_at timestamptz,
  offered_at timestamptz,
  decided_at timestamptz,
  decision_note text,
  meeting_id uuid references public.guidance_meetings(id) on delete set null,
  constraint meeting_availability_rounds_status_check
    check (status in ('Open', 'Offered', 'Approved', 'Declined', 'Cancelled')),
  constraint meeting_availability_rounds_report_round_key
    unique (escalation_report_id, round_no)
);

create index if not exists meeting_availability_rounds_student_idx
  on public.meeting_availability_rounds (student_id, requested_at desc);

create table if not exists public.meeting_availability_slots (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null
    references public.meeting_availability_rounds(id) on delete cascade,
  slot_at timestamptz not null,
  status text not null default 'Offered',
  constraint meeting_availability_slots_status_check
    check (status in ('Offered', 'Approved', 'Declined', 'Not_Chosen'))
);

create index if not exists meeting_availability_slots_round_idx
  on public.meeting_availability_slots (round_id);

-- ---------------------------------------------------------------------------
-- 2. RLS: read only (writes go through the RPCs)
-- ---------------------------------------------------------------------------

alter table public.meeting_availability_rounds enable row level security;
alter table public.meeting_availability_slots enable row level security;

drop policy if exists "meeting_availability_rounds_staff_select"
  on public.meeting_availability_rounds;
create policy "meeting_availability_rounds_staff_select"
  on public.meeting_availability_rounds for select to authenticated
  using (current_user_role() in
         ('Admin'::app_role, 'Discipline_Officer'::app_role,
          'Guidance_Counselor'::app_role));

drop policy if exists "meeting_availability_rounds_parent_select"
  on public.meeting_availability_rounds;
create policy "meeting_availability_rounds_parent_select"
  on public.meeting_availability_rounds for select to authenticated
  using (exists (
    select 1 from public.parent_student_links l
     where l.student_id = meeting_availability_rounds.student_id
       and l.parent_id = auth.uid()));

drop policy if exists "meeting_availability_slots_staff_select"
  on public.meeting_availability_slots;
create policy "meeting_availability_slots_staff_select"
  on public.meeting_availability_slots for select to authenticated
  using (current_user_role() in
         ('Admin'::app_role, 'Discipline_Officer'::app_role,
          'Guidance_Counselor'::app_role));

drop policy if exists "meeting_availability_slots_parent_select"
  on public.meeting_availability_slots;
create policy "meeting_availability_slots_parent_select"
  on public.meeting_availability_slots for select to authenticated
  using (exists (
    select 1
      from public.meeting_availability_rounds r
      join public.parent_student_links l on l.student_id = r.student_id
     where r.id = meeting_availability_slots.round_id
       and l.parent_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- 3. SMS wording (each at most 300 characters)
-- ---------------------------------------------------------------------------

create or replace function public.availability_request_sms(
  p_name text,
  p_school text default null
)
returns text
language sql
immutable
as $$
  select left(
    'Please share the times you are free for a meeting regarding '
      || coalesce(p_name, 'your child')
      || '. Open the Parent Portal to choose your available times. - '
      || coalesce(p_school, 'STI Baliuag'),
    300);
$$;

create or replace function public.availability_retry_sms(
  p_name text,
  p_school text default null
)
returns text
language sql
immutable
as $$
  select left(
    'The times you offered for the meeting regarding '
      || coalesce(p_name, 'your child')
      || ' did not work. Please open the Parent Portal and offer other times. - '
      || coalesce(p_school, 'STI Baliuag'),
    300);
$$;

create or replace function public.meeting_scheduled_sms(
  p_when text,
  p_where text default null,
  p_name text default null,
  p_school text default null
)
returns text
language sql
immutable
as $$
  select left(
    'Your meeting is scheduled on ' || coalesce(p_when, 'the agreed time')
      || coalesce(' at ' || nullif(btrim(coalesce(p_where, '')), ''), '')
      || ' regarding ' || coalesce(p_name, 'your child')
      || '. Please confirm in the Parent Portal. - '
      || coalesce(p_school, 'STI Baliuag'),
    300);
$$;

-- ---------------------------------------------------------------------------
-- 4. The Discipline Officer asks the parent for their availability
-- ---------------------------------------------------------------------------

create or replace function public.request_parent_availability(p_report_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.escalation_reports;
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

  select * into e from public.escalation_reports where id = p_report_id for update;
  if not found then raise exception 'Endorsement not found.'; end if;
  if e.status <> 'Approved' then
    raise exception 'Guidance has not accepted this endorsement yet.';
  end if;
  if e.exclude_parent then
    raise exception 'The parent is excluded from this endorsement.';
  end if;
  if exists (select 1 from public.meeting_availability_rounds r
              where r.escalation_report_id = p_report_id
                and r.status in ('Open', 'Offered')) then
    raise exception 'An availability request is already in progress for this endorsement.';
  end if;
  if not exists (select 1 from public.parent_student_links l
                  where l.student_id = e.student_id) then
    raise exception 'This student has no linked parent.';
  end if;

  select coalesce(max(round_no), 0) + 1 into v_round_no
    from public.meeting_availability_rounds
   where escalation_report_id = p_report_id;

  insert into public.meeting_availability_rounds
    (escalation_report_id, student_id, round_no, status, requested_by)
  values (p_report_id, e.student_id, v_round_no, 'Open', auth.uid())
  returning id into v_round_id;

  v_name := public.sms_student_name(e.student_id);
  select school_name into v_school from public.sms_settings where id;

  for v_parent in
    select parent_id from public.parent_student_links where student_id = e.student_id
  loop
    insert into public.notifications (target_role, user_id, title, message)
    values ('Parent'::app_role, v_parent.parent_id, 'Meeting availability requested',
            'Student Affairs would like to meet with you regarding ' || v_name
            || '. Please open the Parent Portal and share the times you are free.');
  end loop;

  begin
    perform public.queue_sms(
      'availability_request', e.student_id, v_round_id,
      public.availability_request_sms(v_name, v_school));
  exception when others then
    raise warning 'request_parent_availability sms failed: %', sqlerrm;
  end;

  insert into public.notifications (target_role, title, message)
  values ('Guidance_Counselor'::app_role, 'Parent availability requested',
          'Student Affairs asked the parent of ' || v_name
          || ' for available meeting times.');

  perform public.log_audit('Requested parent availability', v_round_id::text);
  return v_round_id;
end;
$$;

revoke all on function public.request_parent_availability(uuid) from public, anon;
grant execute on function public.request_parent_availability(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The parent offers their available times
-- ---------------------------------------------------------------------------

create or replace function public.submit_parent_availability(
  p_round_id uuid,
  p_slots timestamptz[]
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
        where l.student_id = r.student_id and l.parent_id = auth.uid()) then
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
     where student_id = r.student_id and parent_id <> auth.uid()
  loop
    insert into public.notifications (target_role, user_id, title, message)
    values ('Parent'::app_role, v_parent.parent_id, 'Meeting availability answered',
            'Another guardian already shared the available times for ' || v_name || '.');
  end loop;

  perform public.log_audit('Parent offered availability', p_round_id::text);
end;
$$;

revoke all on function public.submit_parent_availability(uuid, timestamptz[])
  from public, anon;
grant execute on function public.submit_parent_availability(uuid, timestamptz[])
  to authenticated;
