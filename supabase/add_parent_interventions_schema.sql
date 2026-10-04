-- Intervention messages shown on the Parent Portal's "Interventions" card:
-- notes from a Guidance Counselor / Discipline Officer / Professor to a
-- child's parent (e.g. "please schedule a conference after repeated
-- absences"). One row per message, addressed to a student; every parent
-- linked to that student (parent_student_links) can read it.
--
-- Sending is not built yet (no UI inserts here) — until a sender exists,
-- insert rows from the SQL editor to try the card out.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create table if not exists public.parent_interventions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  title text not null,
  message text not null default '',
  -- 'attendance' | 'academic' | 'conduct' | 'wellbeing' | 'general'
  kind text not null default 'general',
  sent_by text not null default 'School',
  action_required boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists parent_interventions_student_idx
  on public.parent_interventions (student_id, created_at desc);

alter table public.parent_interventions enable row level security;

-- A parent reads (and marks read) only messages about their linked child.
drop policy if exists "parent_interventions_parent_select" on public.parent_interventions;
create policy "parent_interventions_parent_select"
  on public.parent_interventions
  for select
  to authenticated
  using (
    exists (
      select 1 from public.parent_student_links l
      where l.student_id = parent_interventions.student_id
        and l.parent_id = auth.uid()
    )
  );

drop policy if exists "parent_interventions_parent_mark_read" on public.parent_interventions;
create policy "parent_interventions_parent_mark_read"
  on public.parent_interventions
  for update
  to authenticated
  using (
    exists (
      select 1 from public.parent_student_links l
      where l.student_id = parent_interventions.student_id
        and l.parent_id = auth.uid()
    )
  )
  with check (true);

-- Staff who send interventions.
drop policy if exists "parent_interventions_staff_insert" on public.parent_interventions;
create policy "parent_interventions_staff_insert"
  on public.parent_interventions
  for insert
  to authenticated
  with check (
    current_user_role() in
      ('Admin'::app_role, 'Guidance_Counselor'::app_role,
       'Discipline_Officer'::app_role, 'Teacher'::app_role)
  );

-- Demo mode: the static demo accounts run under the plain anon key (same
-- tradeoff as add_notifications_schema.sql) — tighten before production.
drop policy if exists "parent_interventions_anon_all" on public.parent_interventions;
create policy "parent_interventions_anon_all"
  on public.parent_interventions
  for all
  to anon
  using (true)
  with check (true);
