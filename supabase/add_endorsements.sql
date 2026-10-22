-- Endorsements: the Discipline Officer (DO) asks the Guidance Associate to
-- step in for counseling and/or a parent intervention. It replaces "escalating
-- a violation to Guidance":
--
--   * An endorsement is not tied to a violation (escalation_reports.
--     violation_ids may be empty) and can concern any student.
--   * kind: 'counseling' | 'parent_intervention' | 'both'. A counseling-only
--     endorsement never messages the parent.
--   * Guidance reads an endorsed student's violation history through
--     endorsement_violation_history(): offense, category, date and status only.
--     Never sanctions, override reasons, findings or notes.
--   * Student referrals go to the DO (policies, notification), and endorsing
--     one links it (referral_id) and marks it In_Progress.
--   * Guidance no longer reads sanctions, and the sanction rows the counselor
--     logs received from add_escalation_meeting_and_sanction_log.sql are
--     removed along with their trigger.
--
-- The table keeps its name (escalation_reports) and decide_escalation_report()
-- keeps its name: only what people read changes.
--
-- Run in Supabase SQL Editor after add_escalation_reports.sql,
-- add_escalation_meeting_and_sanction_log.sql and add_student_referrals.sql.
-- Idempotent.

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------

alter table public.escalation_reports
  add column if not exists kind text not null default 'parent_intervention';

do $$
begin
  alter table public.escalation_reports
    add constraint escalation_reports_kind_check
    check (kind in ('counseling', 'parent_intervention', 'both'));
exception when duplicate_object then null;
end $$;

alter table public.escalation_reports
  add column if not exists referral_id uuid
    references public.student_referrals(id) on delete set null;

-- One live endorsement per referral: a declined one frees the referral to be
-- endorsed again.
drop index if exists public.escalation_reports_referral_uidx;
create unique index escalation_reports_referral_uidx
  on public.escalation_reports (referral_id)
  where referral_id is not null and status <> 'Rejected';

-- A counseling-only endorsement has no parent message and no channels.
alter table public.escalation_reports alter column message set default '';
alter table public.escalation_reports
  drop constraint if exists escalation_reports_channels_check;
alter table public.escalation_reports
  add constraint escalation_reports_channels_check
  check (channels <@ array['sms', 'email']
         and (kind = 'counseling' or cardinality(channels) > 0));

-- ---------------------------------------------------------------------------
-- 2. Notifications read "endorsement"
-- ---------------------------------------------------------------------------

create or replace function public.trg_notify_escalation_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'Pending_GC' then
    insert into public.notifications (target_role, title, message)
    values (
      'Guidance_Counselor'::app_role,
      'Endorsement awaiting approval',
      public.sms_student_name(new.student_id)
        || case when new.source = 'auto'
             then ' was flagged automatically'
             else ' was endorsed by Student Affairs' end
        || '. Review it under Endorsement Approvals.'
    );
  end if;
  return new;
exception when others then
  raise warning 'trg_notify_escalation_report failed: %', sqlerrm;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A referral is endorsed once, never after it is closed
-- ---------------------------------------------------------------------------

create or replace function public.trg_endorsement_referral_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_student uuid;
begin
  if new.referral_id is null then
    return new;
  end if;
  select status, student_id into v_status, v_student
    from public.student_referrals where id = new.referral_id;
  if v_status is null then
    raise exception 'Referral not found.';
  end if;
  if v_student is distinct from new.student_id then
    raise exception 'This referral is about a different student.';
  end if;
  if v_status = 'Closed' then
    raise exception 'This referral is already closed.';
  end if;
  return new;
end;
$$;

drop trigger if exists escalation_reports_referral_guard on public.escalation_reports;
create trigger escalation_reports_referral_guard
  before insert on public.escalation_reports
  for each row execute function public.trg_endorsement_referral_guard();

create or replace function public.trg_endorsement_referral_progress()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.referral_id is not null then
    update public.student_referrals
       set status = 'In_Progress',
           handled_by = coalesce(handled_by, auth.uid()),
           handled_at = coalesce(handled_at, now())
     where id = new.referral_id and status <> 'Closed';
  end if;
  return new;
end;
$$;

drop trigger if exists escalation_reports_referral_progress on public.escalation_reports;
create trigger escalation_reports_referral_progress
  after insert on public.escalation_reports
  for each row execute function public.trg_endorsement_referral_progress();

-- ---------------------------------------------------------------------------
-- 4. Violation history for an endorsed student (column-limited)
-- ---------------------------------------------------------------------------

create or replace function public.endorsement_violation_history(p_student_id uuid)
returns table (
  violation_id uuid,
  offense text,
  category text,
  incident_at timestamptz,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role), false) then
    return;
  end if;
  -- Only a student someone endorsed has a history to look at.
  if not exists (select 1 from public.escalation_reports e where e.student_id = p_student_id) then
    return;
  end if;

  return query
    select v.id,
           coalesce(o.description, 'Unclassified report'),
           o.category::text,
           coalesce(v.incident_at, v.created_at),
           v.status::text
      from public.student_violations v
      left join public.handbook_offenses o on o.id = v.offense_id
     where v.student_id = p_student_id
       and v.archived_at is null
     order by coalesce(v.incident_at, v.created_at) desc;
end;
$$;

revoke all on function public.endorsement_violation_history(uuid) from public, anon;
grant execute on function public.endorsement_violation_history(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Approving: counseling-only skips the parent
-- ---------------------------------------------------------------------------

-- Same arguments as add_escalation_meeting_and_sanction_log.sql; dropped first
-- so the body can change without leaving an overload.
drop function if exists public.decide_escalation_report(
  uuid, boolean, text, text, text, timestamptz, text);

create or replace function public.decide_escalation_report(
  p_id uuid,
  p_approve boolean,
  p_note text default null,
  p_message text default null,
  p_actor_name text default null,
  p_meeting_at timestamptz default null,
  p_meeting_location text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.escalation_reports;
  v_message text;
  v_intervention uuid;
  v_email text;
  v_meeting uuid;
  v_when text;
  v_where text := nullif(btrim(coalesce(p_meeting_location, '')), '');
  v_parent record;
begin
  -- A real signed-in user must be a Guidance Counselor/Admin; the static demo
  -- accounts (anon) pass.
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Guidance_Counselor'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Only the Guidance Associate can decide endorsements.'
      using errcode = '42501';
  end if;

  select * into r from public.escalation_reports where id = p_id for update;
  if not found then
    raise exception 'Endorsement % not found.', p_id;
  end if;
  if r.status <> 'Pending_GC' then
    raise exception 'This endorsement was already %.', lower(r.status);
  end if;

  if not p_approve then
    update public.escalation_reports
       set status = 'Rejected', decided_at = now(),
           decided_by = auth.uid(), decided_by_name = p_actor_name,
           decision_note = p_note
     where id = p_id;
    insert into public.notifications (target_role, title, message)
    values ('Discipline_Officer'::app_role, 'Endorsement declined',
            public.sms_student_name(r.student_id) || ': '
            || coalesce(nullif(btrim(p_note), ''), 'no reason given') || '.');
    return null;
  end if;

  -- Counseling only: nobody is messaged. The counselor holds the session and
  -- logs it by hand.
  if r.kind = 'counseling' then
    update public.escalation_reports
       set status = 'Approved', decided_at = now(),
           decided_by = auth.uid(), decided_by_name = p_actor_name,
           decision_note = p_note
     where id = p_id;
    insert into public.notifications (target_role, title, message)
    values ('Discipline_Officer'::app_role, 'Endorsement approved',
            'Guidance accepted the counseling endorsement of '
            || public.sms_student_name(r.student_id) || '.');
    return null;
  end if;

  if p_meeting_at is not null and p_meeting_at <= now() then
    raise exception 'The meeting must be scheduled in the future.';
  end if;

  v_message := coalesce(nullif(btrim(p_message), ''), nullif(btrim(r.message), ''));
  if v_message is null then
    raise exception 'A message to the parent is required.';
  end if;

  insert into public.parent_interventions
    (student_id, title, message, kind, sent_by, action_required, skip_sms)
  values (r.student_id, r.title, v_message, 'conduct',
          'Guidance Office', true, not ('sms' = any (r.channels)))
  returning id into v_intervention;

  if 'email' = any (r.channels) then
    select guardian_email into v_email from public.students where id = r.student_id;
    insert into public.email_outbox (student_id, related_id, recipient, subject, body, status, error)
    values (
      r.student_id, v_intervention, nullif(btrim(v_email), ''),
      'STI Baliuag Guidance: ' || r.title,
      v_message,
      case when nullif(btrim(v_email), '') is null then 'skipped' else 'pending' end,
      case when nullif(btrim(v_email), '') is null then 'No guardian email on file' end
    )
    on conflict (related_id) do nothing;
  end if;

  update public.escalation_reports
     set status = 'Approved', message = v_message, decided_at = now(),
         decided_by = auth.uid(), decided_by_name = p_actor_name,
         decision_note = p_note, intervention_id = v_intervention
   where id = p_id;

  insert into public.notifications (target_role, title, message)
  values ('Discipline_Officer'::app_role, 'Endorsement approved',
          'The parent of ' || public.sms_student_name(r.student_id)
          || ' is being notified.');

  if p_meeting_at is not null then
    insert into public.guidance_meetings (
      escalation_report_id, student_id, scheduled_at, location, invitee, scheduled_by
    )
    values (p_id, r.student_id, p_meeting_at, v_where, 'parent', auth.uid())
    returning id into v_meeting;

    v_when := to_char(p_meeting_at at time zone 'Asia/Manila', 'Mon DD, YYYY HH12:MI AM');

    for v_parent in
      select parent_id from public.parent_student_links where student_id = r.student_id
    loop
      insert into public.notifications (target_role, user_id, title, message)
      values ('Parent'::app_role, v_parent.parent_id, 'Guidance meeting scheduled',
        public.sms_student_name(r.student_id) || '''s guidance meeting is on ' || v_when
        || coalesce(' at ' || v_where, '')
        || '. Please confirm in the Parent Portal.');
    end loop;

    begin
      perform public.queue_sms(
        'guidance_meeting', r.student_id, v_meeting,
        'STI Baliuag: a guidance meeting for ' || public.sms_student_name(r.student_id)
        || ' is set for ' || v_when || '. Please confirm in the Parent Portal.');
    exception when others then
      raise warning 'decide_escalation_report sms failed: %', sqlerrm;
    end;
  end if;

  return v_intervention;
end;
$$;

revoke all on function public.decide_escalation_report(
  uuid, boolean, text, text, text, timestamptz, text) from public;
grant execute on function public.decide_escalation_report(
  uuid, boolean, text, text, text, timestamptz, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Referrals belong to the Discipline Officer
-- ---------------------------------------------------------------------------

drop policy if exists "student_referrals_staff_select" on public.student_referrals;
create policy "student_referrals_staff_select" on public.student_referrals
  for select to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role));

drop policy if exists "student_referrals_staff_update" on public.student_referrals;
create policy "student_referrals_staff_update" on public.student_referrals
  for update to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role))
  with check (current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role));

create or replace function public.trg_notify_student_referral()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (target_role, title, message)
  values (
    'Discipline_Officer'::app_role,
    case when new.urgency = 'Urgent'
      then 'Urgent student referral'
      else 'New student referral' end,
    public.sms_student_name(new.student_id)
      || case when new.is_self
           then ' asked for help.'
           else ' was referred by a classmate.' end
      || ' Review it under Referrals.'
  );
  return new;
exception when others then
  raise warning 'trg_notify_student_referral failed: %', sqlerrm;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Guidance does not see sanctions, and the counselor logs hold none
-- ---------------------------------------------------------------------------

drop policy if exists "sanctions_staff_select" on public.sanctions;
create policy "sanctions_staff_select"
  on public.sanctions for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Registrar'::app_role));

-- The case log quotes sanction descriptions and override reasons in its
-- details, so Guidance does not read it either.
drop policy if exists "violation_actions_staff_select" on public.violation_actions;
create policy "violation_actions_staff_select"
  on public.violation_actions for select to authenticated
  using (coalesce(current_user_role() in
    ('Admin'::app_role, 'Discipline_Officer'::app_role), false));

drop trigger if exists log_sanction_to_archive on public.sanctions;
drop function if exists public.trg_log_sanction_to_archive();

delete from public.counseling_archive_logs where log_type = 'sanction';

do $$
begin
  alter table public.counseling_archive_logs
    drop constraint if exists counseling_archive_logs_type_check;
  alter table public.counseling_archive_logs
    add constraint counseling_archive_logs_type_check
    check (log_type in ('counseling', 'parent_conference', 'intervention',
                        'referral', 'other'));
end $$;
