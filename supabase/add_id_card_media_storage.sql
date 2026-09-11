-- supabase/add_id_card_media_storage.sql
--
-- Two new private storage buckets for the ID card template designer:
--   student-signatures — one captured signature image per student,
--     mirroring add_student_photos_storage.sql's student-photos bucket
--     exactly (same private-bucket-plus-signed-URL pattern).
--   id-card-template-images — static images (e.g. school logos) used by
--     Image-type template elements. Not per-student — shared across
--     templates, so no student_id-shaped path convention.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

insert into storage.buckets (id, name, public)
values ('student-signatures', 'student-signatures', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('id-card-template-images', 'id-card-template-images', false)
on conflict (id) do nothing;

drop policy if exists "Authenticated can read student signatures" on storage.objects;
create policy "Authenticated can read student signatures"
on storage.objects for select
to authenticated
using (bucket_id = 'student-signatures');

drop policy if exists "Authenticated can upload student signatures" on storage.objects;
create policy "Authenticated can upload student signatures"
on storage.objects for insert
to authenticated
with check (bucket_id = 'student-signatures');

drop policy if exists "Authenticated can replace student signatures" on storage.objects;
create policy "Authenticated can replace student signatures"
on storage.objects for update
to authenticated
using (bucket_id = 'student-signatures')
with check (bucket_id = 'student-signatures');

drop policy if exists "Authenticated can read template images" on storage.objects;
create policy "Authenticated can read template images"
on storage.objects for select
to authenticated
using (bucket_id = 'id-card-template-images');

drop policy if exists "Authenticated can upload template images" on storage.objects;
create policy "Authenticated can upload template images"
on storage.objects for insert
to authenticated
with check (bucket_id = 'id-card-template-images');

drop policy if exists "Authenticated can replace template images" on storage.objects;
create policy "Authenticated can replace template images"
on storage.objects for update
to authenticated
using (bucket_id = 'id-card-template-images')
with check (bucket_id = 'id-card-template-images');

-- The static demo accounts (lib/auth/static_demo_accounts.dart) never
-- authenticate via real Supabase Auth, so every storage request from a
-- demo session goes out as Postgres role anon, not authenticated —
-- without these, the ittech.demo account could never capture a
-- signature or upload a template image. Same tradeoff as
-- add_audit_logs_anon_rls.sql. Fine for local development/demo; tighten
-- before production. (The existing student-photos bucket in
-- add_student_photos_storage.sql predates this pattern and doesn't have
-- these — out of scope to fix here, since it's a pre-existing,
-- unrelated bucket.)

drop policy if exists "Anon can read student signatures" on storage.objects;
create policy "Anon can read student signatures"
on storage.objects for select
to anon
using (bucket_id = 'student-signatures');

drop policy if exists "Anon can upload student signatures" on storage.objects;
create policy "Anon can upload student signatures"
on storage.objects for insert
to anon
with check (bucket_id = 'student-signatures');

drop policy if exists "Anon can replace student signatures" on storage.objects;
create policy "Anon can replace student signatures"
on storage.objects for update
to anon
using (bucket_id = 'student-signatures')
with check (bucket_id = 'student-signatures');

drop policy if exists "Anon can read template images" on storage.objects;
create policy "Anon can read template images"
on storage.objects for select
to anon
using (bucket_id = 'id-card-template-images');

drop policy if exists "Anon can upload template images" on storage.objects;
create policy "Anon can upload template images"
on storage.objects for insert
to anon
with check (bucket_id = 'id-card-template-images');

drop policy if exists "Anon can replace template images" on storage.objects;
create policy "Anon can replace template images"
on storage.objects for update
to anon
using (bucket_id = 'id-card-template-images')
with check (bucket_id = 'id-card-template-images');
