-- Professor confirms or denies a violation report that names them.
--
-- A student's kiosk self-report picks a "Teacher / Adviser"
-- (student_violations.professor_id). That professor can now say whether the
-- report is accurate from the Violation Reports tab:
--   * Confirmed - they agree it happened;
--   * Denied    - they dispute it (with an optional note).
-- The decision never deletes or resolves the case; Student Affairs still
-- owns the outcome. A denial notifies Student Affairs so it gets a second
-- look. Reports the professor filed themselves are implicitly confirmed
-- and cannot be decided here.
--
-- Run in Supabase SQL Editor after add_student_violations_professor_column.sql
-- and add_notifications_schema.sql. Idempotent.

alter table public.student_violations
  add column if not exists professor_decision text,
  add column if not exists professor_decision_note text,
  add column if not exists professor_decided_at timestamptz;

do $$
begin
  alter table public.student_violations
    add constraint student_violations_professor_decision_check
    check (professor_decision in ('Confirmed', 'Denied'));
exception when duplicate_object then null;
end $$;

create or replace function public.professor_decide_violation(
  p_violation_id uuid,
  p_professor_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.student_violations;
begin
  if auth.role() = 'authenticated' and p_professor_id is distinct from auth.uid() then
    raise exception 'You can only decide on your own reports.' using errcode = '42501';
  end if;

  if p_decision not in ('Confirmed', 'Denied') then
    raise exception 'Decision must be Confirmed or Denied.';
  end if;

  select * into v from public.student_violations where id = p_violation_id;
  if not found then
    raise exception 'Report not found.';
  end if;
  if v.professor_id is distinct from p_professor_id then
    raise exception 'This report is not tied to you.';
  end if;
  if v.reported_by = p_professor_id then
    raise exception 'You filed this report yourself.';
  end if;

  update public.student_violations
     set professor_decision = p_decision,
         professor_decision_note = nullif(btrim(coalesce(p_note, '')), ''),
         professor_decided_at = now()
   where id = p_violation_id;

  if p_decision = 'Denied' then
    begin
      insert into public.notifications (target_role, title, message)
      values (
        'Discipline_Officer'::app_role,
        'Professor disputed a violation report',
        public.sms_student_name(v.student_id)
          || '''s report was denied by the professor named on it. Review it under Violations.'
      );
    exception when others then
      raise warning 'professor_decide_violation notify failed: %', sqlerrm;
    end;
  end if;
end;
$$;

revoke all on function public.professor_decide_violation(uuid, uuid, text, text) from public;
grant execute on function public.professor_decide_violation(uuid, uuid, text, text)
  to anon, authenticated;
