-- Persists results from the standalone dropout-risk ML service (see
-- `Behavioral AI Model/API_CONTRACT.md`) so the Guidance Counselor
-- dashboard's Overview tab (metrics, Risk Distribution, Trained Model
-- Comparison's data, Approval Queue) has something to read without calling
-- the ML service on every page load. Written by
-- `GuidanceCounselorConnectedPage` right after each `/predict` or
-- `/predict/batch` call (write-through) — this schema does not compute
-- anything itself.
--
-- Run in Supabase SQL Editor, after add_admin_dashboard_schema.sql (needs
-- `public.students`).

create table if not exists public.risk_assessments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade
);

-- `create table if not exists` is a no-op if the table already exists in
-- any form (e.g. a prior run of this script that got partway before
-- failing) — these additive alters make re-running safe regardless of
-- which columns are already there, same pattern as
-- add_admin_dashboard_schema.sql.
alter table public.risk_assessments
  add column if not exists dropout_probability numeric not null default 0,
  add column if not exists risk_level text not null default 'LOW',
  add column if not exists confidence numeric,
  add column if not exists risk_reasoning text,
  add column if not exists key_factors jsonb not null default '[]'::jsonb,
  add column if not exists recommendations jsonb not null default '[]'::jsonb,
  add column if not exists early_warning_30d boolean not null default false,
  add column if not exists handbook_review_required boolean not null default false,
  add column if not exists handbook_review_reason text,
  add column if not exists model_version text,
  -- Set true once a Guidance Counselor has acted on this assessment from
  -- the Approval Queue (see GuidanceCounselorDashboard.onApproveSlip).
  add column if not exists reviewed boolean not null default false,
  add column if not exists computed_at timestamptz not null default now();

create index if not exists risk_assessments_student_id_idx
  on public.risk_assessments (student_id);

create index if not exists risk_assessments_reviewed_computed_at_idx
  on public.risk_assessments (reviewed, computed_at);

alter table public.risk_assessments enable row level security;

-- Same demo-mode tradeoff as rls_discipline_demo_anon.sql: the static demo
-- accounts (including Guidance Counselor) never call Supabase Auth, so
-- every request goes out under the plain anon key. Tighten before
-- production (require a real authenticated staff JWT).
drop policy if exists "risk_assessments_anon_select_all" on public.risk_assessments;
create policy "risk_assessments_anon_select_all"
  on public.risk_assessments
  for select
  to anon, authenticated
  using (true);

drop policy if exists "risk_assessments_anon_insert_all" on public.risk_assessments;
create policy "risk_assessments_anon_insert_all"
  on public.risk_assessments
  for insert
  to anon, authenticated
  with check (true);

drop policy if exists "risk_assessments_anon_update_all" on public.risk_assessments;
create policy "risk_assessments_anon_update_all"
  on public.risk_assessments
  for update
  to anon, authenticated
  using (true)
  with check (true);
