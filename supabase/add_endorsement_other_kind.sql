-- Endorsements: an "Other" intervention and an "exclude the parent" option.
--
--   * kind 'other' + other_description: Student Affairs / Guidance may decide
--     on a kind of intervention the three fixed kinds do not cover. Like a
--     counseling-only endorsement it never messages the parent.
--   * exclude_parent: keeps the parent out of the endorsement entirely. The
--     meeting function in add_endorsement_meetings.sql then refuses to invite
--     the parent.
--   * decide_escalation_report loses its two meeting arguments: Guidance no
--     longer schedules on approval, the Discipline Officer arranges the
--     meeting afterwards (add_endorsement_meetings.sql).
--
-- Run in Supabase SQL Editor after add_guidance_referrals.sql. Idempotent.
-- Run order for this batch: add_endorsement_other_kind, reword_meeting_invitations,
-- add_endorsement_meetings, replace_auto_tap_out. Re-running add_endorsements.sql
-- afterwards restores the old decide_escalation_report: run this file again.

-- ---------------------------------------------------------------------------
-- 1. Columns and checks
-- ---------------------------------------------------------------------------

alter table public.escalation_reports
  add column if not exists other_description text;
alter table public.escalation_reports
  add column if not exists exclude_parent boolean not null default false;

alter table public.escalation_reports
  drop constraint if exists escalation_reports_kind_check;
alter table public.escalation_reports
  add constraint escalation_reports_kind_check
  check (kind in ('counseling', 'parent_intervention', 'both', 'other'));

alter table public.escalation_reports
  drop constraint if exists escalation_reports_channels_check;
alter table public.escalation_reports
  add constraint escalation_reports_channels_check
  check (channels <@ array['sms', 'email']
         and (kind in ('counseling', 'other') or cardinality(channels) > 0));

-- ---------------------------------------------------------------------------
-- 2. The referral Guidance gets mentions the description
-- ---------------------------------------------------------------------------

create or replace function public.trg_referral_from_endorsement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.student_referrals (
    student_id, referred_by, is_self, concern, details, source, endorsement_id
  )
  values (
    new.student_id,
    null,
    false,
    'other',
    btrim(coalesce(nullif(btrim(new.title), ''), 'Endorsement')
          || coalesce(': ' || nullif(btrim(new.summary), ''), '')
          || coalesce(' (' || nullif(btrim(new.other_description), '') || ')', '')),
    'endorsement',
    new.id
  )
  on conflict (endorsement_id) where endorsement_id is not null do nothing;

  insert into public.notifications (target_role, title, message)
  values (
    'Guidance_Counselor'::app_role,
    'New referral from Student Affairs',
    public.sms_student_name(new.student_id)
      || ' was endorsed by Student Affairs. Review it under Referrals.'
  );
  return new;
exception when others then
  raise warning 'trg_referral_from_endorsement failed: %', sqlerrm;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Approving: counseling-only and Other skip the parent; no meeting here
-- ---------------------------------------------------------------------------

drop function if exists public.decide_escalation_report(
  uuid, boolean, text, text, text, timestamptz, text);
drop function if exists public.decide_escalation_report(
  uuid, boolean, text, text, text);

create or replace function public.decide_escalation_report(
  p_id uuid,
  p_approve boolean,
  p_note text default null,
  p_message text default null,
  p_actor_name text default null
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

  -- Counseling only, or Other: nobody outside Guidance is messaged. The
  -- Discipline Officer may now arrange a meeting (add_endorsement_meetings.sql).
  if r.kind in ('counseling', 'other') then
    update public.escalation_reports
       set status = 'Approved', decided_at = now(),
           decided_by = auth.uid(), decided_by_name = p_actor_name,
           decision_note = p_note
     where id = p_id;
    insert into public.notifications (target_role, title, message)
    values ('Discipline_Officer'::app_role, 'Endorsement approved',
            'Guidance accepted the endorsement of '
            || public.sms_student_name(r.student_id)
            || '. You can now arrange a meeting.');
    return null;
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
          || ' is being notified. You can now arrange a meeting.');

  return v_intervention;
end;
$$;

revoke all on function public.decide_escalation_report(
  uuid, boolean, text, text, text) from public;
grant execute on function public.decide_escalation_report(
  uuid, boolean, text, text, text) to anon, authenticated;
