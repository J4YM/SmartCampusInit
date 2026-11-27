-- Defense revisions: sanction status tracking, parent acknowledgment, parent
-- meeting confirmation, behavior categories, suspension visibility.
--
--   * sanctions.status            Pending | Serving | Completed (#4)
--   * refresh_sanction_statuses() flips Pending->Serving on effective_on and
--                                 Serving->Completed after ends_on (suspension
--                                 and community service only; warnings with no
--                                 end date stay manual)
--   * set_sanction_status(...)    DO / Admin override
--   * sanctions.parent_ack_*      parent acknowledgment of the notice (#5)
--   * my_sanction_history(...)    now also returns violation_id + status (#1, #4)
--   * suspended_students_for_professor()  active suspensions among a
--                                 professor's enrolled students (#3)
--   * guidance_meetings.parent_*  parent-attended confirmation + summary (#8)
--   * confirm_parent_meeting(...) records it (DO / Guidance / Admin)
--   * handbook_offenses.behavior_category, student_violations.behavior_category (#11)
--
-- Suspension start/end reuse sanctions.effective_on / ends_on (no duplicate
-- columns). The 1st/2nd/3rd offense tier is computed from violation history in
-- the app, so it stays right when a violation is reclassified.
--
-- Run in Supabase SQL Editor after add_sanctions_schema.sql,
-- add_sanction_history.sql and add_meeting_completion_log.sql. Idempotent.
-- Re-running add_sanction_history.sql afterwards restores the old
-- my_sanction_history (without violation_id and status): run this file again.
-- Verify with test_defense_revisions.sql.

-- ---------------------------------------------------------------------------
-- #4 sanction status
-- ---------------------------------------------------------------------------
alter table public.sanctions
  add column if not exists status text not null default 'Pending',
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid references public.profiles(id) on delete set null;

do $$
begin
  alter table public.sanctions
    add constraint sanctions_status_check
    check (status in ('Pending', 'Serving', 'Completed'));
exception when duplicate_object then null;
end $$;

-- Sanctions that already ended before this ran count as completed.
update public.sanctions
   set status = 'Completed', completed_at = coalesce(completed_at, ends_on::timestamptz)
 where status = 'Pending' and ends_on is not null and ends_on < current_date;

create or replace function public.refresh_sanction_statuses()
returns void
language sql
security definer
set search_path = public
as $$
  update public.sanctions
     set status = 'Serving'
   where status = 'Pending'
     and sanction_type in ('suspension', 'community_service')
     and effective_on <= current_date
     and (ends_on is null or ends_on >= current_date);

  update public.sanctions
     set status = 'Completed', completed_at = coalesce(completed_at, now())
   where status in ('Pending', 'Serving')
     and ends_on is not null
     and ends_on < current_date;
$$;

revoke all on function public.refresh_sanction_statuses() from public;
grant execute on function public.refresh_sanction_statuses() to anon, authenticated;

create or replace function public.set_sanction_status(
  p_sanction_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() not in
     ('Admin'::app_role, 'Discipline_Officer'::app_role) then
    raise exception 'Only the Discipline Officer or Admin can update a sanction.'
      using errcode = '42501';
  end if;
  if p_status not in ('Pending', 'Serving', 'Completed') then
    raise exception 'Invalid sanction status: %', p_status;
  end if;

  update public.sanctions
     set status = p_status,
         completed_at = case when p_status = 'Completed' then now() else null end,
         completed_by = case when p_status = 'Completed' then auth.uid() else null end
   where id = p_sanction_id;
end;
$$;

revoke all on function public.set_sanction_status(uuid, text) from public, anon;
grant execute on function public.set_sanction_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- #5 parent acknowledgment (recorded after the signed notice comes back)
-- ---------------------------------------------------------------------------
alter table public.sanctions
  add column if not exists parent_ack_at timestamptz,
  add column if not exists parent_ack_name text;

create or replace function public.record_parent_acknowledgment(
  p_sanction_id uuid,
  p_parent_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() not in
     ('Admin'::app_role, 'Discipline_Officer'::app_role) then
    raise exception 'Only the Discipline Officer or Admin can record this.'
      using errcode = '42501';
  end if;
  update public.sanctions
     set parent_ack_at = now(),
         parent_ack_name = nullif(btrim(coalesce(p_parent_name, '')), '')
   where id = p_sanction_id;
end;
$$;

revoke all on function public.record_parent_acknowledgment(uuid, text) from public, anon;
grant execute on function public.record_parent_acknowledgment(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- my_sanction_history: add violation_id + status (return type changes, so drop)
-- ---------------------------------------------------------------------------
drop function if exists public.my_sanction_history(uuid, uuid);

create or replace function public.my_sanction_history(
  p_student_id uuid,
  p_parent_id uuid default null
)
returns table (
  id uuid,
  sanction_type text,
  description text,
  effective_on date,
  ends_on date,
  affects_enrollment boolean,
  decided_at timestamptz,
  violation_id uuid,
  status text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed boolean := false;
begin
  if v_uid is not null then
    v_allowed := coalesce(current_user_role() in
                   ('Admin'::app_role, 'Discipline_Officer'::app_role,
                    'Guidance_Counselor'::app_role, 'Registrar'::app_role), false)
                 or v_uid = p_student_id
                 or exists (select 1 from public.parent_student_links l
                             where l.student_id = p_student_id
                               and l.parent_id = v_uid);
  elsif p_parent_id is not null then
    v_allowed := exists (select 1 from public.parent_student_links l
                          where l.student_id = p_student_id
                            and l.parent_id = p_parent_id);
  else
    v_allowed := true;
  end if;

  if not v_allowed then
    raise exception 'You cannot view this sanction history.' using errcode = '42501';
  end if;

  perform public.refresh_sanction_statuses();

  return query
    select s.id, s.sanction_type, s.description, s.effective_on, s.ends_on,
           s.affects_enrollment, s.decided_at, s.violation_id, s.status
      from public.sanctions s
     where s.student_id = p_student_id
     order by s.decided_at desc, s.effective_on desc;
end;
$$;

revoke all on function public.my_sanction_history(uuid, uuid) from public;
grant execute on function public.my_sanction_history(uuid, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- #3 professors see active suspensions among their students
-- ---------------------------------------------------------------------------
create or replace function public.suspended_students_for_professor()
returns table (
  student_id uuid,
  student_name text,
  student_number text,
  subject_title text,
  effective_on date,
  ends_on date
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if current_user_role() not in
     ('Professor'::app_role, 'Admin'::app_role) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  return query
    select distinct st.id,
           btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
           st.student_number,
           sub.title,
           s.effective_on,
           s.ends_on
      from public.sanctions s
      join public.students st on st.id = s.student_id
      join public.profiles p on p.id = st.id
      join public.enrollments e on e.student_id = st.id and e.status = 'Active'
      join public.class_sections cs on cs.id = e.class_section_id
      join public.subjects sub on sub.id = cs.subject_id
     where s.sanction_type = 'suspension'
       and s.status <> 'Completed'
       and s.effective_on <= current_date + 7
       and (s.ends_on is null or s.ends_on >= current_date)
       and (current_user_role() = 'Admin'::app_role or cs.professor_id = auth.uid())
     order by 2;
end;
$$;

revoke all on function public.suspended_students_for_professor() from public, anon;
grant execute on function public.suspended_students_for_professor() to authenticated;

-- ---------------------------------------------------------------------------
-- #8 parent meeting confirmation
-- ---------------------------------------------------------------------------
alter table public.guidance_meetings
  add column if not exists parent_attended boolean,
  add column if not exists parent_confirmed_at timestamptz,
  add column if not exists parent_confirmed_by uuid references public.profiles(id) on delete set null,
  add column if not exists summary text;

create or replace function public.confirm_parent_meeting(
  p_meeting_id uuid,
  p_attended boolean,
  p_summary text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_user_role() not in
     ('Admin'::app_role, 'Discipline_Officer'::app_role,
      'Guidance_Counselor'::app_role) then
    raise exception 'Only Student Affairs, Guidance or Admin can confirm this.'
      using errcode = '42501';
  end if;
  update public.guidance_meetings
     set parent_attended = p_attended,
         parent_confirmed_at = now(),
         parent_confirmed_by = auth.uid(),
         summary = nullif(btrim(coalesce(p_summary, '')), '')
   where id = p_meeting_id
     and invitee in ('parent', 'both');
  if not found then
    raise exception 'No parent meeting found.';
  end if;
end;
$$;

revoke all on function public.confirm_parent_meeting(uuid, boolean, text) from public, anon;
grant execute on function public.confirm_parent_meeting(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- #11 behavior categories (alongside Minor / Major A-D, which are unchanged)
-- ---------------------------------------------------------------------------
alter table public.handbook_offenses
  add column if not exists behavior_category text;
alter table public.student_violations
  add column if not exists behavior_category text;

do $$
begin
  alter table public.handbook_offenses
    add constraint handbook_offenses_behavior_category_check
    check (behavior_category is null or behavior_category in (
      'Academic_Integrity', 'Attendance_Tardiness', 'Uniform_Dress_Code',
      'Property_Damage', 'Disruptive_Conduct', 'Digital_Device_Policy', 'Other'));
exception when duplicate_object then null;
end $$;
do $$
begin
  alter table public.student_violations
    add constraint student_violations_behavior_category_check
    check (behavior_category is null or behavior_category in (
      'Academic_Integrity', 'Attendance_Tardiness', 'Uniform_Dress_Code',
      'Property_Damage', 'Disruptive_Conduct', 'Digital_Device_Policy', 'Other'));
exception when duplicate_object then null;
end $$;

-- Seed existing handbook offenses from their wording (only where unset).
update public.handbook_offenses set behavior_category = case
  when description ~* '(cheat|plagiar|exam|quiz|forg|falsif|academic)' then 'Academic_Integrity'
  when description ~* '(late|tardy|tardiness|absen|cutting class|truan)' then 'Attendance_Tardiness'
  when description ~* '(uniform|dress|haircut|hair|id card|identification|attire)' then 'Uniform_Dress_Code'
  when description ~* '(damag|vandal|destroy|deface|property|facilit|steal|theft)' then 'Property_Damage'
  when description ~* '(phone|gadget|device|online|internet|social media|cyber|website|software|digital|game)' then 'Digital_Device_Policy'
  when description ~* '(disrupt|disrespect|fight|bully|noise|rude|insubordinat|misbehav|conduct|harass|threat)' then 'Disruptive_Conduct'
  else 'Other' end
 where behavior_category is null;

-- A violation inherits its offense's category when none was chosen.
update public.student_violations v
   set behavior_category = o.behavior_category
  from public.handbook_offenses o
 where v.offense_id = o.id and v.behavior_category is null;

-- When the Discipline Officer classifies a violation (sets offense_id), the
-- violation takes its offense's behavior category unless one was already set.
create or replace function public.violation_inherit_behavior_category()
returns trigger
language plpgsql
as $$
begin
  if new.behavior_category is null and new.offense_id is not null then
    select o.behavior_category into new.behavior_category
      from public.handbook_offenses o where o.id = new.offense_id;
  end if;
  return new;
end;
$$;

drop trigger if exists violation_inherit_behavior_category_trg on public.student_violations;
create trigger violation_inherit_behavior_category_trg
  before insert or update of offense_id on public.student_violations
  for each row execute function public.violation_inherit_behavior_category();
