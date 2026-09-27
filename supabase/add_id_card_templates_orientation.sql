-- Adds id_card_templates.orientation — the IT Technician's Design ID
-- Layout editor previously had no portrait/landscape option at all; every
-- template was hardcoded to the CR-80 card's natural landscape shape (see
-- idCardWidthPt/idCardHeightPt in
-- packages/rfid_management_module/lib/id_card_template.dart). Front and
-- back share one value since they're the same physical card.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

alter table public.id_card_templates
  add column if not exists orientation text not null default 'landscape';
