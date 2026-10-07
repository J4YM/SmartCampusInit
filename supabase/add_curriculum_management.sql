-- Registrar "Curriculum" upload: lets Registrar / Scheduling Officer / Admin
-- load a curriculum file into subjects + curriculum_entries from the app, and
-- folds earlier auto-generated subjects into the real ones afterwards.
--
-- Run in Supabase SQL Editor after seed_curriculum_subjects.sql (which
-- creates curriculum_entries and subjects.units). Idempotent.
--
-- DEMO: the static demo accounts use the anon key, so the anon policies
-- below let anyone with that key edit the curriculum. Drop the
-- "_anon_" policies before production.

-- subjects: the upload upserts (insert exists in add_scheduling_officer_role.sql)
drop policy if exists "subjects_staff_update" on public.subjects;
create policy "subjects_staff_update" on public.subjects
  for update to authenticated
  using (current_user_role() in
    ('Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role))
  with check (current_user_role() in
    ('Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role));

drop policy if exists "subjects_anon_update" on public.subjects;
create policy "subjects_anon_update" on public.subjects
  for update to anon using (true) with check (true);

-- curriculum_entries (select already open from seed_curriculum_subjects.sql)
drop policy if exists "curriculum_entries_staff_write" on public.curriculum_entries;
create policy "curriculum_entries_staff_write" on public.curriculum_entries
  for all to authenticated
  using (current_user_role() in
    ('Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role))
  with check (current_user_role() in
    ('Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role));

drop policy if exists "curriculum_entries_anon_write" on public.curriculum_entries;
create policy "curriculum_entries_anon_write" on public.curriculum_entries
  for all to anon using (true) with check (true);

-- Folds `AUTO-…` subjects into the real subject with the same title (ignoring
-- case, punctuation and a trailing "(…)"), re-pointing class_sections, and
-- returns how many were merged. Same rule as seed_curriculum_subjects.sql and
-- normalizeSubjectTitle() in the app.
create or replace function public.merge_auto_subjects()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select a.id as auto_id, real.id as real_id
    from public.subjects a
    join public.subjects real
      on real.code not like 'AUTO-%'
     and regexp_replace(lower(regexp_replace(a.title, '\s*\(.*\)\s*$', '')), '[^a-z0-9]', '', 'g')
       = regexp_replace(lower(regexp_replace(real.title, '\s*\(.*\)\s*$', '')), '[^a-z0-9]', '', 'g')
    where a.code like 'AUTO-%'
  loop
    update public.class_sections set subject_id = r.real_id where subject_id = r.auto_id;
    delete from public.subjects
      where id = r.auto_id
        and not exists (select 1 from public.class_sections where subject_id = r.auto_id);
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.merge_auto_subjects() from public;
grant execute on function public.merge_auto_subjects() to anon, authenticated;
