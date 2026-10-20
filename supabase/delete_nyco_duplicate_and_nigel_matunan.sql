-- Deletes two specific students:
--   1. the DUPLICATE "Nyco ... Geronimo" record — the one whose name has TWO
--      dots in it (e.g. "Nyco D.C. Geronimo"); the other Nyco Geronimo is kept;
--   2. "Nigel Paul Matunan" (the record with the conflict).
--
-- Deleting a student is permanent. This removes the student's own rows —
-- profile, login, enrollments, grades, violations, parent links — and any
-- guardian account left with no student. Run in two parts:
--
--   PART 1 (PREVIEW)  — read the result. Every row shown WILL be deleted if
--                       you run Part 2, so the rows must be exactly the ones
--                       you mean.
--   PART 2 (DELETE)   — runs in one transaction and refuses (rolls back,
--                       deletes nothing) unless each of the two names matches
--                       EXACTLY ONE student. Swap the final `commit` for
--                       `rollback` for a dry run.

-- ---------------------------------------------------------------------------
-- PART 1 — PREVIEW. Run this first.
-- ---------------------------------------------------------------------------

-- Every Nyco Geronimo: "will_delete" marks the two-dot duplicate.
select s.student_number,
       p.first_name, p.last_name, p.email,
       s.created_at,
       (length(coalesce(p.first_name, '') || coalesce(p.last_name, ''))
        - length(replace(coalesce(p.first_name, '') || coalesce(p.last_name, ''), '.', '')) = 2)
         as will_delete
  from public.students s
  join public.profiles p on p.id = s.id
 where p.first_name ilike '%nyco%' and p.last_name ilike '%geronimo%'
    or p.first_name ilike '%geronimo%' and p.last_name ilike '%nyco%'
 order by s.created_at;

-- Every Nigel Paul Matunan (all of these will be deleted).
select s.student_number,
       p.first_name, p.last_name, p.email,
       s.created_at, s.rfid_uid
  from public.students s
  join public.profiles p on p.id = s.id
 where p.first_name ilike '%nigel%' and p.last_name ilike '%matunan%'
    or p.first_name ilike '%matunan%' and p.last_name ilike '%nigel%'
 order by s.created_at;

-- What deleting them takes with it (so nothing important is a surprise).
select p.first_name || ' ' || p.last_name as student,
       (select count(*) from public.enrollments e where e.student_id = s.id) as enrollments,
       (select count(*) from public.grades g where g.student_id = s.id) as grades,
       (select count(*) from public.student_violations v where v.student_id = s.id) as violations
  from public.students s
  join public.profiles p on p.id = s.id
 where p.first_name ilike '%nyco%' and p.last_name ilike '%geronimo%'
    or p.first_name ilike '%nigel%' and p.last_name ilike '%matunan%';

-- ---------------------------------------------------------------------------
-- PART 2 — DELETE. Only after the preview looks right.
-- ---------------------------------------------------------------------------
begin;

create temporary table _doomed on commit drop as
select s.id
  from public.students s
  join public.profiles p on p.id = s.id
 where (
         (p.first_name ilike '%nyco%' and p.last_name ilike '%geronimo%')
      or (p.first_name ilike '%geronimo%' and p.last_name ilike '%nyco%')
       )
   and length(coalesce(p.first_name, '') || coalesce(p.last_name, ''))
       - length(replace(coalesce(p.first_name, '') || coalesce(p.last_name, ''), '.', '')) = 2
union
select s.id
  from public.students s
  join public.profiles p on p.id = s.id
 where (p.first_name ilike '%nigel%' and p.last_name ilike '%matunan%')
    or (p.first_name ilike '%matunan%' and p.last_name ilike '%nigel%');

-- Safety guard: exactly one Nyco duplicate and one Nigel Matunan, or stop.
do $$
declare
  v_nyco int;
  v_nigel int;
begin
  select count(*) into v_nyco
    from _doomed d join public.profiles p on p.id = d.id
   where p.first_name ilike '%nyco%' or p.last_name ilike '%nyco%'
      or p.first_name ilike '%geronimo%' or p.last_name ilike '%geronimo%';
  select count(*) into v_nigel
    from _doomed d join public.profiles p on p.id = d.id
   where p.first_name ilike '%matunan%' or p.last_name ilike '%matunan%'
      or p.first_name ilike '%nigel%' or p.last_name ilike '%nigel%';
  if v_nyco <> 1 then
    raise exception 'Expected exactly 1 two-dot Nyco Geronimo, found %. Nothing deleted.', v_nyco;
  end if;
  if v_nigel <> 1 then
    raise exception 'Expected exactly 1 Nigel Paul Matunan, found %. Nothing deleted.', v_nigel;
  end if;
end $$;

-- Guardians who would be left with no student (computed before links go).
create temporary table _orphan_guardians on commit drop as
select p.id
  from public.profiles p
 where p.role = 'Parent'
   and exists (select 1 from public.parent_student_links l
                where l.parent_id = p.id and l.student_id in (select id from _doomed))
   and not exists (select 1 from public.parent_student_links l
                    where l.parent_id = p.id and l.student_id not in (select id from _doomed));

-- enrollments / grades reference students without on delete cascade.
delete from public.enrollments where student_id in (select id from _doomed);
delete from public.grades where student_id in (select id from _doomed);
-- Untracked tables: explicit deletes as a safety net in case they lack cascade.
delete from public.student_violations where student_id in (select id from _doomed);
delete from public.parent_student_links where student_id in (select id from _doomed);

-- Everything else referencing students cascades or sets null.
delete from public.students where id in (select id from _doomed);
delete from public.profiles
 where id in (select id from _doomed) or id in (select id from _orphan_guardians);
delete from auth.users
 where id in (select id from _doomed) or id in (select id from _orphan_guardians);

commit;  -- use `rollback;` instead for a dry run
