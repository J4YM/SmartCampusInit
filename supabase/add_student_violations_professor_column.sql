-- Adds student_violations.professor_id — the "Teacher / Adviser" the kiosk's
-- self-report violation screen already asks the student to pick
-- (packages/student_kiosk_module/lib/screens/violation_kiosk_screen.dart's
-- _TeacherDropdownCard), which until now was pure UI with nowhere to land:
-- its selection was never read anywhere, let alone persisted. This is the
-- subject professor/adviser the violation happened under (e.g. who the
-- student was in class with) — distinct from `reported_by`, which is
-- always the kiosk's own fixed system identity for a self-report (see
-- add_kiosk_violation_insert_schema.sql).
--
-- Nullable: the Security Personnel report flow (SecurityReportScreen) has
-- no equivalent picker and never supplies this; a self-report where the
-- student didn't pick a teacher also leaves it null rather than blocking
-- submission (matches that dropdown's existing optional behavior).
--
-- Run in Supabase SQL Editor, after add_discipline_officer_schema.sql and
-- add_admission_slips_schema.sql.

alter table public.student_violations
  add column if not exists professor_id uuid references public.profiles(id) on delete set null;

create index if not exists student_violations_professor_id_idx
  on public.student_violations (professor_id)
  where professor_id is not null;

-- ---------------------------------------------------------------------------
-- submit_admission_slip gains an optional p_professor_id, stamped onto
-- every student_violations row this call inserts. Adding a new trailing
-- default-valued parameter is a compatible `create or replace` — existing
-- callers (SecurityReportScreen's flow) that don't pass it keep working
-- unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.submit_admission_slip(
  p_slip_id uuid,
  p_student_id uuid,
  p_reported_by uuid,
  p_offense_ids uuid[],
  p_is_escalated boolean default false,
  p_incident_notes text default null,
  p_professor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if array_length(p_offense_ids, 1) is null then
    raise exception 'At least one offense is required.';
  end if;

  insert into public.admission_slips (id, student_id, reported_by)
  values (p_slip_id, p_student_id, p_reported_by);

  insert into public.student_violations (
    student_id, offense_id, reported_by, status, admission_slip_id,
    is_escalated, incident_notes, professor_id
  )
  select
    p_student_id, offense_id, p_reported_by, 'Pending', p_slip_id,
    p_is_escalated, p_incident_notes, p_professor_id
  from unnest(p_offense_ids) as offense_id;
end;
$$;

revoke all on function public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text, uuid
) from public;
grant execute on function public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text, uuid
) to anon, authenticated;
