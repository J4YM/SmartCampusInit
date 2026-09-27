-- When the Registrar/Scheduling Officer's Classes+Professor list, CFL, or
-- Room Schedule upload runs before a professor has ever signed in,
-- ScheduleImportRepository.resolveProfessorId auto-creates a stub profile
-- (add_scheduling_officer_role.sql's create_auto_professor_profile) keyed
-- by their school Employee ID. When that same professor later signs in
-- for real via Microsoft 365, handle_new_auth_user
-- (add_oauth_role_approval_schema.sql) creates a SEPARATE, unrelated
-- profiles row (status 'pending') tied to their real login's own id —
-- nothing connects the two automatically (the pending row has no Employee
-- ID; it's derived from an email, not the school's SIS).
--
-- This closes that gap at approval time: the Admin supplies the
-- professor's Employee ID alongside the Teacher role on the Staff
-- Accounts page. If a stub profile with that Employee ID exists, every
-- class_sections/class_assignments row currently pointing at the stub is
-- reassigned to the real, now-approved profile, and the stub (plus its
-- placeholder auth.users row) is removed. No matching stub found (e.g.
-- ordinary non-Teacher approvals, or a Teacher approval with no Employee
-- ID given) is a no-op — this never blocks a normal approval.
--
-- Run in Supabase SQL Editor, after add_scheduling_officer_role.sql and
-- add_registration_sync_log_schema.sql. Idempotent: safe to re-run
-- (re-declares approve_staff_member/batch_approve_staff, adding one
-- parameter to each — every other line is unchanged from that file).

-- `create or replace` can't change a function's parameter list — it would
-- leave the old 3-arg version installed as a separate overload alongside
-- this new 4-arg one, which PostgREST's RPC resolver would then have to
-- disambiguate on every call. Drop the old signature explicitly first.
drop function if exists public.approve_staff_member(uuid, app_role, text);

create or replace function public.approve_staff_member(
  p_user_id uuid,
  p_role app_role,
  p_rfid_card_id text default null,
  p_employee_id text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stub_id uuid;
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may approve staff accounts.' using errcode = '42501';
  end if;

  perform public._assert_staff_assignable_role(p_role);

  update public.profiles
    set role = p_role,
        status = 'approved',
        rfid_card_id = coalesce(p_rfid_card_id, rfid_card_id),
        employee_id = coalesce(p_employee_id, employee_id)
    where id = p_user_id and status = 'pending';

  if not found then
    raise exception 'No pending profile found for %.', p_user_id;
  end if;

  if p_rfid_card_id is not null then
    insert into public.registration_sync_events (event_type, profile_id, detail)
    values ('rfid_assigned', p_user_id, 'RFID card ' || p_rfid_card_id || ' assigned during staff approval');
  end if;

  if p_role = 'Teacher'::app_role and p_employee_id is not null then
    select id into v_stub_id
      from public.profiles
      where employee_id = p_employee_id
        and id <> p_user_id
        and role = 'Teacher'::app_role
      limit 1;

    if v_stub_id is not null then
      update public.class_sections set professor_id = p_user_id where professor_id = v_stub_id;
      update public.class_assignments set professor_id = p_user_id where professor_id = v_stub_id;
      delete from public.profiles where id = v_stub_id;
      delete from auth.users where id = v_stub_id;
    end if;
  end if;
end;
$$;

-- Same reconciliation, per-item, for the batch path.
create or replace function public.batch_approve_staff(p_approvals jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
  v_user_id uuid;
  v_role app_role;
  v_rfid text;
  v_employee_id text;
  v_stub_id uuid;
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may approve staff accounts.' using errcode = '42501';
  end if;

  for v_item in select * from jsonb_array_elements(p_approvals) loop
    v_user_id := (v_item ->> 'user_id')::uuid;
    v_role := (v_item ->> 'role')::app_role;
    v_rfid := v_item ->> 'rfid_card_id';
    v_employee_id := v_item ->> 'employee_id';

    perform public._assert_staff_assignable_role(v_role);

    update public.profiles
      set role = v_role,
          status = 'approved',
          rfid_card_id = coalesce(v_rfid, rfid_card_id),
          employee_id = coalesce(v_employee_id, employee_id)
      where id = v_user_id and status = 'pending';

    if not found then
      raise exception 'No pending profile found for %.', v_user_id;
    end if;

    if v_rfid is not null then
      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('rfid_assigned', v_user_id, 'RFID card ' || v_rfid || ' assigned during staff approval');
    end if;

    if v_role = 'Teacher'::app_role and v_employee_id is not null then
      select id into v_stub_id
        from public.profiles
        where employee_id = v_employee_id
          and id <> v_user_id
          and role = 'Teacher'::app_role
        limit 1;

      if v_stub_id is not null then
        update public.class_sections set professor_id = v_user_id where professor_id = v_stub_id;
        update public.class_assignments set professor_id = v_user_id where professor_id = v_stub_id;
        delete from public.profiles where id = v_stub_id;
        delete from auth.users where id = v_stub_id;
      end if;
    end if;
  end loop;
end;
$$;

revoke all on function public.approve_staff_member(uuid, app_role, text, text) from public;
grant execute on function public.approve_staff_member(uuid, app_role, text, text) to authenticated;

revoke all on function public.batch_approve_staff(jsonb) from public;
grant execute on function public.batch_approve_staff(jsonb) to authenticated;
