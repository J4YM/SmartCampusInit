-- Login lockout, scoped to the sign-in SESSION (the browser/device making the
-- attempts), not to the account: 3 failed password sign-ins in a session
-- within 15 minutes lock that session out of signing in for 15 minutes and
-- queue a security alert email. Someone signing in to the same account from a
-- different session is not affected.
--
-- Prerequisites: add_escalation_reports.sql (email_outbox) and, to actually
-- deliver mail, setup_email_resend_direct.sql.
--
-- Design notes
--  * The app generates a random session id the first time it runs on a
--    device and sends it with every attempt. Clearing site data creates a new
--    session id, so this limits guessing per session, not per account or IP.
--  * The counter lives in public.login_attempts, which no client role can read
--    or write directly (RLS on, no policies, privileges revoked); the app only
--    uses the SECURITY DEFINER functions below.
--  * There is deliberately NO "reset on success" function: an anonymous caller
--    could use it to wipe the counter. Failures age out of the 15-minute
--    window instead.
--  * Alert mail goes to the attempted account's email when the username is a
--    profiles.email, otherwise to login_alert_config.fallback_recipient (the
--    demo accounts have no mailbox) - currently the testing address.
--  * Alert volume is capped (one mail per lockout, plus a global ceiling).
--
-- Run in Supabase SQL Editor. Idempotent.

-- Replaces the earlier per-username version, if it was ever run.
drop function if exists public.login_lock_status(text);
drop function if exists public.record_failed_login(text);
drop table if exists public.login_attempts;

create table public.login_attempts (
  session_id      text primary key,
  failed_count    int  not null default 0,
  last_username   text,
  last_failed_at  timestamptz,
  locked_until    timestamptz
);

alter table public.login_attempts enable row level security;
revoke all on public.login_attempts from public, anon, authenticated;

create table if not exists public.login_alert_config (
  id                 boolean primary key default true check (id),
  fallback_recipient text not null
);
insert into public.login_alert_config (id, fallback_recipient)
values (true, 'rubenbanaga@gmail.com')
on conflict (id) do nothing;

alter table public.login_alert_config enable row level security;
revoke all on public.login_alert_config from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- login_lock_status: is this session locked out right now?
-- ---------------------------------------------------------------------------
create or replace function public.login_lock_status(p_session_id text)
returns table (locked boolean, locked_until timestamptz, attempts int)
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.login_attempts;
begin
  if p_session_id is null or length(p_session_id) not between 16 and 64 then
    return query select false, null::timestamptz, 0;
    return;
  end if;

  select * into r from public.login_attempts where session_id = p_session_id;
  if not found then
    return query select false, null::timestamptz, 0;
  elsif r.locked_until is not null and r.locked_until > now() then
    return query select true, r.locked_until, r.failed_count;
  elsif r.last_failed_at is null
        or r.last_failed_at < now() - interval '15 minutes' then
    return query select false, null::timestamptz, 0;
  else
    return query select false, null::timestamptz, r.failed_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_failed_login: count one failure for this session; lock + alert on
-- the 3rd. p_username is only used to say which account was targeted.
-- ---------------------------------------------------------------------------
create or replace function public.record_failed_login(
  p_session_id text,
  p_username   text
)
returns table (attempts int, remaining int, locked boolean,
               locked_until timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  c_max       constant int := 3;
  v_name      text := lower(left(btrim(coalesce(p_username, '')), 100));
  r           public.login_attempts;
  v_count     int;
  v_recipient text;
  v_recent    int;
begin
  if p_session_id is null or length(p_session_id) not between 16 and 64 then
    return query select 0, c_max, false, null::timestamptz;
    return;
  end if;

  insert into public.login_attempts (session_id) values (p_session_id)
  on conflict (session_id) do nothing;

  select * into r from public.login_attempts
   where session_id = p_session_id for update;

  -- Already locked: report it, do not extend or re-alert.
  if r.locked_until is not null and r.locked_until > now() then
    return query select r.failed_count, 0, true, r.locked_until;
    return;
  end if;

  -- Stale failures (or an expired lock) start a fresh window.
  if r.last_failed_at is null
     or r.last_failed_at < now() - interval '15 minutes'
     or (r.locked_until is not null and r.locked_until <= now()) then
    v_count := 1;
  else
    v_count := r.failed_count + 1;
  end if;

  if v_count >= c_max then
    update public.login_attempts
       set failed_count = v_count,
           last_username = v_name,
           last_failed_at = now(),
           locked_until = now() + interval '15 minutes'
     where session_id = p_session_id;

    -- Security alert, throttled to 5 mails / 10 minutes overall.
    select count(*) into v_recent
      from public.email_outbox
     where subject like 'Security alert:%'
       and created_at > now() - interval '10 minutes';

    if v_recent < 5 then
      select p.email into v_recipient
        from public.profiles p
       where lower(p.email) = v_name
       limit 1;
      if v_recipient is null then
        select fallback_recipient into v_recipient
          from public.login_alert_config where id;
      end if;

      if v_recipient is not null then
        insert into public.email_outbox (related_id, recipient, subject, body)
        values (
          gen_random_uuid(),
          v_recipient,
          'Security alert: sign-in locked after failed attempts',
          'STI College Baliuag - Campus Safety System' || E'\n\n' ||
          'A sign-in session was locked after 3 failed attempts' ||
          case when v_name <> ''
               then ', the last one for the account "' || v_name || '"'
               else '' end ||
          '.' || E'\n\n' ||
          'Time: ' || to_char(now() at time zone 'Asia/Manila',
                              'YYYY-MM-DD HH24:MI:SS') || ' (Philippine time)' ||
          E'\n' ||
          'Locked until: ' || to_char((now() + interval '15 minutes')
                              at time zone 'Asia/Manila', 'HH24:MI:SS') ||
          E'\n\n' ||
          'Only the session that made the attempts is locked; the account ' ||
          'itself and other sessions are not affected. If this was not you, ' ||
          'someone may be trying to guess a password - tell your ' ||
          'administrator.'
        );
      end if;
    end if;

    return query select v_count, 0, true, now() + interval '15 minutes';
    return;
  end if;

  update public.login_attempts
     set failed_count = v_count,
         last_username = v_name,
         last_failed_at = now(),
         locked_until = null
   where session_id = p_session_id;

  return query select v_count, c_max - v_count, false, null::timestamptz;
end;
$$;

revoke all on function public.login_lock_status(text) from public;
revoke all on function public.record_failed_login(text, text) from public;
grant execute on function public.login_lock_status(text) to anon, authenticated;
grant execute on function public.record_failed_login(text, text)
  to anon, authenticated;
