-- Adds id_card_templates.back_background_color — the ID card editor now
-- colours the FRONT and the BACK separately. `background_color` (from
-- add_id_card_templates_background_color.sql) stays the front's colour.
--
-- Nullable on purpose: NULL means "the back uses the front's colour", which
-- is exactly how every template saved before this behaved, so existing cards
-- look the same until someone gives the back its own colour.
--
-- bigint, not integer, for the same reason as background_color: an opaque
-- ARGB int (white = 0xFFFFFFFF = 4294967295) overflows a signed 32-bit int.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run. Until it is run
-- the app keeps working and saves one colour for both sides.

alter table public.id_card_templates
  add column if not exists back_background_color bigint;
