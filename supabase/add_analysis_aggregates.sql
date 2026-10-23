-- Student analysis without violation details.
--
-- The ML risk analysis (single and batch student analysis, parent intervention
-- suggestion) only needs HOW MANY violations a student has in each category and
-- WHEN the last one was. Until now Guidance read the violation rows themselves.
-- This gives the analysis screens exactly the aggregate:
--
--   analysis_violation_counts(p_since, p_student_id, p_resolved_only)
--     -> one row per (student, category): violation_count, last_at
--
-- and takes away Guidance's direct read of student_violations (which also
-- carried the sanction text in penalty_imposed). Guidance still sees the
-- violation history of a student the Discipline Officer endorsed, through
-- endorsement_violation_history() (add_endorsements.sql).
--
-- The Discipline Officer and Admin read the same aggregate, so Student Affairs
-- uses the same analysis screens on the same numbers.
--
-- Run in Supabase SQL Editor after add_endorsements.sql. Idempotent.
-- Re-running an older script that recreates a Guidance policy on
-- student_violations restores the direct read: run this file again.

create or replace function public.analysis_violation_counts(
  p_since timestamptz default null,
  p_student_id uuid default null,
  p_resolved_only boolean default true
)
returns table (
  student_id uuid,
  category text,
  violation_count integer,
  last_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role), false) then
    return;
  end if;

  return query
    select v.student_id,
           coalesce(o.category::text, 'Minor'),
           count(*)::integer,
           max(v.created_at)
      from public.student_violations v
      left join public.handbook_offenses o on o.id = v.offense_id
     where v.archived_at is null
       and (not p_resolved_only or v.status::text = 'Resolved')
       and (p_since is null or v.created_at >= p_since)
       and (p_student_id is null or v.student_id = p_student_id)
     group by v.student_id, coalesce(o.category::text, 'Minor');
end;
$$;

revoke all on function public.analysis_violation_counts(timestamptz, uuid, boolean) from public, anon;
grant execute on function public.analysis_violation_counts(timestamptz, uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Guidance no longer reads student_violations directly.
--
-- The authenticated read policies on this table were created outside this
-- repository's scripts, so they are found by what they say: any policy that
-- names Guidance_Counselor has that role removed from its list; a policy that
-- exists only for Guidance is dropped. INSERT / UPDATE policies are left alone.
-- ---------------------------------------------------------------------------

do $$
declare
  p record;
  v_qual text;
begin
  for p in
    select policyname, cmd, qual
      from pg_policies
     where schemaname = 'public'
       and tablename = 'student_violations'
       and cmd in ('SELECT', 'ALL')
       and qual ilike '%Guidance_Counselor%'
  loop
    v_qual := p.qual;
    v_qual := replace(v_qual, '''Guidance_Counselor''::app_role, ', '');
    v_qual := replace(v_qual, ', ''Guidance_Counselor''::app_role', '');
    if v_qual ilike '%Guidance_Counselor%' then
      -- Only Guidance (or a shape that cannot be rewritten safely): drop it.
      execute format('drop policy %I on public.student_violations', p.policyname);
      raise notice 'Dropped policy % (it admitted only Guidance)', p.policyname;
    else
      execute format('alter policy %I on public.student_violations using (%s)',
                     p.policyname, v_qual);
      raise notice 'Removed Guidance from policy %', p.policyname;
    end if;
  end loop;
end $$;
