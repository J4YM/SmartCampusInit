-- Adds id_card_templates.background_color — the ID card editor's canvas
-- was always hardcoded to a plain white background with no way to change
-- it. Stored as `bigint`, not `integer`: an opaque ARGB int (e.g. white =
-- 0xFFFFFFFF = 4294967295) exceeds `integer`'s signed 32-bit range
-- (max ~2.1 billion) once the alpha byte is set, same convention as every
-- other ARGB color value in this app (element color/fillColor/strokeColor
-- live inside the front_layout/back_layout jsonb blobs instead, where
-- JSON numbers have no such limit).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.id_card_templates
  add column if not exists background_color bigint not null default 4294967295;
