-- Email setup that needs NO Edge Function and NO CLI: Postgres calls the Resend
-- API directly through pg_net. Use this instead of deploying
-- supabase/functions/send-email (the outbox, triggers and escalation flow from
-- add_escalation_reports.sql stay exactly as they are).
--
-- Before running:
--   1. Run add_escalation_reports.sql (creates email_config / email_outbox).
--   2. Create a Resend API key at resend.com. To email real guardians, verify a
--      domain there; until then Resend only delivers to your own account email,
--      and the sender must be 'onboarding@resend.dev'.
--   3. Fill in the two values in the UPDATE in section 2 below.
--
-- Security note: the API key lives in public.email_config. That table has RLS
-- enabled with no policies, so the app (anon / authenticated) cannot read it;
-- only the dashboard SQL Editor and service_role can. The Edge Function route
-- keeps the key out of the database entirely if that matters more to you.
--
-- Run in Supabase SQL Editor. Idempotent.

-- ---------------------------------------------------------------------------
-- 1. Extensions and columns
-- ---------------------------------------------------------------------------
create extension if not exists pg_net;
create extension if not exists pg_cron;

alter table public.email_config
  add column if not exists resend_api_key text,
  add column if not exists from_address text;

-- Links an outbox row to its in-flight pg_net request so the result can be
-- read back (pg_net is asynchronous).
alter table public.email_outbox
  add column if not exists net_request_id bigint;

-- ---------------------------------------------------------------------------
-- 2. YOUR SETTINGS — edit these two values, then run
-- ---------------------------------------------------------------------------
update public.email_config
   set resend_api_key = 'PASTE_RESEND_API_KEY_HERE',          -- re_xxxxxxxx
       from_address   = 'STI Baliuag <onboarding@resend.dev>' -- or noreply@your-verified-domain
 where id;

-- ---------------------------------------------------------------------------
-- 3. Read back results of earlier requests: 2xx -> sent, anything else -> failed
-- ---------------------------------------------------------------------------
create or replace function public.reconcile_email_results()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.email_outbox o
     set status  = case when r.status_code between 200 and 299
                        then 'sent' else 'failed' end,
         sent_at = case when r.status_code between 200 and 299
                        then now() else o.sent_at end,
         error   = case when r.status_code between 200 and 299 then null
                        else left('Resend ' || coalesce(r.status_code::text, '?')
                                  || ': ' || coalesce(r.content, r.error_msg, ''), 300)
                   end
    from net._http_response r
   where o.status = 'sending'
     and o.net_request_id = r.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Dispatcher: replaces the version that called the Edge Function.
--    (Falls back to the Edge Function if only function_url is configured.)
-- ---------------------------------------------------------------------------
create or replace function public.ping_email_dispatcher()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c public.email_config;
  r public.email_outbox;
  v_req bigint;
begin
  select * into c from public.email_config where id;

  if c.resend_api_key is null or c.resend_api_key like 'PASTE_%'
     or c.from_address is null then
    -- Legacy path: hand off to the send-email Edge Function if it is set up.
    if c.function_url is not null and c.shared_secret is not null then
      perform net.http_post(
        url := c.function_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-email-secret', c.shared_secret),
        body := '{}'::jsonb,
        timeout_milliseconds := 30000);
    else
      raise warning 'email_config is not set up; emails stay pending until it is.';
    end if;
    return;
  end if;

  perform public.reconcile_email_results();

  for r in select * from public.claim_email_batch(20) loop
    begin
      select net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || c.resend_api_key,
          'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'from', c.from_address,
          'to', jsonb_build_array(r.recipient),
          'subject', r.subject,
          'text', r.body),
        timeout_milliseconds := 30000
      ) into v_req;

      update public.email_outbox set net_request_id = v_req where id = r.id;
    exception when others then
      update public.email_outbox
         set status = 'failed', error = left(sqlerrm, 300)
       where id = r.id;
    end;
  end loop;
exception when others then
  raise warning 'ping_email_dispatcher failed: %', sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Schedules: retry sweep every 5 min (already exists), result read-back
--    every minute.
-- ---------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'email-reconcile';
  perform cron.schedule('email-reconcile', '* * * * *',
                        'select public.reconcile_email_results()');

  perform cron.unschedule(jobid) from cron.job where jobname = 'email-sweeper';
  perform cron.schedule('email-sweeper', '*/5 * * * *',
                        'select public.ping_email_dispatcher()');
end $$;

-- ---------------------------------------------------------------------------
-- TEST (uncomment, put YOUR Resend account email, run, wait ~1 minute, then
-- check the status). With the default sender Resend only delivers to the
-- email you signed up with.
-- ---------------------------------------------------------------------------
-- insert into public.email_outbox (related_id, recipient, subject, body)
-- values (gen_random_uuid(), 'you@example.com', 'Test email', 'Hello from Supabase.');
-- select status, error, sent_at from public.email_outbox order by created_at desc limit 5;
