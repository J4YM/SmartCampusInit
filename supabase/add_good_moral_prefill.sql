-- Good Moral request: the student's own details, readable by the student and
-- by a linked parent.
--
-- The request form fills in name, student number, section and contact number
-- from the account and locks them. Reading students / profiles / sections
-- directly depends on each role's table policies; this function returns just
-- those fields for the student themselves or a parent linked to them, so the
-- form fills in the same way in both portals.
--
-- Run in Supabase SQL Editor. Idempotent.

create or replace function public.good_moral_prefill(p_student_id uuid)
returns table (
  last_name text,
  first_name text,
  student_number text,
  section text,
  contact_number text,
  enrollment_year text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.last_name::text,
         p.first_name::text,
         s.student_number::text,
         sec.name::text,
         p.phone_number::text,
         s.enrollment_year::text
    from public.students s
    join public.profiles p on p.id = s.id
    left join public.sections sec on sec.id = s.section_id
   where s.id = p_student_id
     and (
       auth.role() <> 'authenticated'
       or p_student_id = auth.uid()
       or exists (
         select 1 from public.parent_student_links l
          where l.student_id = p_student_id and l.parent_id = auth.uid())
     );
$$;

revoke all on function public.good_moral_prefill(uuid) from public;
grant execute on function public.good_moral_prefill(uuid) to anon, authenticated;
