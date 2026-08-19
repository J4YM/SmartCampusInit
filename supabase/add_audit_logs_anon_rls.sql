-- ---------------------------------------------------------------------------
-- Audit & Privacy Logs — demo-mode anon access.
--
-- add_admin_dashboard_schema.sql created `audit_logs` with only
-- `to authenticated` select/insert policies. The static demo accounts
-- (lib/auth/static_demo_accounts.dart) never authenticate via Supabase Auth,
-- so every request from AuditLogger (lib/data/audit_logger.dart) and every
-- role's connected page (Discipline Officer, Professor, Admin) goes out
-- under the plain anon key with no JWT — those inserts were being rejected
-- by RLS ("new row violates row-level security policy for table
-- audit_logs"). Same tradeoff as rls_discipline_demo_anon.sql and
-- add_notifications_schema.sql's anon policies: this makes the table fully
-- readable/writable by anyone holding the public anon key. Fine for local
-- development/demo; tighten before production.
-- ---------------------------------------------------------------------------

drop policy if exists "audit_logs_anon_select" on public.audit_logs;
create policy "audit_logs_anon_select"
  on public.audit_logs
  for select
  to anon
  using (true);

drop policy if exists "audit_logs_anon_insert" on public.audit_logs;
create policy "audit_logs_anon_insert"
  on public.audit_logs
  for insert
  to anon
  with check (true);
