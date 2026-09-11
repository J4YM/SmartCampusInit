-- supabase/add_rfid_assignment_requests_schema.sql
--
-- One row per student a Registrar flags as missing RFID. Registrar
-- submits via notify_rfid_missing (security definer — Registrar has
-- no direct INSERT access, matching report_technical_issue's
-- established pattern); IT Technician/Admin can see and update the
-- queue directly. Only one *pending* request per student at a time —
-- resubmitting for an already-pending student is a harmless no-op,
-- not a duplicate row.
--
-- Run in Supabase SQL Editor.

create table if not exists public.rfid_assignment_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  requested_by uuid references public.profiles(id),
  requested_at timestamptz not null default now(),
  status text not null default 'Pending' check (status in ('Pending', 'Fulfilled')),
  fulfilled_at timestamptz
);

create unique index if not exists idx_rfid_assignment_requests_pending_student
  on public.rfid_assignment_requests(student_id)
  where status = 'Pending';

create index if not exists idx_rfid_assignment_requests_requested_by
  on public.rfid_assignment_requests(requested_by);

alter table public.rfid_assignment_requests enable row level security;

drop policy if exists "rfid_assignment_requests_select" on public.rfid_assignment_requests;
create policy "rfid_assignment_requests_select"
on public.rfid_assignment_requests for select
to authenticated
using (
  current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role)
  or requested_by = auth.uid()
);

drop policy if exists "rfid_assignment_requests_update" on public.rfid_assignment_requests;
create policy "rfid_assignment_requests_update"
on public.rfid_assignment_requests for update
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

-- No INSERT policy for authenticated — inserts only ever happen via
-- notify_rfid_missing below (security definer, bypasses RLS).

-- p_registrar_id is an explicit parameter, not auth.uid() — the
-- static demo accounts (lib/auth/static_demo_accounts.dart) never
-- hold a real Supabase Auth session, the same reason
-- report_technical_issue takes its actor id explicitly.
create or replace function public.notify_rfid_missing(
  p_student_ids uuid[],
  p_registrar_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_names text;
begin
  insert into public.rfid_assignment_requests (student_id, requested_by)
  select unnest(p_student_ids), p_registrar_id
  on conflict (student_id) where status = 'Pending' do nothing;

  get diagnostics v_count = row_count;

  if v_count > 0 then
    select string_agg(trim(p.first_name || ' ' || p.last_name), ', ')
      into v_names
      from public.students s
      join public.profiles p on p.id = s.id
      where s.id = any(p_student_ids);

    insert into public.notifications (target_role, title, message)
    values (
      'IT_Technician'::app_role,
      'Students need RFID cards assigned',
      coalesce(v_names, 'Selected students') || ' need an RFID card assigned.'
    );
  end if;

  return v_count;
end;
$$;

revoke all on function public.notify_rfid_missing(uuid[], uuid) from public;
grant execute on function public.notify_rfid_missing(uuid[], uuid) to anon, authenticated;
