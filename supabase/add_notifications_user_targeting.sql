-- Adds direct-to-user targeting to the centralized `notifications` table
-- (see add_notifications_schema.sql) so the Admin Dashboard's Notifications
-- page can send a custom message to one specific person, not just broadcast
-- to everyone in a role. `target_role` stays required on every row (set to
-- the recipient's own role even for a direct send) so every existing
-- role-based read/update path keeps working unchanged; `user_id` is the
-- new, optional narrowing column.
--
-- Run in Supabase SQL Editor, after add_notifications_schema.sql.

alter table public.notifications
  add column if not exists user_id uuid references public.profiles(id) on delete cascade;

create index if not exists notifications_user_id_idx
  on public.notifications (user_id, created_at desc);

-- A user now sees: anything sent directly to them (user_id match), OR any
-- broadcast to their role (user_id is null + role match), OR everything if
-- they're Admin — replaces the old role-only check, which would have let
-- someone see a colleague's direct message just for sharing their role.
drop policy if exists "notifications_role_select" on public.notifications;
create policy "notifications_role_select"
  on public.notifications
  for select
  to authenticated
  using (
    auth.uid() = user_id
    or (user_id is null and current_user_role() = target_role)
    or current_user_role() = 'Admin'::app_role
  );
