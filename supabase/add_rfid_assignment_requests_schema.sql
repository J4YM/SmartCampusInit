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
                    student_id uuid not null references public.students(id) on delete cascade,
                    requested_by uuid references public.profiles(id) on delete set null,
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

                  -- The static demo accounts (lib/auth/static_demo_accounts.dart) never
                  -- authenticate via real Supabase Auth, so every request from a demo
                  -- session (registrar.demo, ittech.demo, ...) goes out as Postgres role
                  -- anon, not authenticated — without these, fetchMyRequests/
                  -- fetchAllRequests/markFulfilled would silently see/affect zero rows
                  -- for every demo account. Same tradeoff as add_audit_logs_anon_rls.sql:
                  -- fully open to anyone holding the public anon key. Fine for local
                  -- development/demo; tighten before production.

                  drop policy if exists "rfid_assignment_requests_anon_select" on public.rfid_assignment_requests;
                  create policy "rfid_assignment_requests_anon_select"
                  on public.rfid_assignment_requests
                  for select
                  to anon
                  using (true);

                  drop policy if exists "rfid_assignment_requests_anon_update" on public.rfid_assignment_requests;
                  create policy "rfid_assignment_requests_anon_update"
                  on public.rfid_assignment_requests
                  for update
                  to anon
                  using (true)
                  with check (true);

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

                  -- ---------------------------------------------------------------------------
                  -- Demo Registrar system profile — same reasoning and pattern as the demo
                  -- Professor/IT Technician system profiles (add_professor_module_schema.sql,
                  -- add_it_technician_schema.sql): the static `registrar.demo` account
                  -- (lib/auth/static_demo_accounts.dart) never calls Supabase Auth, so it has
                  -- no real `profiles.id` to satisfy `rfid_assignment_requests.requested_by`
                  -- (references public.profiles(id)). This fixed id is referenced directly by
                  -- lib/ui/registrar_connected_page.dart (`_demoRegistrarProfileId`) — keep the
                  -- two in sync if it ever changes. Real Microsoft-authenticated Registrar
                  -- accounts use their own actual profile id instead and never touch this row.
                  -- ---------------------------------------------------------------------------
                  do $$
                  declare
                    v_registrar_id uuid := '00000000-0000-4000-8000-000000000003';
                  begin
                    insert into auth.users (
                      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                      raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
                    )
                    values (
                      v_registrar_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
                      'registrar.demo@baliuag.sti.edu.ph', crypt('demo-system-not-a-real-login', gen_salt('bf')), now(),
                      '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, false, now(), now()
                    )
                    on conflict (id) do nothing;

                    insert into public.profiles (
                      id, email, first_name, last_name, role, status, department, is_active, created_at
                    )
                    values (
                      v_registrar_id, 'registrar.demo@baliuag.sti.edu.ph',
                      'Registrar', 'Demo', 'Registrar'::app_role, 'approved'::approval_status,
                      'Registrar', true, now()
                    )
                    on conflict (id) do update set
                      role = excluded.role,
                      status = excluded.status,
                      department = excluded.department,
                      is_active = excluded.is_active;
                  end $$;
