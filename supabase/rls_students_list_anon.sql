-- Dashboard can list students when using the Supabase anon key.
-- If RLS is enabled but there is no SELECT policy for `anon`, the list is always empty
-- even though rows exist in Table Editor.
--
-- Run in Supabase SQL Editor. Tighten policies before production (e.g. staff-only via JWT claims).

-- Students: allow listing for anonymous API clients (dashboard)
drop policy if exists "students_anon_select_all" on public.students;
create policy "students_anon_select_all"
  on public.students
  for select
  to anon
  using (true);

drop policy if exists "students_authenticated_select_all" on public.students;
create policy "students_authenticated_select_all"
  on public.students
  for select
  to authenticated
  using (true);

-- Profiles: allow reading rows that belong to a student (for embedded select in Flutter)
drop policy if exists "profiles_anon_select_linked_students" on public.profiles;
create policy "profiles_anon_select_linked_students"
  on public.profiles
  for select
  to anon
  using (exists (select 1 from public.students s where s.id = profiles.id));

drop policy if exists "profiles_authenticated_select_linked_students" on public.profiles;
create policy "profiles_authenticated_select_linked_students"
  on public.profiles
  for select
  to authenticated
  using (exists (select 1 from public.students s where s.id = profiles.id));

-- Parent links: allow read so the nested query in the app does not strip rows
drop policy if exists "parent_student_links_anon_select" on public.parent_student_links;
create policy "parent_student_links_anon_select"
  on public.parent_student_links
  for select
  to anon
  using (true);

drop policy if exists "parent_student_links_authenticated_select" on public.parent_student_links;
create policy "parent_student_links_authenticated_select"
  on public.parent_student_links
  for select
  to authenticated
  using (true);

-- Parent profiles (guardian names in embed): allow read if they appear in a link
drop policy if exists "profiles_anon_select_linked_parents" on public.profiles;
create policy "profiles_anon_select_linked_parents"
  on public.profiles
  for select
  to anon
  using (
    exists (
      select 1
      from public.parent_student_links l
      where l.parent_id = profiles.id
    )
  );

drop policy if exists "profiles_authenticated_select_linked_parents" on public.profiles;
create policy "profiles_authenticated_select_linked_parents"
  on public.profiles
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.parent_student_links l
      where l.parent_id = profiles.id
    )
  );
