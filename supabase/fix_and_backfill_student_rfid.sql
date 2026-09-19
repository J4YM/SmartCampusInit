-- supabase/fix_and_backfill_student_rfid.sql
--
-- One-paste combination of fix_link_rfid_card_for_students.sql (the code
-- fix) and backfill_student_rfid_from_profiles.sql (the one-time data
-- repair for anything mis-assigned before that fix existed) — run this
-- single file instead of the two separately. Safe to run in one go: the
-- backfill steps skip any colliding row rather than erroring, so nothing
-- here can abort partway through. Idempotent: safe to re-run entirely.
--
-- Run in Supabase SQL Editor, after add_oauth_role_approval_schema.sql
-- and add_student_self_registration_schema.sql.
--
-- Background: link_rfid_card() (behind Admin's RFID Card Mapping page)
-- always wrote an assigned card's UID to profiles.rfid_card_id, regardless
-- of the target's role. The kiosk identifies a STUDENT by
-- students.rfid_uid (StudentsRepository.fetchStudentByRfidUid) —
-- profiles.rfid_card_id is staff/security-only
-- (StudentsRepository.fetchStaffByRfidCardId explicitly excludes Student/
-- Parent). So a card assigned to a Student through that page went to a
-- column the kiosk's student lookup never reads — it really was
-- "assigned," just to the wrong place, hence "Invalid RFID" every time.
-- Mainly hit self-registered (Microsoft-signed-in) students, since a
-- manually-created student already gets their card through Student
-- Records' own RFID field, which was always correct.

-- ===========================================================================
-- PART 1 — the code fix: link_rfid_card() now routes the write by role.
-- ===========================================================================

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

-- ===========================================================================
-- PART 2 — the data repair: move anything already mis-assigned before the
-- fix above existed from profiles.rfid_card_id to students.rfid_uid.
-- ===========================================================================

-- 2a. Copy any RFID sitting in a Student's profiles.rfid_card_id into
--     students.rfid_uid, wherever a matching students row exists, doesn't
--     already have one, AND no OTHER student already holds that same
--     card (students.rfid_uid has its own unique constraint, separate
--     from profiles.rfid_card_id's — a genuine double-assignment before
--     the fix can collide here; skipped rather than erroring, see the
--     diagnostic at the end of this file).
update public.students s
set rfid_uid = p.rfid_card_id
from public.profiles p
where p.id = s.id
  and p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and s.rfid_uid is null
  and not exists (
    select 1 from public.students s2
    where s2.rfid_uid = p.rfid_card_id and s2.id <> p.id
  );

-- 2b. Clear the now-redundant profiles.rfid_card_id for students — going
--     forward link_rfid_card() never writes there for a Student, so
--     leaving old values behind would just be confusing clutter. Only
--     clears rows where 2a actually copied the value across (rfid_uid
--     now matches) — a collision (see diagnostic below) keeps its
--     profiles.rfid_card_id untouched, since that's still the only
--     record of that assignment until resolved by hand.
update public.profiles p
set rfid_card_id = null
where p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and exists (
    select 1 from public.students s
    where s.id = p.id and s.rfid_uid = p.rfid_card_id
  );

-- ===========================================================================
-- PART 3 — diagnostic: anything Part 2 could NOT auto-resolve. Read this
-- result. Each row is one physical card assigned to two different
-- students before the fix — decide by hand which one actually holds it,
-- then clear the loser's profiles.rfid_card_id yourself (e.g.
-- `update public.profiles set rfid_card_id = null where id = '<loser id>';`).
-- Empty result = nothing left to resolve.
-- ===========================================================================

select
  p.id as profile_id_with_stale_rfid_card_id,
  p.first_name || ' ' || p.last_name as profile_name,
  p.rfid_card_id as colliding_card_uid,
  s2.id as student_id_already_holding_this_card,
  pr2.first_name || ' ' || pr2.last_name as student_already_holding_it_name
from public.profiles p
join public.students s2 on s2.rfid_uid = p.rfid_card_id
join public.profiles pr2 on pr2.id = s2.id
where p.role = 'Student'::app_role
  and p.rfid_card_id is not null
  and s2.id <> p.id;
