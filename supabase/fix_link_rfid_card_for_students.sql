-- supabase/fix_link_rfid_card_for_students.sql
--
-- Root cause of "Invalid RFID" at the kiosk for a student whose card was
-- just assigned via Admin's RFID Card Mapping page (packages/
-- admin_dashboard's RfidMappingPage / AdminApprovalRepository.linkRfidCard):
-- link_rfid_card() always wrote the card UID to `profiles.rfid_card_id`,
-- regardless of the target's role. But the kiosk identifies a STUDENT by
-- `students.rfid_uid` (StudentsRepository.fetchStudentByRfidUid) —
-- `profiles.rfid_card_id` is read only for STAFF/security identification
-- (StudentsRepository.fetchStaffByRfidCardId explicitly excludes Student/
-- Parent roles). So a card assigned to a Student through this page was
-- written to a column the kiosk's student lookup never reads — it really
-- was "assigned," just to the wrong place, hence "Invalid RFID" every time.
--
-- This mainly affects self-registered (Microsoft-signed-in) students:
-- unlike a student the Registrar/IT Technician creates manually (who gets
-- their card assigned through Student Records' own RFID field, which
-- already correctly targets `students.rfid_uid`), a self-registered
-- student who later just needs a card is exactly the case staff reach for
-- this general-purpose Admin page for.
--
-- Run in Supabase SQL Editor, after add_oauth_role_approval_schema.sql
-- (which this replaces one function from) and
-- add_student_self_registration_schema.sql. Idempotent: safe to re-run.

create or replace function public.link_rfid_card(
  p_profile_id uuid,
  p_rfid_card_id text,
  p_role app_role default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status public.approval_status;
  v_effective_role public.app_role;
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may link RFID cards.' using errcode = '42501';
  end if;

  select status, role into v_status, v_effective_role
    from public.profiles where id = p_profile_id;
  if not found then
    raise exception 'No profile found for %.', p_profile_id;
  end if;

  if v_status = 'pending' then
    if p_role is null then
      raise exception 'A role must be selected to approve this pending profile.';
    end if;
    perform public._assert_staff_assignable_role(p_role);
    update public.profiles
      set role = p_role, status = 'approved'
      where id = p_profile_id;
    v_effective_role := p_role;
  end if;

  if v_effective_role = 'Student'::app_role then
    update public.students set rfid_uid = p_rfid_card_id where id = p_profile_id;
    if not found then
      raise exception
        'No students row found for profile % — this account has not '
        'completed student registration yet.', p_profile_id;
    end if;
  else
    update public.profiles set rfid_card_id = p_rfid_card_id where id = p_profile_id;
  end if;
end;
$$;

revoke all on function public.link_rfid_card(uuid, text, app_role) from public;
grant execute on function public.link_rfid_card(uuid, text, app_role) to authenticated;
