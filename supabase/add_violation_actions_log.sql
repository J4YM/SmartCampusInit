-- A record of everything done on a violation case: who did what, and when.
--
-- Written by triggers, so every path is captured the same way: the Discipline
-- Officer's buttons, the counselor's investigation, a parent's reply to a
-- meeting, and the hourly expiry job.
--
--   student_violations  insert           -> Report filed
--                       offense set      -> Classified
--                       status change    -> Escalated to Guidance / Investigation
--                                           complete
--                       expired_at set   -> Expired
--   sanctions           insert           -> Sanction recorded (+ override reason)
--   guidance_meetings   insert / update  -> Meeting scheduled / confirmed /
--                                           declined / completed / missed ...
--
-- Staff (Admin, Discipline Officer, Guidance Counselor) can read the log for a
-- case; students and parents cannot. Nothing writes to it except these
-- triggers.
--
-- Run in Supabase SQL Editor. Best after add_sanctions_schema.sql and
-- add_guidance_investigations.sql; if either has not been run yet, the triggers
-- on their tables are skipped with a NOTICE (the rest still installs), and
-- re-running this script after them adds the skipped ones. Idempotent.

create table if not exists public.violation_actions (
  id uuid primary key default gen_random_uuid(),
  violation_id uuid not null references public.student_violations(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  actor_name text,
  actor_role text,
  action text not null,
  detail text,
  created_at timestamptz not null default now()
);

create index if not exists violation_actions_violation_idx
  on public.violation_actions (violation_id, created_at);

alter table public.violation_actions enable row level security;

drop policy if exists "violation_actions_staff_select" on public.violation_actions;
create policy "violation_actions_staff_select"
  on public.violation_actions for select to authenticated
  using (coalesce(current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role,
     'Guidance_Counselor'::app_role), false));

-- Internal writer. Not callable from the API.
create or replace function public._record_violation_action(
  p_violation_id uuid,
  p_action text,
  p_detail text default null,
  p_actor uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_role text;
begin
  select nullif(btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''),
         role::text
    into v_name, v_role
    from public.profiles where id = p_actor;

  insert into public.violation_actions
    (violation_id, actor_id, actor_name, actor_role, action, detail)
  values (
    p_violation_id,
    case when v_role is null then null else p_actor end,
    coalesce(v_name, 'System'),
    v_role,
    p_action,
    nullif(btrim(coalesce(p_detail, '')), '')
  );
exception when others then
  raise warning '_record_violation_action failed: %', sqlerrm;
end;
$$;

revoke all on function public._record_violation_action(uuid, text, text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- student_violations
-- ---------------------------------------------------------------------------

create or replace function public.trg_log_violation_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public._record_violation_action(
      new.id, 'Report filed',
      case when new.offense_id is null then 'Awaiting classification' else null end,
      coalesce(new.reported_by, auth.uid()));
    return new;
  end if;

  if old.offense_id is null and new.offense_id is not null then
    perform public._record_violation_action(new.id, 'Classified',
      (select description from public.handbook_offenses where id = new.offense_id));
  end if;

  if old.status is distinct from new.status then
    if new.status::text = 'Under_Investigation' then
      perform public._record_violation_action(new.id, 'Escalated to Guidance');
    elsif new.status::text = 'Investigation_Complete' then
      perform public._record_violation_action(new.id,
        'Investigation complete', 'Ready for the Discipline Officer to sanction');
    end if;
  end if;

  if old.expired_at is null and new.expired_at is not null then
    perform public._record_violation_action(new.id, 'Expired',
      '72 weekday hours passed without action', null);
  end if;

  if old.archived_at is null and new.archived_at is not null then
    perform public._record_violation_action(new.id, 'Archived');
  elsif old.archived_at is not null and new.archived_at is null then
    perform public._record_violation_action(new.id, 'Restored from the archive');
  end if;

  return new;
end;
$$;

drop trigger if exists student_violations_log_actions on public.student_violations;
create trigger student_violations_log_actions
  after insert or update on public.student_violations
  for each row execute function public.trg_log_violation_changes();

-- ---------------------------------------------------------------------------
-- sanctions
-- ---------------------------------------------------------------------------

create or replace function public.trg_log_sanction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._record_violation_action(
    new.violation_id,
    'Sanction recorded: ' || replace(initcap(replace(new.sanction_type, '_', ' ')), 'Readmission', 'readmission'),
    concat_ws(E'\n',
      new.description,
      case when new.basis = 'custom' then 'Custom sanction' else 'Handbook-based' end,
      case when new.affects_enrollment then 'Blocks re-enrollment' end,
      case when new.override_reason is not null
           then 'Sanctioned while with Guidance. Reason: ' || new.override_reason end),
    coalesce(new.decided_by, auth.uid()));
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.sanctions') is null then
    raise notice 'public.sanctions does not exist yet: run add_sanctions_schema.sql, then re-run this script to log sanctions.';
  else
    drop trigger if exists sanctions_log_action on public.sanctions;
    create trigger sanctions_log_action
      after insert on public.sanctions
      for each row execute function public.trg_log_sanction();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- guidance meetings and the investigation
-- ---------------------------------------------------------------------------

create or replace function public.trg_log_meeting()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_violation uuid;
  v_when text := to_char(new.scheduled_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');
begin
  select violation_id into v_violation
    from public.guidance_investigations where id = new.investigation_id;
  if v_violation is null then return new; end if;

  if tg_op = 'INSERT' then
    perform public._record_violation_action(v_violation, 'Meeting scheduled',
      v_when || coalesce(' at ' || new.location, '') || ' (invited: ' || new.invitee || ')',
      coalesce(new.scheduled_by, auth.uid()));
  elsif old.status is distinct from new.status then
    perform public._record_violation_action(v_violation,
      'Meeting ' || lower(replace(new.status, '_', ' ')),
      v_when || coalesce(E'\nReply: ' || new.response_note, ''),
      case when new.status in ('Confirmed', 'Declined') then coalesce(new.response_by, auth.uid())
           else auth.uid() end);
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.guidance_meetings') is null
     or to_regclass('public.guidance_investigations') is null then
    raise notice 'The guidance tables do not exist yet: run add_guidance_investigations.sql, then re-run this script to log meetings.';
  else
    drop trigger if exists guidance_meetings_log_action on public.guidance_meetings;
    create trigger guidance_meetings_log_action
      after insert or update on public.guidance_meetings
      for each row execute function public.trg_log_meeting();
  end if;
end $$;

create or replace function public.trg_log_investigation_complete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status is distinct from new.status and new.status = 'Complete' then
    perform public._record_violation_action(new.violation_id,
      'Investigation findings filed', new.findings);
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.guidance_investigations') is null then
    raise notice 'public.guidance_investigations does not exist yet: run add_guidance_investigations.sql, then re-run this script to log findings.';
  else
    drop trigger if exists guidance_investigations_log_action on public.guidance_investigations;
    create trigger guidance_investigations_log_action
      after update on public.guidance_investigations
      for each row execute function public.trg_log_investigation_complete();
  end if;
end $$;
