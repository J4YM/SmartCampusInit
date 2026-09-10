-- supabase/add_good_moral_status_and_insert_policies.sql
--
-- Adds the status column add_good_moral_requests_schema.sql deliberately
-- left out ("add one once that workflow is actually built") now that the
-- student/parent request + Discipline Officer fulfill workflow exists, plus
-- INSERT policies so a student/parent can create their own request (the
-- table previously only allowed staff to insert).
--
-- Run in Supabase SQL Editor, after add_good_moral_requests_schema.sql.

alter table public.good_moral_requests
  add column if not exists status text not null default 'Pending';

do $$
begin
  alter table public.good_moral_requests
    add constraint good_moral_requests_status_check
    check (status in ('Pending', 'Fulfilled'));
exception
  when duplicate_object then null;
end $$;

drop policy if exists "good_moral_requests_student_insert_own" on public.good_moral_requests;
create policy "good_moral_requests_student_insert_own"
  on public.good_moral_requests
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'Student'::app_role
        and p.id = good_moral_requests.student_id
    )
  );

drop policy if exists "good_moral_requests_parent_insert_child" on public.good_moral_requests;
create policy "good_moral_requests_parent_insert_child"
  on public.good_moral_requests
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.parent_student_links l
      join public.profiles p on p.id = l.parent_id
      where l.parent_id = auth.uid()
        and l.student_id = good_moral_requests.student_id
        and p.role = 'Parent'::app_role
    )
  );
