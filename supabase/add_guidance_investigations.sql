-- Guidance investigations and two-way meeting acknowledgement.
--
-- The DO escalates a classified case to Guidance. The counselor schedules a
-- meeting with the student and/or parent; the invitee confirms or declines in
-- their own dashboard; the counselor records the outcome and findings, which
-- unlocks the DO's sanction (violation -> 'Investigation_Complete').
--
--   guidance_investigations  one per escalated case
--   guidance_meetings        one or more per investigation
--   escalate_to_guidance / schedule_guidance_meeting / respond_to_meeting /
--   set_meeting_outcome / complete_investigation
--
-- Run in Supabase SQL Editor after add_sanctions_schema.sql and
-- add_incident_report_classification.sql. Idempotent.

create table if not exists public.guidance_investigations (
  id uuid primary key default gen_random_uuid(),
  violation_id uuid not null unique
    references public.student_violations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  assigned_to uuid references public.profiles(id) on delete set null,
  status text not null default 'Open' check (status in ('Open', 'Complete')),
  findings text,
  recommendation text,
  escalated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists guidance_investigations_student_idx
  on public.guidance_investigations (student_id);

create table if not exists public.guidance_meetings (
  id uuid primary key default gen_random_uuid(),
  investigation_id uuid not null
    references public.guidance_investigations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  scheduled_at timestamptz not null,
  location text,
  invitee text not null check (invitee in ('student', 'parent', 'both')),
  status text not null default 'Proposed' check (status in (
    'Proposed', 'Confirmed', 'Declined', 'Reschedule_Requested',
    'Completed', 'Missed', 'Cancelled')),
  scheduled_by uuid references public.profiles(id) on delete set null,
  response_by uuid references public.profiles(id) on delete set null,
  responded_at timestamptz,
  response_note text,
  created_at timestamptz not null default now()
);

create index if not exists guidance_meetings_student_idx
  on public.guidance_meetings (student_id, scheduled_at desc);

alter table public.guidance_investigations enable row level security;
alter table public.guidance_meetings enable row level security;

drop policy if exists "guidance_investigations_staff_select" on public.guidance_investigations;
create policy "guidance_investigations_staff_select"
  on public.guidance_investigations for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role));

drop policy if exists "guidance_meetings_staff_select" on public.guidance_meetings;
create policy "guidance_meetings_staff_select"
  on public.guidance_meetings for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role));

-- The invitee reads their own meetings (never the investigation findings).
drop policy if exists "guidance_meetings_student_select" on public.guidance_meetings;
create policy "guidance_meetings_student_select"
  on public.guidance_meetings for select to authenticated
  using (student_id = auth.uid() and invitee in ('student', 'both'));

drop policy if exists "guidance_meetings_parent_select" on public.guidance_meetings;
create policy "guidance_meetings_parent_select"
  on public.guidance_meetings for select to authenticated
  using (invitee in ('parent', 'both') and exists (
    select 1 from public.parent_student_links l
     where l.student_id = guidance_meetings.student_id and l.parent_id = auth.uid()));

-- All writes go through the SECURITY DEFINER functions below.

do $$
begin
  alter publication supabase_realtime add table public.guidance_meetings;
exception when duplicate_object then null;
end $$;

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
  if current_user_role() not in
     ('Admin'::app_role, 'Discipline_Officer'::app_role) then
    raise exception 'Only the Discipline Officer can escalate a case.'
      using errcode = '42501';
  end if;

  select * into v from public.student_violations
   where id = p_violation_id for update;
  if not found then raise exception 'Report not found.'; end if;
  if v.offense_id is null then
    raise exception 'Classify the report before escalating it.';
  end if;
  if v.status <> 'Pending' then
    raise exception 'Only a pending case can be escalated to Guidance.';
  end if;

  insert into public.guidance_investigations (violation_id, student_id, escalated_by)
  values (p_violation_id, v.student_id, auth.uid())
  returning id into v_id;

  update public.student_violations
     set status = 'Under_Investigation', is_escalated = true
   where id = p_violation_id;

  begin
    insert into public.notifications (target_role, title, message)
    values (
      'Guidance_Counselor'::app_role,
      'Case escalated for investigation',
      public.sms_student_name(v.student_id)
        || '''s case was escalated by the Discipline Officer. Schedule a meeting under Investigations.'
    );
  exception when others then
    raise warning 'escalate_to_guidance notify failed: %', sqlerrm;
  end;

  perform public.log_audit('Escalated case to Guidance', p_violation_id::text);
  return v_id;
end;
$$;

revoke all on function public.escalate_to_guidance(uuid) from public;
grant execute on function public.escalate_to_guidance(uuid) to authenticated;

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
  if current_user_role() not in
     ('Admin'::app_role, 'Guidance_Counselor'::app_role) then
    raise exception 'Only the Guidance Counselor can schedule a meeting.'
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
    values ('Student'::app_role, inv.student_id, 'Guidance meeting scheduled',
      'You are invited to a guidance meeting on ' || v_when
      || coalesce(' at ' || nullif(btrim(coalesce(p_location, '')), ''), '')
      || '. Please confirm in your dashboard.');
  end if;

  if p_invitee in ('parent', 'both') then
    for v_parent in
      select parent_id from public.parent_student_links where student_id = inv.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Guidance meeting scheduled',
        public.sms_student_name(inv.student_id) || '''s guidance meeting is on ' || v_when
        || coalesce(' at ' || nullif(btrim(coalesce(p_location, '')), ''), '')
        || '. Please confirm in the Parent Portal.');
    end loop;
    begin
      perform public.queue_sms(
        'guidance_meeting', inv.student_id, v_id,
        'STI Baliuag: a guidance meeting for ' || public.sms_student_name(inv.student_id)
        || ' is set for ' || v_when || '. Please confirm in the Parent Portal.');
    exception when others then
      raise warning 'schedule_guidance_meeting sms failed: %', sqlerrm;
    end;
  end if;

  perform public.log_audit('Scheduled guidance meeting', v_id::text);
  return v_id;
end;
$$;

revoke all on function public.schedule_guidance_meeting(uuid, timestamptz, text, text) from public;
grant execute on function public.schedule_guidance_meeting(uuid, timestamptz, text, text)
  to authenticated;

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
      'Guidance_Counselor'::app_role,
      case when p_accept then 'Meeting confirmed' else 'Meeting declined' end,
      public.sms_student_name(m.student_id)
        || case when p_accept then ' confirmed' else ' cannot attend' end
        || ' the guidance meeting.'
        || coalesce(' Note: ' || nullif(btrim(coalesce(p_note, '')), ''), '')
    );
  exception when others then
    raise warning 'respond_to_meeting notify failed: %', sqlerrm;
  end;
end;
$$;

revoke all on function public.respond_to_meeting(uuid, boolean, text) from public;
grant execute on function public.respond_to_meeting(uuid, boolean, text) to authenticated;

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
  if current_user_role() not in
     ('Admin'::app_role, 'Guidance_Counselor'::app_role) then
    raise exception 'Only the Guidance Counselor can set a meeting outcome.'
      using errcode = '42501';
  end if;
  if p_status not in ('Completed', 'Missed', 'Cancelled') then
    raise exception 'Outcome must be Completed, Missed or Cancelled.';
  end if;
  update public.guidance_meetings set status = p_status where id = p_meeting_id;
  if not found then raise exception 'Meeting not found.'; end if;
  perform public.log_audit('Set meeting outcome: ' || p_status, p_meeting_id::text);
end;
$$;

revoke all on function public.set_meeting_outcome(uuid, text) from public;
grant execute on function public.set_meeting_outcome(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------

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
  if current_user_role() not in
     ('Admin'::app_role, 'Guidance_Counselor'::app_role) then
    raise exception 'Only the Guidance Counselor can complete an investigation.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_findings, '')) = '' then
    raise exception 'Findings are required.';
  end if;

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

  begin
    insert into public.notifications (target_role, title, message)
    values (
      'Discipline_Officer'::app_role,
      'Investigation complete',
      public.sms_student_name(inv.student_id)
        || '''s investigation is complete. The case is ready for a sanction.'
    );
  exception when others then
    raise warning 'complete_investigation notify failed: %', sqlerrm;
  end;

  perform public.log_audit('Completed guidance investigation', inv.violation_id::text);
end;
$$;

revoke all on function public.complete_investigation(uuid, text, text) from public;
grant execute on function public.complete_investigation(uuid, text, text) to authenticated;
