-- Gives SIGNED-IN staff the same table access the anonymous demo logins have.
--
-- Background: the built-in demo logins reach the database as `anon`, so many
-- tables were opened with policies written `to anon` only (grades, enrollments,
-- notifications, id cards, rooms, and about 50 more). A real signed-in account
-- is `authenticated`, which those policies do not cover, so its screens would
-- come up empty or refuse to save.
--
-- This script finds every policy that applies to `anon` alone and adds a twin
-- for `authenticated` named "<policy> (staff)". The twin is the original rule
-- AND the caller is a staff role (Admin, Registrar, Discipline_Officer,
-- Guidance_Counselor, Teacher, Security, IT_Technician, Scheduling_Officer).
-- Students and parents are NOT included: they have their own policies.
--
-- It is parity, not a redesign: any staff role gets the access the old anon
-- policy gave. Tighten per role later (for example, only the Registrar may
-- write grades); the "(staff)" suffix makes these easy to find and replace.
--
-- Idempotent. Safe to re-run after adding new `to anon` policies.
-- Run after the table scripts and after add_incident_report_classification.sql.

create or replace function public.is_staff_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(current_user_role()::text in (
    'Admin', 'Registrar', 'Discipline_Officer', 'Guidance_Counselor',
    'Teacher', 'Security', 'IT_Technician', 'Scheduling_Officer'
  ), false);
$$;

revoke all on function public.is_staff_role() from public, anon;
grant execute on function public.is_staff_role() to authenticated;

do $$
declare
  p record;
  v_name text;
  v_using text;
  v_check text;
  v_sql text;
  v_count int := 0;
begin
  for p in
    select schemaname, tablename, policyname, cmd, qual, with_check
      from pg_policies
     where roles = array['anon']::name[]
       and policyname not like '% (staff)'
  loop
    v_name := left(p.policyname, 55) || ' (staff)';
    v_using := format('(%s) and public.is_staff_role()', coalesce(p.qual, 'true'));
    v_check := format('(%s) and public.is_staff_role()', coalesce(p.with_check, p.qual, 'true'));

    execute format('drop policy if exists %I on %I.%I',
                   v_name, p.schemaname, p.tablename);

    v_sql := format('create policy %I on %I.%I for %s to authenticated',
                    v_name, p.schemaname, p.tablename, p.cmd);
    if p.cmd in ('SELECT', 'DELETE') then
      v_sql := v_sql || ' using ' || v_using;
    elsif p.cmd = 'INSERT' then
      v_sql := v_sql || ' with check ' || v_check;
    else  -- UPDATE and ALL
      v_sql := v_sql || ' using ' || v_using || ' with check ' || v_check;
    end if;

    execute v_sql;
    v_count := v_count + 1;
  end loop;
  raise notice 'Added % staff policies for signed-in users.', v_count;
end $$;
