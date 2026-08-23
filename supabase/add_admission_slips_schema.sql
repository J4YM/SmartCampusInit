-- Admission slips: groups one or more `student_violations` rows filed in a
-- single kiosk visit (self-report or Security Personnel report) under one
-- shareable identity — the QR code on the printable slip encodes this row's
-- `id`, so a phone scan or the standalone slip-lookup page (lib/main_slip.dart)
-- can resolve back to everything filed in that visit.
--
-- `id` is deliberately NOT `default gen_random_uuid()` — the kiosk generates
-- it client-side before ever writing to the database, so the QR code (built
-- from that same id) is valid the instant the slip preview screen renders,
-- before the student has even tapped Confirm.
--
-- `redeemed_at`/`redeemed_by` are unused for now — reserved for the
-- follow-up "teacher scans to validate attendance" feature (deliberately
-- out of scope for this pass) so that work has a natural home instead of
-- needing its own later migration.
--
-- Run in Supabase SQL Editor, after add_discipline_officer_schema.sql (needs
-- `public.student_violations`) and add_admin_dashboard_schema.sql (needs
-- `public.students`, `public.profiles`).

create table if not exists public.admission_slips (
  id uuid primary key,
  student_id uuid not null references public.students(id) on delete cascade,
  reported_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_by uuid references public.profiles(id) on delete set null
);

create index if not exists admission_slips_student_id_idx
  on public.admission_slips (student_id);

alter table public.student_violations
  add column if not exists admission_slip_id uuid
    references public.admission_slips(id) on delete set null;

create index if not exists student_violations_admission_slip_id_idx
  on public.student_violations (admission_slip_id)
  where admission_slip_id is not null;

alter table public.admission_slips enable row level security;

-- Same broad anon access as `student_violations` itself
-- (rls_discipline_demo_anon.sql) — the kiosk writes this under the plain
-- anon key with no staff JWT, and the standalone slip-lookup page
-- (lib/main_slip.dart) needs to read it without any login. Fine for
-- local development/demo; tighten before production.
drop policy if exists "admission_slips_anon_select_all" on public.admission_slips;
create policy "admission_slips_anon_select_all"
  on public.admission_slips
  for select
  to anon, authenticated
  using (true);

drop policy if exists "admission_slips_anon_insert_all" on public.admission_slips;
create policy "admission_slips_anon_insert_all"
  on public.admission_slips
  for insert
  to anon, authenticated
  with check (true);

-- Reserved for the future "teacher redeems slip" follow-up — not called by
-- anything in this pass, but the policy is added now alongside the table
-- rather than as yet another later migration.
drop policy if exists "admission_slips_anon_update_all" on public.admission_slips;
create policy "admission_slips_anon_update_all"
  on public.admission_slips
  for update
  to anon, authenticated
  using (true)
  with check (true);

-- ---------------------------------------------------------------------------
-- submit_admission_slip — the kiosk's one entry point for confirming a
-- slip (both the student self-report and Security Personnel report paths
-- call this identically). Writes `admission_slips` + every
-- `student_violations` row in a single transaction, so a mid-way failure
-- can never leave an admission_slips row with zero linked violations, or a
-- violation pointing at a slip that doesn't exist.
-- ---------------------------------------------------------------------------

create or replace function public.submit_admission_slip(
  p_slip_id uuid,
  p_student_id uuid,
  p_reported_by uuid,
  p_offense_ids uuid[],
  p_is_escalated boolean default false,
  p_incident_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if array_length(p_offense_ids, 1) is null then
    raise exception 'At least one offense is required.';
  end if;

  insert into public.admission_slips (id, student_id, reported_by)
  values (p_slip_id, p_student_id, p_reported_by);

  insert into public.student_violations (
    student_id, offense_id, reported_by, status, admission_slip_id,
    is_escalated, incident_notes
  )
  select
    p_student_id, offense_id, p_reported_by, 'Pending', p_slip_id,
    p_is_escalated, p_incident_notes
  from unnest(p_offense_ids) as offense_id;
end;
$$;

revoke all on function public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text
) from public;
grant execute on function public.submit_admission_slip(
  uuid, uuid, uuid, uuid[], boolean, text
) to anon, authenticated;
