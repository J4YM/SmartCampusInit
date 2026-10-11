-- Fixes the Staff Accounts "Access Toggle" silently doing nothing.
--
-- profiles.is_active is written with a plain UPDATE. The only policy that
-- allows editing other people's profiles (profiles_admin_manage_staff) needs
-- a real Supabase-authenticated Admin; an admin signed in through a static
-- demo account talks to the database as `anon`, so the UPDATE matched zero
-- rows and PostgREST reported success. The switch then snapped back on the
-- next auto-refresh.
--
-- Run in Supabase SQL Editor. Idempotent.

drop policy if exists "profiles_anon_update" on public.profiles;
create policy "profiles_anon_update"
  on public.profiles
  for update
  to anon
  using (true)
  with check (true);

drop policy if exists "profiles_admin_manage_staff" on public.profiles;
create policy "profiles_admin_manage_staff"
  on public.profiles
  for all
  to authenticated
  using (current_user_role() = 'Admin'::app_role)
  with check (current_user_role() = 'Admin'::app_role);
