-- Removes the 10 most recently created students (the latest batch upload) and
-- returns the database to the earlier state of 50 students with test data.
-- Professors, and everything attached to the older 50 students, are not touched.
--
-- Also removes any guardian (Parent) account whose ONLY linked students are
-- among those 10. A guardian who is also linked to a kept student stays.
--
-- Safety guard: the DELETE block raises an exception, and the transaction
-- rolls back, unless exactly 50 students remain afterwards. If it aborts,
-- check the PREVIEW output (the student count may not be 60 to begin with).
--
-- Run the PREVIEW block first and confirm the 10 rows shown are the ones you
-- expect to clear before running the DELETE block.

-- ---------------------------------------------------------------------------
-- PREVIEW — run this first.
-- ---------------------------------------------------------------------------

select count(*) as total_students_now from public.students;

-- The 10 newest students (these get deleted).
select s.student_number, p.first_name, p.last_name, s.course, s.year_level,
       p.email, s.created_at
from public.students s
join public.profiles p on p.id = s.id
order by s.created_at desc
limit 10;

-- The next 5 newest, as a sanity check that the cut falls where you expect
-- (there should be a clear gap in created_at between these and the list above).
select s.student_number, p.first_name, p.last_name, s.created_at
from public.students s
join public.profiles p on p.id = s.id
order by s.created_at desc
offset 10 limit 5;

-- ---------------------------------------------------------------------------
-- DELETE — only run this after the preview looks right. Children before
-- parents. Runs in one transaction; swap the final `commit` for `rollback`
-- for a dry run.
-- ---------------------------------------------------------------------------
begin;

create temporary table _last10_student_ids on commit drop as
select s.id
from public.students s
order by s.created_at desc
limit 10;

-- Guardians whose only linked students are being removed. Computed BEFORE
-- the links are deleted.
create temporary table _last10_guardian_ids on commit drop as
select p.id
from public.profiles p
where p.role = 'Parent'
  and exists (select 1 from public.parent_student_links l
              where l.parent_id = p.id
                and l.student_id in (select id from _last10_student_ids))
  and not exists (select 1 from public.parent_student_links l
                  where l.parent_id = p.id
                    and l.student_id not in (select id from _last10_student_ids));

-- enrollments/grades have no ON DELETE CASCADE to students.
delete from public.enrollments where student_id in (select id from _last10_student_ids);
delete from public.grades      where student_id in (select id from _last10_student_ids);

-- Untracked tables: explicit deletes as a safety net in case they lack cascade.
delete from public.student_violations   where student_id in (select id from _last10_student_ids);
delete from public.parent_student_links where student_id in (select id from _last10_student_ids);

-- Everything else referencing students cascades or sets null.
delete from public.students where id in (select id from _last10_student_ids);

delete from public.profiles
 where id in (select id from _last10_guardian_ids)
    or id in (select id from _last10_student_ids);
delete from auth.users
 where id in (select id from _last10_guardian_ids)
    or id in (select id from _last10_student_ids);

-- Guard: abort (roll back) unless we land on exactly 50 students.
do $$
declare
  remaining int;
begin
  select count(*) into remaining from public.students;
  if remaining <> 50 then
    raise exception 'Expected 50 students after cleanup, found %. Rolling back.', remaining;
  end if;
end $$;

commit;  -- use `rollback;` instead for a dry run

-- Sections the import auto-created are left in place; empty ones are harmless.
