-- Lets the Virtual Admission Kiosk (lib/kiosk/capstone_kiosk_scan_host.dart)
-- write real `student_violations` rows when a student self-reports at the
-- kiosk (RFID tap only — no staff member authenticates alongside them).
--
-- Two things are needed for that:
--   1. `student_violations.reported_by` is a required FK to an approved
--      Discipline_Officer/Security/Teacher profile (see the comments in
--      supabase/populating/populate_violations_and_good_moral.sql) — the
--      kiosk has no such staff identity to use, so this seeds one fixed
--      "Kiosk Self-Report" system profile to satisfy it.
--   2. The kiosk runs under the plain anon key (same as the rest of this
--      project's demo-mode accounts — see rls_discipline_demo_anon.sql),
--      so `student_violations` needs an anon INSERT policy; today only
--      anon select/update exist.
--
-- Run in Supabase SQL Editor, after add_discipline_officer_schema.sql,
-- rls_discipline_demo_anon.sql, and add_admin_dashboard_schema.sql (the
-- profile upsert below writes `department`/`is_active`, which that script
-- adds to public.profiles).

-- ---------------------------------------------------------------------------
-- 1. Kiosk system reporter profile. Fixed id (not derived like the
--    populate script's _mock_uuid helper) because lib/kiosk/capstone_kiosk_scan_host.dart
--    references this exact literal — keep the two in sync if it ever changes.
-- ---------------------------------------------------------------------------
do $$
begin
  create extension if not exists pgcrypto;
exception when insufficient_privilege then
  raise notice 'Could not ensure pgcrypto extension (may already be enabled): %', sqlerrm;
end $$;

do $$
declare
  v_kiosk_id uuid := '00000000-0000-4000-8000-000000000001';
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    v_kiosk_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    'kiosk.selfreport@baliuag.sti.edu.ph', crypt('kiosk-system-not-a-real-login', gen_salt('bf')), now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, false, now(), now()
  )
  on conflict (id) do nothing;

  insert into public.profiles (
    id, email, first_name, last_name, role, status, department, is_active, created_at
  )
  values (
    v_kiosk_id, 'kiosk.selfreport@baliuag.sti.edu.ph',
    'Kiosk', 'Self-Report System', 'Security'::app_role, 'approved'::approval_status,
    'Automated Kiosk', true, now()
  )
  on conflict (id) do update set
    role = excluded.role,
    status = excluded.status,
    department = excluded.department,
    is_active = excluded.is_active,
    first_name = excluded.first_name,
    last_name = excluded.last_name;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Anon INSERT on student_violations — mirrors the anon select/update
--    policies already granted in rls_discipline_demo_anon.sql.
-- ---------------------------------------------------------------------------
alter table public.student_violations enable row level security;

drop policy if exists "student_violations_anon_insert_all" on public.student_violations;
create policy "student_violations_anon_insert_all"
  on public.student_violations
  for insert
  to anon, authenticated
  with check (true);
