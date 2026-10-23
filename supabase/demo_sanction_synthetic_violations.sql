-- DEMO ONLY: sanction every open violation of the synthetic (mock) students so
-- the ML risk analysis finally counts them.
--
-- WHY THIS IS NEEDED
-- The risk analysis never sees a violation until it is SANCTIONED. It reads
-- public.analysis_violation_counts(), which counts only violations that are
--   * status = 'Resolved'   (recording a sanction is what sets this; Pending,
--                            Under_Investigation and Investigation_Complete
--                            cases are ignored),
--   * not archived (archived_at is null).
-- Violations of EVERY term count; the app no longer limits the analysis to the
-- current term, so disciplinary history carries over. A student with only open
-- violations shows 0 violations in Single Student Analysis.
--
-- WHAT IT DOES
-- For every non-archived violation of a mock student (student_number
-- 900001-900250) that has no sanction yet, in status Pending /
-- Under_Investigation / Investigation_Complete / Resolved:
--   1. inserts one public.sanctions row (handbook-based, matched to the offense
--      category: Minor -> warning, Major_A -> community service, Major_B/C/D ->
--      suspension). Dismissal and non-readmission are deliberately NOT used,
--      so no student's enrollment standing or good-moral status changes.
--   2. sets the violation to 'Resolved' and stamps acknowledged_at.
-- Triggers on both tables are disabled inside the transaction so no SMS,
-- notification or escalation fires for synthetic data.
--
-- It does NOT touch created_at.
--
-- To include real students too, replace the student_number filter (appears
-- twice) with `true`.
--
-- Safe to re-run: violations that already have a sanction are skipped.
-- Run in the Supabase SQL Editor. One transaction: use `rollback;` instead of
-- `commit;` for a dry run.

-- ---------------------------------------------------------------------------
-- STEP 1 — DIAGNOSE (read-only). Run on its own first.
-- ---------------------------------------------------------------------------
-- Violations of mock students by status, and how many the analysis counts now.
-- select v.status::text as status,
--        count(*) as violations,
--        count(*) filter (where v.archived_at is null) as not_archived,
--        count(*) filter (where exists (select 1 from public.sanctions sa where sa.violation_id = v.id)) as already_sanctioned
--   from public.student_violations v
--   join public.students s on s.id = v.student_id
--  where s.student_number between '900001' and '900250'
--  group by 1 order by 1;

-- ---------------------------------------------------------------------------
-- STEP 2 — SANCTION
-- ---------------------------------------------------------------------------
begin;

alter table public.student_violations disable trigger user;
alter table public.sanctions disable trigger user;

create temporary table _to_sanction on commit drop as
select v.id as violation_id,
       v.student_id,
       v.offense_id,
       v.created_at,
       case o.category::text
         when 'Minor'   then 'warning'
         when 'Major_A' then 'community_service'
         else 'suspension'
       end as sanction_type,
       case o.category::text
         when 'Minor'   then 'Written warning on file.'
         when 'Major_A' then 'Community service and parent conference.'
         when 'Major_B' then 'Suspension per STI handbook.'
         when 'Major_C' then 'Suspension per STI handbook; Discipline Board review.'
         when 'Major_D' then 'Suspension pending Discipline Board review.'
         else 'Warning issued.'
       end as description
  from public.student_violations v
  join public.students s on s.id = v.student_id
  left join public.handbook_offenses o on o.id = v.offense_id
 where s.student_number between '900001' and '900250'
   and v.archived_at is null
   and v.status::text in ('Pending', 'Under_Investigation', 'Investigation_Complete', 'Resolved')
   and not exists (select 1 from public.sanctions sa where sa.violation_id = v.id);

with ins as (
  insert into public.sanctions (
    violation_id, student_id, decided_by, decided_at, basis, handbook_offense_id,
    sanction_type, description, effective_on, affects_enrollment
  )
  select t.violation_id, t.student_id, null,
         least(now(), t.created_at + interval '2 days'),
         'handbook', t.offense_id,
         t.sanction_type, t.description,
         least(current_date, (t.created_at + interval '2 days')::date),
         false
    from _to_sanction t
  returning violation_id, description
)
update public.student_violations v
   set status = 'Resolved',
       acknowledged_at = coalesce(v.acknowledged_at, now()),
       penalty_imposed = coalesce(nullif(v.penalty_imposed, ''), ins.description)
  from ins
 where v.id = ins.violation_id;

alter table public.student_violations enable trigger user;
alter table public.sanctions enable trigger user;

-- Summary: how many were sanctioned, and how many the analysis can now see.
select (select count(*) from _to_sanction) as sanctioned_this_run,
       count(*) filter (where v.status::text = 'Resolved' and v.archived_at is null) as counted_by_analysis
  from public.student_violations v
  join public.students s on s.id = v.student_id
 where s.student_number between '900001' and '900250';

commit;  -- use `rollback;` instead for a dry run

-- ---------------------------------------------------------------------------
-- UNDO (run separately): removes the sanctions this script created for mock
-- students and puts their violations back to Pending. Violations that were
-- already Resolved before this script ran (e.g. from demo_3_seed_activity.sql)
-- will also go back to Pending; re-run demo_3_seed_activity.sql to restore them.
--
-- update public.student_violations v set status = 'Pending', acknowledged_at = null
--   from public.sanctions sa join public.students s on s.id = sa.student_id
--  where sa.violation_id = v.id and s.student_number between '900001' and '900250';
-- delete from public.sanctions sa using public.students s
--  where s.id = sa.student_id and s.student_number between '900001' and '900250';
-- ---------------------------------------------------------------------------
