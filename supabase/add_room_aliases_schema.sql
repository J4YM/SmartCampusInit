-- supabase/add_room_aliases_schema.sql
--
-- Room names are inconsistent across the school's own export formats
-- (e.g. "COMPUTER LABORATORY 2" / "Comlab2" / "ComLab 1" / "RM 202") —
-- similar-looking strings can be genuinely different rooms ("ComLab 1"
-- vs "ComLab 3"), so this is a maintained lookup, not fuzzy matching.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.room_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,
  canonical_room text not null,
  created_at timestamptz not null default now()
);

alter table public.room_aliases enable row level security;

drop policy if exists "room_aliases_select" on public.room_aliases;
create policy "room_aliases_select"
on public.room_aliases for select
to authenticated
using (true);

drop policy if exists "room_aliases_write" on public.room_aliases;
create policy "room_aliases_write"
on public.room_aliases for all
to authenticated
using (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role))
with check (current_user_role() in ('Registrar'::app_role, 'Admin'::app_role));
