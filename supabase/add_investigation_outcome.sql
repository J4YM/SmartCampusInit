-- Proven / Not Proven verdict on an investigation.
--
-- An investigation is one-per-violation and a violation has one student, so the
-- verdict lives on guidance_investigations.outcome.
--
--   * outcome is required when an investigation is completed through
--     complete_investigation. It stays null on Open investigations and on
--     legacy Complete rows that predate this migration and have no sanction
--     (null on a Complete row is allowed and treated as "no verdict").
--   * set_investigation_outcome lets the DO / Admin flip the verdict of a
--     Complete investigation, but only while no sanction exists for the
--     violation (sanctions.violation_id is unique, one sanction per violation).
--   * record_sanction refuses a violation whose investigation is Complete with
--     outcome Not_Proven. Everything else in record_sanction is unchanged from
--     add_do_investigations.sql (the latest definition): a Proven or legacy
--     null verdict, and an investigation still Open (early sanction with an
--     override reason), behave exactly as before.
--
-- Run after add_do_investigations.sql. Idempotent.
--
-- Run order / re-run: run add_do_investigations.sql, then this file.
-- Re-running add_do_investigations.sql, add_guidance_investigations.sql or
-- add_sanctions_schema.sql afterwards reverts the record_sanction Not_Proven
-- guard and the complete_investigation signature; re-run this file after any
-- of them. (add_endorsement_meetings.sql likewise reverts the
-- propose_endorsement_meeting guard from add_parent_availability_scheduling.sql;
-- re-run that file too.) Deploy the migrations BEFORE the app build.

alter table public.guidance_investigations
  add column if not exists outcome text;

do $$
begin
  alter table public.guidance_investigations
    add constraint guidance_investigations_outcome_check
    check (outcome in ('Proven', 'Not_Proven'));
exception when duplicate_object then null;
end $$;

-- Legacy backfill: a completed investigation whose violation already has a
-- sanction was, in effect, proven. Others stay null (allowed on Complete).
update public.guidance_investigations gi
   set outcome = 'Proven'
 where gi.status = 'Complete'
   and gi.outcome is null
   and exists (select 1 from public.sanctions s where s.violation_id = gi.violation_id);

-- ---------------------------------------------------------------------------
-- complete_investigation: now takes the verdict. The old 3-argument version is
-- dropped so a stale caller fails loudly instead of binding the wrong overload.
-- ---------------------------------------------------------------------------

drop function if exists public.complete_investigation(uuid, text, text);

create or replace function public.complete_investigation(
  p_investigation_id uuid,
  p_findings text,
  p_outcome text,
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
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can complete an investigation.'
      using errcode = '42501';
  end if;
  if btrim(coalesce(p_findings, '')) = '' then
    raise exception 'Findings are required.';
  end if;
  if p_outcome is null or p_outcome not in ('Proven', 'Not_Proven') then
    raise exception 'Outcome must be Proven or Not_Proven.';
  end if;

  -- Lock the violation BEFORE the investigation: record_sanction locks them in
  -- that order.
  perform 1 from public.student_violations v
    join public.guidance_investigations gi on gi.violation_id = v.id
   where gi.id = p_investigation_id
   for update of v;

  select * into inv from public.guidance_investigations
   where id = p_investigation_id for update;
  if not found then raise exception 'Investigation not found.'; end if;
  if inv.status <> 'Open' then
    raise exception 'This investigation is already complete.';
  end if;

  update public.guidance_investigations
     set status = 'Complete',
         findings = btrim(p_findings),
         outcome = p_outcome,
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

  perform public.log_audit('Completed investigation: ' || p_outcome, inv.violation_id::text);
end;
$$;

revoke all on function public.complete_investigation(uuid, text, text, text) from public, anon;
grant execute on function public.complete_investigation(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- set_investigation_outcome: change the verdict while no sanction exists.
-- ---------------------------------------------------------------------------

create or replace function public.set_investigation_outcome(
  p_investigation_id uuid,
  p_outcome text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  inv public.guidance_investigations;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can change an investigation outcome.'
      using errcode = '42501';
  end if;
  if p_outcome is null or p_outcome not in ('Proven', 'Not_Proven') then
    raise exception 'Outcome must be Proven or Not_Proven.';
  end if;

  -- Same lock order as record_sanction / complete_investigation: violation
  -- first, so a concurrent sanction and verdict change serialise.
  perform 1 from public.student_violations v
    join public.guidance_investigations gi on gi.violation_id = v.id
   where gi.id = p_investigation_id
   for update of v;

  select * into inv from public.guidance_investigations
   where id = p_investigation_id for update;
  if not found then raise exception 'Investigation not found.'; end if;
  if inv.status <> 'Complete' then
    raise exception 'Complete the investigation before setting its outcome.';
  end if;
  if exists (select 1 from public.sanctions where violation_id = inv.violation_id) then
    raise exception 'A sanction has already been recorded, so the outcome can no longer be changed.';
  end if;

  update public.guidance_investigations
     set outcome = p_outcome
   where id = p_investigation_id;

  perform public.log_audit('Set investigation outcome: ' || p_outcome, inv.violation_id::text);
end;
$$;

revoke all on function public.set_investigation_outcome(uuid, text) from public, anon;
grant execute on function public.set_investigation_outcome(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- record_sanction: identical to add_do_investigations.sql plus the
-- Not Proven guard.
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
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
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

  if exists (
    select 1 from public.guidance_investigations
     where violation_id = p_violation_id
       and status = 'Complete'
       and outcome = 'Not_Proven'
  ) then
    raise exception 'The investigation found this case Not Proven, so it cannot be sanctioned.';
  end if;

  if v.status = 'Under_Investigation' then
    if btrim(coalesce(p_override_reason, '')) = '' then
      raise exception 'This case is still under investigation. Enter a reason to sanction it before findings are filed.';
    end if;
    update public.guidance_investigations
       set status = 'Complete', completed_at = now()
     where violation_id = p_violation_id and status = 'Open';
    -- Close the meetings too, so nobody is still asked to confirm one for a
    -- case that no longer needs it.
    update public.guidance_meetings
       set status = 'Cancelled'
     where investigation_id in (
             select id from public.guidance_investigations
              where violation_id = p_violation_id)
       and status in ('Proposed', 'Confirmed', 'Reschedule_Requested', 'Declined')
       and scheduled_at > now();
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
  uuid, text, uuid, text, text, date, date, boolean, text) from public, anon;
grant execute on function public.record_sanction(
  uuid, text, uuid, text, text, date, date, boolean, text) to authenticated;
