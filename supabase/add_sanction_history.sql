-- Sanction history for students and parents.
--
-- public.sanctions is staff-only (it carries override reasons). Students and
-- parents see a trimmed history through this function instead: type,
-- description, dates and whether it affects enrollment. Never the override
-- reason, who decided it, or the handbook basis.
--
-- Access:
--   * staff (Admin, Discipline Officer, Guidance Counselor, Registrar)
--   * a parent linked to the student via parent_student_links. Credential
--     parents run on the anon role (auth.uid() is null), so they pass
--     p_parent_id, used when nobody is signed in (see
--     add_parent_credential_access.sql). TEST-GRADE security.
--   * the student: signed in as themselves, or the anon student path that
--     my_concern_reports(p_reporter_id) already uses (no p_parent_id).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create or replace function public.my_sanction_history(
  p_student_id uuid,
  p_parent_id uuid default null
)
returns table (
  id uuid,
  sanction_type text,
  description text,
  effective_on date,
  ends_on date,
  affects_enrollment boolean,
  decided_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed boolean := false;
begin
  if v_uid is not null then
    v_allowed := coalesce(current_user_role() in
                   ('Admin'::app_role, 'Discipline_Officer'::app_role,
                    'Guidance_Counselor'::app_role, 'Registrar'::app_role), false)
                 or v_uid = p_student_id
                 or exists (select 1 from public.parent_student_links l
                             where l.student_id = p_student_id
                               and l.parent_id = v_uid);
  elsif p_parent_id is not null then
    -- Credential parent on the anon role.
    v_allowed := exists (select 1 from public.parent_student_links l
                          where l.student_id = p_student_id
                            and l.parent_id = p_parent_id);
  else
    -- Anon student path, same as my_concern_reports.
    v_allowed := true;
  end if;

  if not v_allowed then
    raise exception 'You cannot view this sanction history.' using errcode = '42501';
  end if;

  return query
    select s.id, s.sanction_type, s.description, s.effective_on, s.ends_on,
           s.affects_enrollment, s.decided_at
      from public.sanctions s
     where s.student_id = p_student_id
     order by s.effective_on desc, s.decided_at desc;
end;
$$;

revoke all on function public.my_sanction_history(uuid, uuid) from public;
grant execute on function public.my_sanction_history(uuid, uuid) to anon, authenticated;
