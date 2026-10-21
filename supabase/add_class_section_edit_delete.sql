-- Registrar Class Schedule tab: edit and delete an offering.
--
-- class_sections had INSERT policies only, and enrollments / grades reference
-- it WITHOUT on delete cascade, so a plain client-side UPDATE/DELETE either
-- wrote nothing (RLS) or failed on the foreign keys. Both actions are
-- security-definer functions instead, with the same role check the other
-- registrar RPCs use (anon is allowed because every demo account is a purely
-- client-side login with no real Supabase Auth session — see
-- add_schedule_import_commit_support.sql; tighten before production).
--
-- update_class_section: changes the offering's subject / section / teacher /
--   school year / term, and its room, days and time. The Class Schedule table
--   shows an offering's class_section_meetings in preference to the columns
--   on class_sections itself, so when the offering has meetings (it came from
--   a CFL / Room Schedule import) they are replaced by one meeting per
--   selected day with the new room and time. The manual form only ever writes
--   the class_sections columns, so those offerings have no meetings to touch.
--
-- delete_class_section: removes the offering together with its enrollments
--   and grades (no cascade) — meetings and per-class attendance records go
--   with it via their own on delete cascade. Returns how many enrollments
--   were removed.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create or replace function public.update_class_section(
  p_id uuid,
  p_subject_id uuid,
  p_section_id uuid,
  p_professor_id uuid,
  p_school_year text,
  p_term text,
  p_room text,
  p_days text[],
  p_start_time time,
  p_end_time time
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day text;
  v_code text;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to edit a class schedule.';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'End time must be after start time.';
  end if;

  update public.class_sections
     set subject_id    = p_subject_id,
         section_id    = p_section_id,
         professor_id  = p_professor_id,
         school_year   = p_school_year,
         term          = p_term,
         room          = p_room,
         schedule_days = p_days,
         start_time    = p_start_time,
         end_time      = p_end_time
   where id = p_id;
  if not found then
    raise exception 'Class schedule not found (it may have been deleted).';
  end if;

  if exists (select 1 from public.class_section_meetings
              where class_section_id = p_id) then
    delete from public.class_section_meetings where class_section_id = p_id;
    foreach v_day in array p_days loop
      v_code := case lower(left(v_day, 3))
        when 'mon' then 'M'
        when 'tue' then 'T'
        when 'wed' then 'W'
        when 'thu' then 'TH'
        when 'fri' then 'F'
        when 'sat' then 'S'
      end;
      if v_code is not null then
        insert into public.class_section_meetings
          (class_section_id, day, start_time, end_time, room)
        values (p_id, v_code, p_start_time, p_end_time, p_room);
      end if;
    end loop;
  end if;
end;
$$;

revoke all on function public.update_class_section(
  uuid, uuid, uuid, uuid, text, text, text, text[], time, time) from public;
grant execute on function public.update_class_section(
  uuid, uuid, uuid, uuid, text, text, text, text[], time, time)
  to anon, authenticated;

create or replace function public.delete_class_section(p_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enrollments int;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to delete a class schedule.';
  end if;

  delete from public.grades where class_section_id = p_id;
  delete from public.enrollments where class_section_id = p_id;
  get diagnostics v_enrollments = row_count;

  delete from public.class_sections where id = p_id;
  if not found then
    raise exception 'Class schedule not found (it may already be deleted).';
  end if;

  return v_enrollments;
end;
$$;

revoke all on function public.delete_class_section(uuid) from public;
grant execute on function public.delete_class_section(uuid)
  to anon, authenticated;
