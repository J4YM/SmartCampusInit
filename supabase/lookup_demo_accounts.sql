-- READ-ONLY. Finds the two demo accounts so the batch-upload sample files
-- can match them exactly. Run in Supabase SQL Editor and paste the results.

-- Carl Vinson Ventura (student)
select s.*, p.email, p.first_name, p.last_name
from public.students s
join public.profiles p on p.id = s.id
where p.first_name ilike '%carl%' and p.last_name ilike '%ventura%';

-- Ramon Villanueva (demo professor)
select id, first_name, last_name, email, employee_id, department, role
from public.profiles
where id = '00000000-0000-4000-8000-000000000002'
   or (first_name ilike 'ramon' and last_name ilike 'villanueva');
