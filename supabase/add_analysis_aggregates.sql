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
-- Run in Supabase SQL Editor AFTER add_endorsements.sql and, if you use it,
-- add_staff_policies_for_signed_in_users.sql (its "(staff)" twins would give
-- Guidance the read back). Idempotent. Re-running an older script that
-- recreates a read policy on student_violations restores Guidance's access:
-- run this file again afterwards.
--
-- The existing read policies on student_violations were created outside this
-- repository's scripts, so this file finds them by what they say. It NEVER
-- drops a policy it does not understand: it stops with a message that names
-- the policy so you can edit it by hand.

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
-- Every SELECT / ALL policy on the table is examined:
--   1. it lists Guidance_Counselor among roles   -> Guidance is removed from the
--      list (a shape that cannot be rewritten stops the script);
--   2. it is a "(staff)" twin using is_staff_role() -> Guidance is excluded;
--   3. it is a blanket `using (true)` for authenticated users (the demo
--      policy) -> narrowed to the anon role, which the built-in demo logins use.
-- INSERT / UPDATE / DELETE policies are not touched. Student and parent own-row
-- policies do not mention Guidance and are left as they are.
-- ---------------------------------------------------------------------------

do $$
declare
  p record;
  v_qual text;
begin
  for p in
    select policyname, cmd, roles, qual
      from pg_policies
     where schemaname = 'public'
       and tablename = 'student_violations'
       and cmd in ('SELECT', 'ALL')
  loop
    if p.qual ~* '<>\s*''Guidance_Counselor''' then
      null; -- already excludes Guidance (an earlier run of this file)

    elsif p.qual ilike '%Guidance_Counselor%' then
      v_qual := replace(p.qual, '''Guidance_Counselor''::app_role, ', '');
      v_qual := replace(v_qual, ', ''Guidance_Counselor''::app_role', '');
      if v_qual ilike '%Guidance_Counselor%' then
        raise exception
          'Policy "%" on student_violations admits Guidance in a shape this script cannot rewrite safely: %. Remove Guidance_Counselor from it by hand, then run this file again.',
          p.policyname, p.qual;
      end if;
      execute format('alter policy %I on public.student_violations using (%s)',
                     p.policyname, v_qual);
      raise notice 'Removed Guidance from policy %', p.policyname;

    elsif p.qual ilike '%is_staff_role()%' then
      execute format(
        'alter policy %I on public.student_violations using ((%s) and current_user_role() <> ''Guidance_Counselor''::app_role)',
        p.policyname, p.qual);
      raise notice 'Excluded Guidance from staff policy %', p.policyname;

    elsif btrim(p.qual) in ('true', '(true)')
          and (p.roles::text ~* 'authenticated' or p.roles::text ~* 'public') then
      execute format('alter policy %I on public.student_violations to anon', p.policyname);
      raise notice 'Policy % now applies to the anon (demo) role only', p.policyname;
    end if;
  end loop;
end $$;

-- Signed-in staff other than Guidance keep reading violations.
drop policy if exists "student_violations_staff_select_no_guidance" on public.student_violations;
do $$
begin
  if to_regprocedure('public.is_staff_role()') is not null then
    create policy "student_violations_staff_select_no_guidance"
      on public.student_violations for select to authenticated
      using (public.is_staff_role()
             and current_user_role() <> 'Guidance_Counselor'::app_role);
  else
    create policy "student_violations_staff_select_no_guidance"
      on public.student_violations for select to authenticated
      using (current_user_role() in
        ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Registrar'::app_role,
         'Teacher'::app_role, 'Security'::app_role));
  end if;
end $$;
