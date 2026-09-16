-- supabase/add_program_aliases_schema.sql
--
-- Same problem as room_aliases, for program abbreviations the school's
-- exports use ("BSIT", "BCT") against subjects.program/sections.program's
-- full names ("BS Information Technology").
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.program_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,
  canonical_program text not null,
  created_at timestamptz not null default now()
);

alter table public.program_aliases enable row level security;

drop policy if exists "program_aliases_select" on public.program_aliases;
create policy "program_aliases_select"
on public.program_aliases for select
to authenticated
using (true);

drop policy if exists "program_aliases_write" on public.program_aliases;
create policy "program_aliases_write"
on public.program_aliases for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
