-- Schema additions for the Discipline Officer Dashboard UI
-- (packages/discipline_officer_module), integrated from
-- CipherPunk-7800/Capstone-Project ("Discipline Officer Module/").
--
-- The dashboard's approval queue (`DisciplineCaseModel`) is UI-only today
-- (`pendingQueue` starts as an empty list, no Supabase calls yet) and maps
-- almost entirely onto the existing `student_violations` table — student,
-- offense, reporter, evidence, and status are already modeled. Two fields
-- referenced by the queue/detail cards have no home in `student_violations`
-- yet:
--
--   - `isEscalated` — the "Security Escalation" banner on a case.
--   - `slaRemaining` — the countdown label ("02:20") on a case; stored here
--     as a deadline (`sla_due_at`) and formatted into a countdown client-side
--     rather than persisting a pre-formatted string.
--
-- The Quick Approve / Modify / Deny actions currently all resolve a case
-- identically in the UI (no distinct outcome is written per action), so no
-- new `violation_status` value is added here — `Resolved` already covers
-- "this case is done" once the UI grows real per-action semantics.
--
-- Run in Supabase SQL Editor.

alter table public.student_violations
  add column if not exists is_escalated boolean not null default false,
  add column if not exists sla_due_at timestamptz;

create index if not exists student_violations_sla_due_at_idx
  on public.student_violations (sla_due_at)
  where sla_due_at is not null;
