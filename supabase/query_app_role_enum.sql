-- List allowed values for profiles.role (enum app_role).
-- Use the exact label in PROFILE_ROLE_STUDENT / .env (case-sensitive).

select e.enumlabel as app_role_value
from pg_type t
join pg_enum e on t.oid = e.enumtypid
where t.typname = 'app_role'
order by e.enumsortorder;
