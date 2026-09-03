-- Adds student photo storage — backs the IT Technician's webcam capture
-- for ID card printing (and later, per the app owner, an Attendance tap
-- monitor page that will also display these).
--
-- Private bucket (not public): these are photos of students, some of them
-- minors, so access goes through RLS rather than a guessable public URL.
-- The app reads photos via signed URLs (createSignedUrl), generated
-- on-demand for whoever's allowed to see them.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

insert into storage.buckets (id, name, public)
values ('student-photos', 'student-photos', false)
on conflict (id) do nothing;

-- Any authenticated staff member (not the public `anon` role) can read a
-- student's photo — matches how the rest of this app treats staff-facing
-- student data (no per-role restriction at the table level either).
-- `create policy` has no `if not exists` in Postgres, so this drops first
-- to stay idempotent/safe to re-run.
drop policy if exists "Authenticated can read student photos" on storage.objects;
create policy "Authenticated can read student photos"
on storage.objects for select
to authenticated
using (bucket_id = 'student-photos');

-- Any authenticated staff member can upload/replace a student's photo —
-- captured today only from the IT Technician's Print ID flow, but not
-- worth restricting to a specific role at the storage layer when every
-- caller is already an authenticated staff session.
drop policy if exists "Authenticated can upload student photos" on storage.objects;
create policy "Authenticated can upload student photos"
on storage.objects for insert
to authenticated
with check (bucket_id = 'student-photos');

drop policy if exists "Authenticated can replace student photos" on storage.objects;
create policy "Authenticated can replace student photos"
on storage.objects for update
to authenticated
using (bucket_id = 'student-photos')
with check (bucket_id = 'student-photos');

alter table public.students
  add column if not exists photo_path text;
