-- Two follow-ups to the guidance workflow.
--
--  1. Escalation Approvals can schedule a meeting with the parent. When the
--     Guidance Counselor approves an escalation report they may also pick a
--     date, time and place; the parent gets the invitation (notification + SMS)
--     and confirms or declines in the Parent Portal, exactly like an
--     investigation meeting. Such a meeting hangs off the escalation report
--     instead of an investigation, so guidance_meetings.investigation_id
--     becomes optional.
--
--  2. A recorded sanction is copied into the Guidance Counselor's per-student
--     Intervention Logs (counseling_archive_logs, log_type 'sanction'), so the
--     counselor sees the outcome of every case next to their own entries.
--
-- Run in Supabase SQL Editor after add_escalation_reports.sql,
-- add_guidance_investigations.sql, add_counseling_archive_logs.sql and
-- add_sanctions_schema.sql. Idempotent.

-- ---------------------------------------------------------------------------
-- 1. Meetings that belong to an escalation report
-- ---------------------------------------------------------------------------

alter table public.guidance_meetings
  alter column investigation_id drop not null;

alter table public.guidance_meetings
  add column if not exists escalation_report_id uuid
    references public.escalation_reports(id) on delete cascade;

do $$
begin
  alter table public.guidance_meetings
    add constraint guidance_meetings_has_parent_check
    check (investigation_id is not null or escalation_report_id is not null);
exception when duplicate_object then null;
end $$;

create index if not exists guidance_meetings_escalation_idx
  on public.guidance_meetings (escalation_report_id);

-- The old five-argument version is dropped first: two overloads that differ
-- only by defaulted arguments make every call ambiguous.
drop function if exists public.decide_escalation_report(uuid, boolean, text, text, text);

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
  v_name text;
  v_meeting uuid;
  v_when text;
  v_where text := nullif(btrim(coalesce(p_meeting_location, '')), '');
  v_parent record;
begin
  -- Same pattern as create_auto_professor_profile: a real signed-in user must
  -- be a Guidance Counselor/Admin; the static demo accounts (anon) pass.
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Guidance_Counselor'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Only the Guidance Counselor can decide escalation reports.'
      using errcode = '42501';
  end if;

  select * into r from public.escalation_reports where id = p_id for update;
  if not found then
    raise exception 'Escalation report % not found.', p_id;
  end if;
  if r.status <> 'Pending_GC' then
    raise exception 'This report was already %.', lower(r.status);
  end if;

  if not p_approve then
    update public.escalation_reports
       set status = 'Rejected', decided_at = now(),
           decided_by = auth.uid(), decided_by_name = p_actor_name,
           decision_note = p_note
     where id = p_id;
    insert into public.notifications (target_role, title, message)
    values ('Discipline_Officer'::app_role, 'Escalation report rejected',
            public.sms_student_name(r.student_id) || ': '
            || coalesce(nullif(btrim(p_note), ''), 'no reason given') || '.');
    return null;
  end if;

  if p_meeting_at is not null and p_meeting_at <= now() then
    raise exception 'The meeting must be scheduled in the future.';
  end if;

  v_message := coalesce(nullif(btrim(p_message), ''), r.message);

  insert into public.parent_interventions
    (student_id, title, message, kind, sent_by, action_required, skip_sms)
  values (r.student_id, r.title, v_message, 'conduct',
          'Guidance Office', true, not ('sms' = any (r.channels)))
  returning id into v_intervention;

  if 'email' = any (r.channels) then
    select guardian_email into v_email from public.students where id = r.student_id;
    v_name := public.sms_student_name(r.student_id);
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
  values ('Discipline_Officer'::app_role, 'Escalation report approved',
          'The parent of ' || public.sms_student_name(r.student_id)
          || ' is being notified.');

  -- Optional meeting with the parent, invited in the same step.
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
-- 2. Sanctions appear in the counselor's Intervention Logs
-- ---------------------------------------------------------------------------

do $$
begin
  alter table public.counseling_archive_logs
    drop constraint if exists counseling_archive_logs_type_check;
  alter table public.counseling_archive_logs
    add constraint counseling_archive_logs_type_check
    check (log_type in ('counseling', 'parent_conference', 'intervention',
                        'referral', 'sanction', 'other'));
end $$;

create or replace function public.trg_log_sanction_to_archive()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offense text;
  v_label text;
begin
  select o.description into v_offense
    from public.student_violations sv
    left join public.handbook_offenses o on o.id = sv.offense_id
   where sv.id = new.violation_id;

  v_label := initcap(replace(new.sanction_type, '_', ' '));

  insert into public.counseling_archive_logs (
    student_id, log_type, occurred_on, title, notes, created_by_name
  )
  values (
    new.student_id, 'sanction', new.effective_on,
    'Sanction recorded: ' || v_label,
    concat_ws(E'\n',
      case when v_offense is not null then 'Offense: ' || v_offense end,
      new.description,
      case when new.ends_on is not null then 'Until ' || new.ends_on end,
      case when new.affects_enrollment then 'Affects enrollment standing.' end,
      case when new.override_reason is not null
           then 'Sanctioned before the investigation finished: ' || new.override_reason end),
    'Discipline Office'
  );
  return new;
exception when others then
  -- Never block recording the sanction itself.
  raise warning 'trg_log_sanction_to_archive failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists log_sanction_to_archive on public.sanctions;
create trigger log_sanction_to_archive
  after insert on public.sanctions
  for each row execute function public.trg_log_sanction_to_archive();

-- Sanctions recorded before this migration get their log entry once.
insert into public.counseling_archive_logs (
  student_id, log_type, occurred_on, title, notes, created_by_name
)
select s.student_id, 'sanction', s.effective_on,
       'Sanction recorded: ' || initcap(replace(s.sanction_type, '_', ' ')),
       s.description, 'Discipline Office'
  from public.sanctions s
 where not exists (
   select 1 from public.counseling_archive_logs l
    where l.student_id = s.student_id
      and l.log_type = 'sanction'
      and l.occurred_on = s.effective_on
      and l.title = 'Sanction recorded: ' || initcap(replace(s.sanction_type, '_', ' '))
 );
