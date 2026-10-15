-- Fixes "new row violates row-level security policy" when printing an ID.
--
-- The Print ID flow uploads the captured photo to the `student-photos`
-- bucket. add_student_photos_storage.sql only granted `authenticated`, but
-- demo accounts (ittech.demo etc.) have no Supabase Auth session and call
-- Supabase as `anon` — so the upload was rejected. Mirrors the anon policies
-- already given to `student-signatures` in add_id_card_media_storage.sql.
-- Fine for demo/dev; tighten before production.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

drop policy if exists "Anon can read student photos" on storage.objects;
create policy "Anon can read student photos"
on storage.objects for select
to anon
using (bucket_id = 'student-photos');

drop policy if exists "Anon can upload student photos" on storage.objects;
create policy "Anon can upload student photos"
on storage.objects for insert
to anon
with check (bucket_id = 'student-photos');

drop policy if exists "Anon can replace student photos" on storage.objects;
create policy "Anon can replace student photos"
on storage.objects for update
to anon
using (bucket_id = 'student-photos')
with check (bucket_id = 'student-photos');
