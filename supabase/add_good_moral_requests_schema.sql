-- Schema additions for the Discipline Officer Dashboard's new "Good Moral"
-- tab (packages/discipline_officer_module), added upstream in
-- CipherPunk-7800/Capstone-Project commit "DO Dashboard update".
--
-- `GoodMoralRequestModel` (queue) and `StudentDirectoryEntryModel` (browse-
-- all-students list) are both still UI-only placeholders (empty lists, no
-- Supabase calls yet). `StudentDirectoryEntryModel` needs no schema changes
-- — it's just a read view over `students` + `profiles` + `sections` that
-- already exist. `GoodMoralRequestModel` has no home anywhere: it's a
-- request for a document (Good Moral Certificate, Certificate of Clearance,
-- etc.) with its own purpose/requester/date per request — a per-student
-- boolean (`students.good_moral_status`) can't hold multiple requests over
-- time, so this needs its own table, exactly as the module's own
-- `_handleGenerateCertificate` TODO comment names it
-- ("`good_moral_requests` table").
--
-- The UI has no approve/deny workflow yet (no status field on the model,
-- no accept/reject method on its controller — only select + an empty
-- "Generate Certificate" stub), so no `status` column is added here either;
-- add one once that workflow is actually built, matching how this project's
-- other schema files only model what the UI concretely references today.
--
-- Run in Supabase SQL Editor.

create table if not exists public.good_moral_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  document_type text not null,
  purpose text not null,
  requested_by text not null,
  request_date timestamptz not null default now(),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists good_moral_requests_student_id_idx
  on public.good_moral_requests (student_id);

alter table public.good_moral_requests enable row level security;

-- Same staff-management shape as `student_violations` — Discipline Officer,
-- Guidance Counselor, and Admin handle these requests; every other role is
-- excluded by omission (no policy = no access once RLS is enabled).
drop policy if exists "good_moral_requests_discipline_guidance_full" on public.good_moral_requests;
create policy "good_moral_requests_discipline_guidance_full"
  on public.good_moral_requests
  for all
  to authenticated
  using (current_user_role() = ANY (ARRAY['Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role, 'Admin'::app_role]))
  with check (current_user_role() = ANY (ARRAY['Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role, 'Admin'::app_role]));

-- Student/parent self-service read, matching `student_violations`'s
-- `violations_student_select_own` / `violations_parent_select_child` shape,
-- since a request likely originates from the student or their parent.
drop policy if exists "good_moral_requests_student_select_own" on public.good_moral_requests;
create policy "good_moral_requests_student_select_own"
  on public.good_moral_requests
  for select
  to public
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'Student'::app_role
        and p.id = good_moral_requests.student_id
    )
  );

drop policy if exists "good_moral_requests_parent_select_child" on public.good_moral_requests;
create policy "good_moral_requests_parent_select_child"
  on public.good_moral_requests
  for select
  to public
  using (
    exists (
      select 1
      from public.parent_student_links l
      join public.profiles p on p.id = l.parent_id
      where l.parent_id = auth.uid()
        and l.student_id = good_moral_requests.student_id
        and p.role = 'Parent'::app_role
    )
  );
