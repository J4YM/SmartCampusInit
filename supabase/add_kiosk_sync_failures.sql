-- supabase/add_kiosk_sync_failures.sql
--
-- Kiosk offline-mode failures, reviewable and clearable from the IT Technician
-- and Admin dashboards.
--
-- Background: the Windows kiosk keeps taps and violation reports in a local
-- outbox while offline and replays them when it reconnects
-- (packages/kiosk_offline). When the server refuses a replayed item (e.g. "You
-- have already tapped in and out for today."), the kiosk parks it as
-- `rejected` and its corner chip shows "N failed" — with no way to review or
-- clear it, and no way for anyone off that PC to see it.
--
-- Now the kiosk REPORTS each rejected item here, and IT Technician / Admin
-- review it in their dashboards and dismiss it. On its next sync the kiosk
-- sees the dismissal, drops its local copy, and the chip clears. The kiosk's
-- own screen deliberately has no clear button.
--
--   * The kiosk (anon key) can INSERT open rows and READ rows (to learn which
--     of its own were dismissed). It cannot update or delete anything.
--   * Dismissing goes only through dismiss_kiosk_sync_failures(): signed-in
--     Admin / IT_Technician accounts, plus the demo accounts. Demo accounts
--     (lib/auth/static_demo_accounts.dart) have no Supabase session, so the
--     database sees them as `anon` — the same role the kiosk uses — and the two
--     cannot be told apart. Same tradeoff as the rest of this project's demo
--     mode; tighten before production by removing anon from the grant below.
--   * Dismissed rows are kept as history (who, when, optional note).
--
-- Run in Supabase SQL Editor, after add_rfid_reader_network_schema.sql.
-- Idempotent: safe to re-run.

create table if not exists public.kiosk_sync_failures (
  id uuid primary key default gen_random_uuid(),
  -- Which kiosk reported it (rfid_readers.usb_serial).
  reader_usb_serial text not null,
  -- Stable per-item key made by the kiosk, so reporting the same item twice is
  -- a no-op and a dismissal can be matched back to the right local row.
  client_key text not null,
  -- 'tap' (a card tap) or 'slip' (a violation / admission-slip report).
  kind text not null check (kind in ('tap', 'slip')),
  rfid_uid text,
  student_id uuid references public.students(id) on delete set null,
  -- Snapshot of the name from the kiosk's cache, so the dashboards need no join
  -- and still show something if the student is later removed.
  student_name text,
  -- When the tap / report actually happened on the kiosk.
  occurred_at timestamptz not null,
  -- The server's refusal message, verbatim.
  reason text not null,
  payload jsonb,
  status text not null default 'open' check (status in ('open', 'dismissed')),
  reported_at timestamptz not null default now(),
  dismissed_at timestamptz,
  dismissed_by text,
  dismiss_note text,
  unique (reader_usb_serial, client_key)
);

create index if not exists kiosk_sync_failures_status_idx
  on public.kiosk_sync_failures (status, reported_at desc);

alter table public.kiosk_sync_failures enable row level security;

-- The kiosk (and demo-mode dashboards) read through the anon key.
drop policy if exists "kiosk_sync_failures_anon_select" on public.kiosk_sync_failures;
create policy "kiosk_sync_failures_anon_select"
  on public.kiosk_sync_failures
  for select
  to anon
  using (true);

-- The kiosk may only report NEW, OPEN rows — it cannot insert a pre-dismissed
-- one, and there is no update/delete policy at all.
drop policy if exists "kiosk_sync_failures_anon_insert" on public.kiosk_sync_failures;
create policy "kiosk_sync_failures_anon_insert"
  on public.kiosk_sync_failures
  for insert
  to anon
  with check (
    status = 'open'
    and dismissed_at is null
    and dismissed_by is null
    and dismiss_note is null
  );

drop policy if exists "kiosk_sync_failures_staff_select" on public.kiosk_sync_failures;
create policy "kiosk_sync_failures_staff_select"
  on public.kiosk_sync_failures
  for select
  to authenticated
  using (
    current_user_role() in ('Admin'::app_role, 'IT_Technician'::app_role)
  );

-- A kiosk running under a signed-in session reports the same way.
drop policy if exists "kiosk_sync_failures_authenticated_insert" on public.kiosk_sync_failures;
create policy "kiosk_sync_failures_authenticated_insert"
  on public.kiosk_sync_failures
  for insert
  to authenticated
  with check (
    status = 'open'
    and dismissed_at is null
    and dismissed_by is null
    and dismiss_note is null
  );

-- ---------------------------------------------------------------------------
-- Dismissing: the only write path for status changes.
-- Returns how many OPEN rows were dismissed (already-dismissed ids are skipped).
-- ---------------------------------------------------------------------------
create or replace function public.dismiss_kiosk_sync_failures(
  p_ids uuid[],
  p_note text default null,
  p_dismissed_by text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_n int;
begin
  -- A real signed-in session must be Admin or IT_Technician. No session
  -- (auth.uid() is null) is anon: the demo accounts — see the file header.
  if auth.uid() is not null then
    if current_user_role() is null
       or current_user_role() not in ('Admin'::app_role, 'IT_Technician'::app_role) then
      raise exception
        'Only Admin or IT Technician accounts can dismiss kiosk sync failures.';
    end if;
    select nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), '')
      into v_name
      from public.profiles p
     where p.id = auth.uid();
  end if;

  update public.kiosk_sync_failures f
     set status = 'dismissed',
         dismissed_at = now(),
         dismissed_by = coalesce(v_name, nullif(btrim(coalesce(p_dismissed_by, '')), ''), 'Unknown'),
         dismiss_note = nullif(btrim(coalesce(p_note, '')), '')
   where f.id = any(p_ids)
     and f.status = 'open';

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.dismiss_kiosk_sync_failures(uuid[], text, text) from public;
grant execute on function public.dismiss_kiosk_sync_failures(uuid[], text, text)
  to anon, authenticated;
