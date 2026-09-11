-- supabase/add_id_card_templates_schema.sql
--
-- Saved ID card templates for IT Technician's Design ID Layout editor —
-- each row is one named template with independent front/back element
-- layouts (opaque jsonb; only Dart code ever reads/writes individual
-- element fields, so no relational schema for the layout's contents —
-- see packages/rfid_management_module/lib/id_card_template.dart for the
-- element shape).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.id_card_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  front_layout jsonb not null default '[]'::jsonb,
  back_layout jsonb not null default '[]'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.id_card_templates enable row level security;

drop policy if exists "id_card_templates_select" on public.id_card_templates;
create policy "id_card_templates_select"
on public.id_card_templates for select
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

drop policy if exists "id_card_templates_insert" on public.id_card_templates;
create policy "id_card_templates_insert"
on public.id_card_templates for insert
to authenticated
with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

drop policy if exists "id_card_templates_update" on public.id_card_templates;
create policy "id_card_templates_update"
on public.id_card_templates for update
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

drop policy if exists "id_card_templates_delete" on public.id_card_templates;
create policy "id_card_templates_delete"
on public.id_card_templates for delete
to authenticated
using (current_user_role() in ('IT_Technician'::app_role, 'Admin'::app_role));

-- Static demo accounts (lib/auth/static_demo_accounts.dart) never
-- authenticate via real Supabase Auth, so every request from a demo
-- session goes out as Postgres role anon, not authenticated — without
-- these, every method on IdCardTemplatesRepository would silently
-- see/affect zero rows for the ittech.demo account. Same tradeoff as
-- add_audit_logs_anon_rls.sql: fully open to anyone holding the public
-- anon key. Fine for local development/demo; tighten before production.

drop policy if exists "id_card_templates_anon_select" on public.id_card_templates;
create policy "id_card_templates_anon_select"
on public.id_card_templates for select
to anon
using (true);

drop policy if exists "id_card_templates_anon_insert" on public.id_card_templates;
create policy "id_card_templates_anon_insert"
on public.id_card_templates for insert
to anon
with check (true);

drop policy if exists "id_card_templates_anon_update" on public.id_card_templates;
create policy "id_card_templates_anon_update"
on public.id_card_templates for update
to anon
using (true)
with check (true);

drop policy if exists "id_card_templates_anon_delete" on public.id_card_templates;
create policy "id_card_templates_anon_delete"
on public.id_card_templates for delete
to anon
using (true);

-- Keeps updated_at current on every layout/name change — the print
-- flow's template picker defaults to the most-recently-updated template
-- and relies on this being accurate.
create or replace function public.set_id_card_templates_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_id_card_templates_updated_at on public.id_card_templates;
create trigger trg_id_card_templates_updated_at
before update on public.id_card_templates
for each row
execute function public.set_id_card_templates_updated_at();
