-- The three automatic escalation rules no longer act on their own. They now
-- only FLAG the case with `suggested_escalation` so the Discipline Officer
-- sees a "Suggested escalation" badge and decides:
--
--   * apply_sanction_progression  - 3+ prior Minor violations on record
--   * escalate_sensitive_violation- sensitive keyword in the report notes
--   * trg_auto_parent_intervention- major offense / violation count in window
--                                   (used to file an escalation report and
--                                   message the parents by itself)
--
-- All three tolerate reports that are not classified yet (offense_id null);
-- the offense-based rules run again once classify_violation sets offense_id.
-- Existing escalation_reports / parent_interventions data is untouched.
--
-- Run in Supabase SQL Editor right after add_incident_report_classification.sql.
-- Idempotent.

alter table public.student_violations
  add column if not exists suggested_escalation boolean not null default false;

-- ---------------------------------------------------------------------------
-- 3+ prior Minor violations
-- ---------------------------------------------------------------------------

create or replace function public.apply_sanction_progression()
returns trigger
language plpgsql
as $function$
declare
  v_category text;
  v_minor_count int;
begin
  if new.offense_id is null then
    return new;
  end if;

  select category::text into v_category
    from public.handbook_offenses where id = new.offense_id;
  if v_category is distinct from 'Minor' then
    return new;
  end if;

  select count(*) into v_minor_count
    from public.student_violations sv
    join public.handbook_offenses ho on ho.id = sv.offense_id
   where sv.student_id = new.student_id
     and ho.category = 'Minor'
     and sv.id is distinct from new.id
     -- Sibling rows of the same incident (classify_violation splits one report
     -- into one row per offense) are not "prior" violations of each other.
     and not (sv.incident_at is not distinct from new.incident_at
              and sv.incident_notes is not distinct from new.incident_notes
              and sv.reported_by is not distinct from new.reported_by);

  if v_minor_count >= 3 then
    new.suggested_escalation := true;
  end if;

  return new;
end;
$function$;

drop trigger if exists student_violations_sanction_progression on public.student_violations;
do $$
declare
  v_trigger text;
begin
  -- The original trigger name was created outside this repo; replace
  -- whichever BEFORE trigger calls apply_sanction_progression.
  for v_trigger in
    select t.tgname
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.student_violations'::regclass
       and p.proname = 'apply_sanction_progression'
       and not t.tgisinternal
  loop
    execute format('drop trigger %I on public.student_violations', v_trigger);
  end loop;
end $$;

create trigger student_violations_sanction_progression
  before insert or update of offense_id on public.student_violations
  for each row execute function public.apply_sanction_progression();

-- ---------------------------------------------------------------------------
-- Sensitive keywords: flag, don't escalate or rewrite the sanction text.
-- ---------------------------------------------------------------------------

create or replace function public.escalate_sensitive_violation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_terms text[];
begin
  v_terms := public.find_sensitive_terms(
    concat_ws(E'\n', new.incident_notes, new.penalty_imposed)
  );

  if coalesce(array_length(v_terms, 1), 0) = 0 then
    return new;
  end if;

  new.suggested_escalation := true;
  new.sensitive_terms := v_terms;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Major offense / violation volume: flag instead of filing a report.
-- ---------------------------------------------------------------------------

create or replace function public.trg_auto_parent_intervention()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_is_major boolean;
  v_count int;
begin
  if new.offense_id is null or new.student_id is null or new.archived_at is not null then
    return new;
  end if;

  select * into s from public.sms_settings where id;
  if not coalesce(s.auto_intervention_enabled, true) then
    return new;
  end if;

  select (o.category::text <> 'Minor') into v_is_major
    from public.handbook_offenses o where o.id = new.offense_id;

  select count(*) into v_count
    from public.student_violations v
   where v.student_id = new.student_id
     and v.archived_at is null
     and v.offense_id is not null
     and v.created_at >= now() - make_interval(days => s.auto_intervention_window_days);

  if (s.auto_intervention_on_major and coalesce(v_is_major, false))
     or v_count >= s.auto_intervention_violation_count then
    update public.student_violations
       set suggested_escalation = true
     where id = new.id and not suggested_escalation;
  end if;
  return new;
exception when others then
  raise warning 'trg_auto_parent_intervention failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists student_violations_auto_intervention on public.student_violations;
create trigger student_violations_auto_intervention
  after insert or update of offense_id on public.student_violations
  for each row
  execute function public.trg_auto_parent_intervention();
