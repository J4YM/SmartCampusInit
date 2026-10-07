-- Escalation reports: Student Affairs (Discipline Officer) -> Guidance
-- Counselor approval -> parent notification by SMS and/or email.
--
-- Flow
--   1. The Discipline Officer issues an escalation report for a student
--      (Parental Intervention tab), choosing SMS and/or email. It is saved as
--      `Pending_GC`; a trigger notifies the Guidance Counselor role.
--   2. The Guidance Counselor approves (optionally editing the message) or
--      rejects it via decide_escalation_report().
--   3. Approval inserts the parent_interventions row. The existing SMS
--      trigger texts the guardian (unless the report is email-only), and an
--      email_outbox row is queued for the `send-email` Edge Function when
--      email was chosen.
--   4. The automatic intervention (3 violations in 30 days / any major
--      offense) no longer notifies parents directly: trg_auto_parent_intervention
--      now files a `Pending_GC` report with source 'auto' instead, so no
--      parent is contacted without counselor sign-off.
--
-- Run in Supabase SQL Editor after add_sms_alerts_schema.sql,
-- add_parent_interventions_schema.sql and add_notifications_schema.sql.
-- Idempotent.
--
-- ONE-TIME EMAIL SETUP (secrets, so not in this file):
--   supabase functions deploy send-email --no-verify-jwt
--   supabase secrets set RESEND_API_KEY=... EMAIL_FROM="STI Baliuag <noreply@yourdomain>" \
--                        EMAIL_WEBHOOK_SECRET=<random>
--   update public.email_config
--      set function_url  = 'https://<project-ref>.supabase.co/functions/v1/send-email',
--          shared_secret = '<same EMAIL_WEBHOOK_SECRET>';
-- Until then email rows simply stay `pending`.

-- ---------------------------------------------------------------------------
-- 1. Columns / tables
-- ---------------------------------------------------------------------------
alter table public.students add column if not exists guardian_email text;

alter table public.parent_interventions
  add column if not exists skip_sms boolean not null default false;

create table if not exists public.escalation_reports (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  violation_ids uuid[] not null default '{}',
  title text not null default 'Parent conference requested',
  -- The officer's report to the Guidance Counselor (internal).
  summary text not null default '',
  -- What the parent receives (the counselor may edit it on approval).
  message text not null,
  channels text[] not null default array['sms'],
  source text not null default 'officer',
  status text not null default 'Pending_GC',
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  decided_by uuid references public.profiles(id) on delete set null,
  decided_by_name text,
  decided_at timestamptz,
  decision_note text,
  intervention_id uuid references public.parent_interventions(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint escalation_reports_status_check
    check (status in ('Pending_GC', 'Approved', 'Rejected')),
  constraint escalation_reports_source_check
    check (source in ('officer', 'auto')),
  constraint escalation_reports_channels_check
    check (channels <@ array['sms', 'email'] and cardinality(channels) > 0)
);

create index if not exists escalation_reports_status_idx
  on public.escalation_reports (status, created_at desc);
create index if not exists escalation_reports_student_idx
  on public.escalation_reports (student_id, created_at desc);

create table if not exists public.email_config (
  id boolean primary key default true check (id),
  function_url text,
  shared_secret text
);
insert into public.email_config (id) values (true) on conflict (id) do nothing;

create table if not exists public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete set null,
  related_id uuid not null,
  recipient text,
  subject text not null,
  body text not null,
  -- 'pending' | 'sending' | 'sent' | 'failed' | 'skipped'
  status text not null default 'pending',
  attempts int not null default 0,
  error text,
  created_at timestamptz not null default now(),
  last_attempt_at timestamptz,
  sent_at timestamptz,
  unique (related_id)
);
create index if not exists email_outbox_status_idx
  on public.email_outbox (status, created_at);

-- ---------------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------------
alter table public.escalation_reports enable row level security;
alter table public.email_config enable row level security;
alter table public.email_outbox enable row level security;

drop policy if exists "escalation_reports_staff_select" on public.escalation_reports;
create policy "escalation_reports_staff_select" on public.escalation_reports
  for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Guidance_Counselor'::app_role, 'Discipline_Officer'::app_role));

drop policy if exists "escalation_reports_officer_insert" on public.escalation_reports;
create policy "escalation_reports_officer_insert" on public.escalation_reports
  for insert to authenticated
  with check (
    current_user_role() in ('Admin'::app_role, 'Discipline_Officer'::app_role)
    and status = 'Pending_GC'
  );

-- No update/delete policy: decisions go through decide_escalation_report().

-- Demo mode: static demo accounts run under the anon key (same tradeoff as
-- add_notifications_schema.sql). Tighten before production.
drop policy if exists "escalation_reports_anon_select" on public.escalation_reports;
create policy "escalation_reports_anon_select" on public.escalation_reports
  for select to anon using (true);
drop policy if exists "escalation_reports_anon_insert" on public.escalation_reports;
create policy "escalation_reports_anon_insert" on public.escalation_reports
  for insert to anon with check (status = 'Pending_GC');

drop policy if exists "email_outbox_staff_select" on public.email_outbox;
create policy "email_outbox_staff_select" on public.email_outbox
  for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Guidance_Counselor'::app_role, 'Discipline_Officer'::app_role));

-- ---------------------------------------------------------------------------
-- 3. Notify the Guidance Counselor when a report is filed
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
      'Escalation report awaiting approval',
      public.sms_student_name(new.student_id)
        || case when new.source = 'auto'
             then ' was flagged automatically'
             else ' was escalated by Student Affairs' end
        || '. Review it under Escalation Approvals.'
    );
  end if;
  return new;
exception when others then
  raise warning 'trg_notify_escalation_report failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists escalation_reports_notify on public.escalation_reports;
create trigger escalation_reports_notify
  after insert on public.escalation_reports
  for each row execute function public.trg_notify_escalation_report();

-- ---------------------------------------------------------------------------
-- 4. SMS trigger honours skip_sms (email-only escalations)
-- ---------------------------------------------------------------------------
create or replace function public.trg_queue_intervention_sms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_body text;
begin
  if new.skip_sms then
    return new;
  end if;

  select * into s from public.sms_settings where id;
  if not coalesce(s.intervention_alerts_enabled, true) then
    return new;
  end if;

  v_body := coalesce(nullif(btrim(new.message), ''), new.title);
  perform public.queue_sms(
    'intervention', new.student_id, new.id,
    coalesce(s.school_name, 'STI Baliuag') || ' Guidance: ' || v_body
  );
  return new;
exception when others then
  raise warning 'trg_queue_intervention_sms failed: %', sqlerrm;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. decide_escalation_report — Guidance Counselor approves / rejects
-- ---------------------------------------------------------------------------
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
  v_name text;
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

  return v_intervention;
end;
$$;

revoke all on function public.decide_escalation_report(uuid, boolean, text, text, text) from public;
grant execute on function public.decide_escalation_report(uuid, boolean, text, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Automatic interventions now wait for Guidance Counselor approval
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
  select * into s from public.sms_settings where id;
  if not coalesce(s.auto_intervention_enabled, true) then
    return new;
  end if;
  if new.student_id is null or new.archived_at is not null then
    return new;
  end if;

  select (o.category::text <> 'Minor') into v_is_major
    from public.handbook_offenses o
   where o.id = new.offense_id;

  select count(*) into v_count
    from public.student_violations v
   where v.student_id = new.student_id
     and v.archived_at is null
     and v.created_at >= now() - make_interval(days => s.auto_intervention_window_days);

  if not (
    (s.auto_intervention_on_major and coalesce(v_is_major, false))
    or v_count >= s.auto_intervention_violation_count
  ) then
    return new;
  end if;

  -- At most one automatic report per student per window, counting both
  -- pending and decided ones.
  if exists (
    select 1 from public.escalation_reports e
     where e.student_id = new.student_id
       and e.source = 'auto'
       and e.created_at >= now() - make_interval(days => s.auto_intervention_window_days)
  ) then
    return new;
  end if;

  insert into public.escalation_reports
    (student_id, violation_ids, summary, message, channels, source, created_by_name)
  values (
    new.student_id,
    array[new.id],
    'Automatic flag: ' || case when coalesce(v_is_major, false)
      then 'major conduct violation reported.'
      else v_count || ' conduct violations in the last '
           || s.auto_intervention_window_days || ' days.' end,
    public.build_conduct_intervention_message(
      public.sms_student_name(new.student_id),
      v_count,
      coalesce(v_is_major, false),
      s.auto_intervention_window_days
    ),
    array['sms'],
    'auto',
    'System (auto)'
  );
  return new;
exception when others then
  raise warning 'trg_auto_parent_intervention failed: %', sqlerrm;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Email dispatch (database -> send-email Edge Function), mirrors SMS
-- ---------------------------------------------------------------------------
create or replace function public.ping_email_dispatcher()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c public.email_config;
begin
  select * into c from public.email_config where id;
  if c.function_url is null or c.shared_secret is null then
    raise warning 'email_config is not set up; emails stay pending until it is.';
    return;
  end if;
  perform net.http_post(
    url := c.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-email-secret', c.shared_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
exception when others then
  raise warning 'ping_email_dispatcher failed: %', sqlerrm;
end;
$$;

create or replace function public.trg_ping_email_dispatcher()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from new_rows where status = 'pending') then
    perform public.ping_email_dispatcher();
  end if;
  return null;
end;
$$;

drop trigger if exists email_outbox_ping on public.email_outbox;
create trigger email_outbox_ping
  after insert on public.email_outbox
  referencing new table as new_rows
  for each statement
  execute function public.trg_ping_email_dispatcher();

-- Hands the Edge Function a batch of pending rows (skip locked so overlapping
-- invocations don't double-send; a row stuck 'sending' 10+ min is reclaimable).
create or replace function public.claim_email_batch(p_limit int default 20)
returns setof public.email_outbox
language sql
security definer
set search_path = public
as $$
  update public.email_outbox o
     set status = 'sending', attempts = o.attempts + 1, last_attempt_at = now()
   where o.id in (
     select id from public.email_outbox
      where (status = 'pending' or (status = 'failed' and attempts < 5)
             or (status = 'sending' and last_attempt_at < now() - interval '10 minutes'))
        and recipient is not null
      order by created_at
      limit p_limit
      for update skip locked
   )
  returning o.*;
$$;

revoke all on function public.claim_email_batch(int) from public, anon, authenticated;
grant execute on function public.claim_email_batch(int) to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'email-sweeper';
    perform cron.schedule('email-sweeper', '*/5 * * * *',
                          'select public.ping_email_dispatcher()');
  end if;
end $$;
