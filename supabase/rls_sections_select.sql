-- Allow the Flutter app (anon key) to read sections when resolving section_id.
-- Without a SELECT policy, PostgREST returns no rows and registration fails even if data exists.
--
-- Run once in Supabase SQL Editor after enabling RLS on sections (if not already).

alter table public.sections enable row level security;

drop policy if exists "sections_anon_select" on public.sections;
create policy "sections_anon_select"
  on public.sections
  for select
  to anon
  using (true);

drop policy if exists "sections_authenticated_select" on public.sections;
create policy "sections_authenticated_select"
  on public.sections
  for select
  to authenticated
  using (true);
