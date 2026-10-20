-- Sanctions: every violation case ends with exactly one sanction record on the
-- student's file. A sanction is either handbook-based or custom, and may
-- affect enrollment (non-readmission / dismissal).
--
--   * sanctions                       - the record (one per violation)
--   * students.enrollment_standing    - Good | Non_Readmission | Dismissed
--   * record_sanction(...)            - DO / Admin records a sanction
--   * auto_record_minor(...)          - one-click path for classified Minor cases
--
-- While a case is Under_Investigation (with Guidance) record_sanction refuses
-- unless an override reason is given; the reason is stored, audit-logged and
-- the Guidance Counselors are notified.
--
-- Run in Supabase SQL Editor after add_incident_report_classification.sql
-- (needs log_audit, classified cases). add_guidance_investigations.sql must
-- also be run before an Under_Investigation case can be sanctioned early.
-- Idempotent.

alter table public.students
  add column if not exists enrollment_standing text not null default 'Good';

do $$
begin
  alter table public.students
    add constraint students_enrollment_standing_check
    check (enrollment_standing in ('Good', 'Non_Readmission', 'Dismissed'));
exception when duplicate_object then null;
end $$;

create table if not exists public.sanctions (
  id uuid primary key default gen_random_uuid(),
  violation_id uuid not null unique
    references public.student_violations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz not null default now(),
  basis text not null check (basis in ('handbook', 'custom')),
  handbook_offense_id uuid references public.handbook_offenses(id) on delete set null,
  sanction_type text not null check (sanction_type in (
    'warning', 'community_service', 'suspension',
    'non_readmission', 'dismissal', 'other')),
  description text not null,
  effective_on date not null default current_date,
  ends_on date,
  affects_enrollment boolean not null default false,
  override_reason text,
  created_at timestamptz not null default now(),
  constraint sanctions_enrollment_type_check check (
    affects_enrollment = (sanction_type in ('non_readmission', 'dismissal'))
  )
);

create index if not exists sanctions_student_id_idx on public.sanctions (student_id);

alter table public.sanctions enable row level security;

drop policy if exists "sanctions_staff_select" on public.sanctions;
create policy "sanctions_staff_select"
  on public.sanctions for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role,
     'Guidance_Counselor'::app_role, 'Registrar'::app_role));

drop policy if exists "sanctions_student_select" on public.sanctions;
create policy "sanctions_student_select"
  on public.sanctions for select to authenticated
  using (student_id = auth.uid());

drop policy if exists "sanctions_parent_select" on public.sanctions;
create policy "sanctions_parent_select"
  on public.sanctions for select to authenticated
  using (exists (
    select 1 from public.parent_student_links l
     where l.student_id = sanctions.student_id and l.parent_id = auth.uid()));

-- Writes happen only through the SECURITY DEFINER functions below.

-- ---------------------------------------------------------------------------
-- Internal: insert the sanction, resolve the case, update the student.
-- ---------------------------------------------------------------------------

create or replace function public._apply_sanction(
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
  v_student uuid;
  v_id uuid;
begin
  select student_id into v_student
    from public.student_violations where id = p_violation_id;

  insert into public.sanctions (
    violation_id, student_id, decided_by, basis, handbook_offense_id,
    sanction_type, description, effective_on, ends_on,
    affects_enrollment, override_reason
  )
  values (
    p_violation_id, v_student, auth.uid(), p_basis, p_handbook_offense_id,
    p_sanction_type, btrim(p_description),
    coalesce(p_effective_on, current_date), p_ends_on,
    p_affects_enrollment, nullif(btrim(coalesce(p_override_reason, '')), '')
  )
  returning id into v_id;

  update public.student_violations
     set status = 'Resolved',
         acknowledged_at = now(),
         penalty_imposed = concat_ws(' | ', nullif(penalty_imposed, ''), btrim(p_description))
   where id = p_violation_id;

  if p_affects_enrollment then
    update public.students
       set enrollment_standing =
             case when p_sanction_type = 'dismissal' then 'Dismissed'
                  else 'Non_Readmission' end,
           good_moral_status = false
     where id = v_student;
  end if;

  return v_id;
end;
$$;

revoke all on function public._apply_sanction(
  uuid, text, uuid, text, text, date, date, boolean, text) from public;

-- ---------------------------------------------------------------------------
-- record_sanction
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
  if current_user_role() not in
     ('Admin'::app_role, 'Discipline_Officer'::app_role) then
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
      raise exception 'This case is with Guidance. Enter a reason to sanction it early.';
    end if;
    update public.guidance_investigations
       set status = 'Complete', completed_at = now()
     where violation_id = p_violation_id and status = 'Open';
    begin
      insert into public.notifications (target_role, title, message)
      values (
        'Guidance_Counselor'::app_role,
        'Case sanctioned before investigation finished',
        public.sms_student_name(v.student_id)
          || '''s case was sanctioned early by the Discipline Officer: '
          || btrim(p_override_reason)
      );
    exception when others then
      raise warning 'record_sanction notify failed: %', sqlerrm;
    end;
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
  uuid, text, uuid, text, text, date, date, boolean, text) from public;
grant execute on function public.record_sanction(
  uuid, text, uuid, text, text, date, date, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- auto_record_minor — classified Minor offense, no investigation.
-- ---------------------------------------------------------------------------

create or replace function public.auto_record_minor(p_violation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.student_violations;
  v_category text;
  v_penalty text;
  v_id uuid;
begin
  if current_user_role() not in
     ('Admin'::app_role, 'Discipline_Officer'::app_role) then
    raise exception 'Only the Discipline Officer can record a violation.'
      using errcode = '42501';
  end if;

  select * into v from public.student_violations
   where id = p_violation_id for update;
  if not found then
    raise exception 'Report not found.';
  end if;
  if v.offense_id is null then
    raise exception 'Classify the report before recording it.';
  end if;
  if v.status <> 'Pending' then
    raise exception 'Only a pending case can be auto-recorded.';
  end if;

  select category::text, penalty_info into v_category, v_penalty
    from public.handbook_offenses where id = v.offense_id;
  if v_category <> 'Minor' then
    raise exception 'Only Minor offenses can be auto-recorded.';
  end if;

  v_id := public._apply_sanction(
    p_violation_id, 'handbook', v.offense_id, 'warning',
    coalesce(nullif(btrim(v_penalty), ''), 'Recorded per student handbook (Minor offense)'),
    current_date, null, false, null);

  perform public.log_audit('Auto-recorded minor violation', p_violation_id::text);
  return v_id;
end;
$$;

revoke all on function public.auto_record_minor(uuid) from public;
grant execute on function public.auto_record_minor(uuid) to authenticated;
