-- Seed sections for RFID dashboard testing.
-- program = exact strings from the Flutter course dropdown (lib/ui/dashboard_page.dart).
-- name = what users type in "Section" (e.g. BSIT-3B); repository matches program + year_level + name.
--
-- Run in Supabase: SQL Editor → paste → Run.
--
-- If registration still says "No section named ...", either rows are missing or RLS blocks
-- SELECT for `anon`. Run `rls_sections_select.sql` in this folder, then retry.

insert into public.sections (name, program, year_level) values
  -- BS Information Technology (BSIT)
  ('BSIT-1A', 'BS Information Technology', 1),
  ('BSIT-1B', 'BS Information Technology', 1),
  ('BSIT-2A', 'BS Information Technology', 2),
  ('BSIT-2B', 'BS Information Technology', 2),
  ('BSIT-3A', 'BS Information Technology', 3),
  ('BSIT-3B', 'BS Information Technology', 3),
  ('BSIT-4A', 'BS Information Technology', 4),
  ('BSIT-4B', 'BS Information Technology', 4),

  -- BS Hospitality Management (BSHM)
  ('BSHM-1A', 'BS Hospitality Management', 1),
  ('BSHM-1B', 'BS Hospitality Management', 1),
  ('BSHM-2A', 'BS Hospitality Management', 2),
  ('BSHM-2B', 'BS Hospitality Management', 2),
  ('BSHM-3A', 'BS Hospitality Management', 3),
  ('BSHM-3B', 'BS Hospitality Management', 3),
  ('BSHM-4A', 'BS Hospitality Management', 4),
  ('BSHM-4B', 'BS Hospitality Management', 4),

  -- BS Business Administration (BSBA)
  ('BSBA-1A', 'BS Business Administration', 1),
  ('BSBA-1B', 'BS Business Administration', 1),
  ('BSBA-2A', 'BS Business Administration', 2),
  ('BSBA-2B', 'BS Business Administration', 2),
  ('BSBA-3A', 'BS Business Administration', 3),
  ('BSBA-3B', 'BS Business Administration', 3),
  ('BSBA-4A', 'BS Business Administration', 4),
  ('BSBA-4B', 'BS Business Administration', 4),

  -- BS Tourism Management (BSTM)
  ('BSTM-1A', 'BS Tourism Management', 1),
  ('BSTM-1B', 'BS Tourism Management', 1),
  ('BSTM-2A', 'BS Tourism Management', 2),
  ('BSTM-2B', 'BS Tourism Management', 2),
  ('BSTM-3A', 'BS Tourism Management', 3),
  ('BSTM-3B', 'BS Tourism Management', 3),
  ('BSTM-4A', 'BS Tourism Management', 4),
  ('BSTM-4B', 'BS Tourism Management', 4)
on conflict (name) do nothing;
