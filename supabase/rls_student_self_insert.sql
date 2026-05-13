-- Optional RLS for anonymous student self-registration (Flutter uses signInAnonymously).
-- Enable Anonymous sign-ins in Supabase Dashboard: Authentication → Providers → Anonymous.
-- Anonymous users appear as role "authenticated" with auth.uid() = their user id.
-- Adjust or merge with your existing policies.

-- Profiles: allow users to insert/update their own row
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (id = auth.uid());

-- Students: allow users to insert their own student row (id matches auth user)
drop policy if exists "students_insert_own" on public.students;
create policy "students_insert_own"
  on public.students for insert to authenticated
  with check (id = auth.uid());

-- Students: allow reading own row (needed right after insert before sign-out)
drop policy if exists "students_select_own" on public.students;
create policy "students_select_own"
  on public.students for select to authenticated
  using (id = auth.uid());
