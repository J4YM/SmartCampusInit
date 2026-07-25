-- Adds sample `student_violations` + `good_moral_requests` rows for
-- whichever students already exist in `public.students` — real enrollments,
-- or ones created by populate_mock_data.sql. Run this any time you want more
-- sample activity for the Discipline Officer dashboard / System Overview,
-- independent of re-seeding students themselves.
--
-- Requires (run first, if not already applied):
--   add_discipline_officer_schema.sql, add_good_moral_requests_schema.sql
--   (see supabase/), and at least one row already in public.students.
--
-- Each run adds a NEW batch on top of whatever's already there — this is
-- intentionally not idempotent (student_violations/good_moral_requests have
-- no natural key to dedupe on), so re-run whenever you want fresher-looking
-- "today" activity rather than expecting a second run to be a no-op.
--
-- Run in Supabase SQL Editor.

-- ---------------------------------------------------------------------------
-- 1. Seed a starter handbook of offenses if `handbook_offenses` is empty.
--    Spans every `category` severity tier (Minor, Major_A..D) confirmed via
--    Table Editor. `values (...)` literals get Postgres's "unknown" type and
--    would auto-cast fine in a direct `insert ... values (...)`, but once
--    wrapped in `select * from (values ...) as t(...)` the column becomes
--    concretely `text`, and `text -> offense_category` needs an explicit
--    cast (confirmed enum type name from the earlier error message).
-- ---------------------------------------------------------------------------
insert into public.handbook_offenses (category, description, penalty_info)
select category::offense_category, description, penalty_info
from (values
  ('Minor', 'Improper or incomplete school uniform', 'Warning and uniform completion within 3 days.'),
  ('Minor', 'Tardiness / late arrival to class', 'Verbal warning; parent notice on the 3rd offense.'),
  ('Minor', 'Unauthorized use of mobile phone during class', 'Confiscation until end of day; returned to parent on repeat.'),
  ('Minor', 'Littering or improper waste disposal', 'Warning and campus clean-up duty.'),
  ('Major_A', 'Cutting classes without permission', 'Parent conference and written warning.'),
  ('Major_A', 'Disrespect toward a faculty member or staff', 'Parent conference; guidance counseling referral.'),
  ('Major_B', 'Vandalism of school property', 'Restitution for damages and suspension.'),
  ('Major_B', 'Cheating or other academic dishonesty', 'Failing mark on the activity and disciplinary probation.'),
  ('Major_C', 'Bullying or harassment of another student', 'Suspension and mandatory counseling.'),
  ('Major_C', 'Possession of prohibited items (e.g. vape, weapons)', 'Confiscation, parent conference, suspension.'),
  ('Major_D', 'Fighting or physical altercation on campus', 'Suspension pending review by the Discipline Board.'),
  ('Major_D', 'Falsification of school documents or records', 'Disciplinary probation and possible expulsion review.')
) as t(category, description, penalty_info)
where not exists (select 1 from public.handbook_offenses);

-- ---------------------------------------------------------------------------
-- 2. Ensure at least one eligible violation reporter exists.
--    `student_violations.reported_by` is a required FK to an approved
--    Discipline_Officer/Security/Teacher profile. If none exist yet (e.g.
--    this script is run without ever running populate_mock_data.sql's staff
--    section), the WHERE EXISTS guard in part 3 below matches zero rows —
--    the insert "succeeds" with 0 rows and no error, which is exactly what
--    happened the first time this ran. Self-contained fallback: seed 3
--    minimal reporter accounts (same auth.users + deterministic-UUID
--    technique as populate_mock_data.sql) only if none already exist.
--
--    IMPORTANT: inserting into `auth.users` fires `on_auth_user_created`
--    (add_oauth_role_approval_schema.sql), which — since these emails match
--    the staff pattern (firstname.lastname@baliuag.sti.edu.ph) — immediately
--    inserts its own `public.profiles` row with `role = null, status =
--    'pending'` before this script's own profiles insert below ever runs.
--    An `on conflict (id) do nothing` there would silently lose the race and
--    leave these 3 accounts stuck pending/roleless forever (which is exactly
--    what happened: v_reporter_count stayed 0 on every re-run). Use
--    `do update` instead so this script's correct role/status always wins.
-- ---------------------------------------------------------------------------
do $$ begin
  create extension if not exists pgcrypto;
exception when others then
  raise notice 'Could not ensure pgcrypto extension (may already be enabled): %', sqlerrm;
end $$;

create or replace function public._mock_uuid(p_seed text)
returns uuid
language sql
immutable
as $$
  select (
    substr(h, 1, 8) || '-' || substr(h, 9, 4) || '-' || substr(h, 13, 4) || '-' ||
    substr(h, 17, 4) || '-' || substr(h, 21, 12)
  )::uuid
  from (select md5('sti-baliuag-mock:' || p_seed) as h) as x;
$$;

do $$
begin
  if exists (
    select 1 from public.profiles
    where status = 'approved'
      and role in ('Discipline_Officer'::app_role, 'Security'::app_role, 'Teacher'::app_role)
  ) then
    raise notice 'Found an existing approved Discipline_Officer/Security/Teacher account — skipping fallback reporter seeding.';
    return;
  end if;

  raise notice 'No approved Discipline_Officer/Security/Teacher account found — seeding 3 fallback reporter accounts.';

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  select id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    email, crypt('mock-data-not-a-real-login', gen_salt('bf')), now(),
    '{"provider":"azure","providers":["azure"]}'::jsonb, '{}'::jsonb, false, now(), now()
  from (values
    (public._mock_uuid('violations-reporter:1'), 'ramon.delacruz@baliuag.sti.edu.ph'),
    (public._mock_uuid('violations-reporter:2'), 'teresa.santoscruz@baliuag.sti.edu.ph'),
    (public._mock_uuid('violations-reporter:3'), 'miguel.reyesbautista@baliuag.sti.edu.ph')
  ) as t(id, email)
  on conflict (id) do nothing;

  insert into public.profiles (
    id, email, first_name, last_name, role, status, department, is_active, created_at
  )
  select id, email, first_name, last_name, role, status, department, is_active, created_at
  from (values
    (
      public._mock_uuid('violations-reporter:1'), 'ramon.delacruz@baliuag.sti.edu.ph',
      'Ramon', 'Dela Cruz', 'Discipline_Officer'::app_role, 'approved'::approval_status,
      'Office of Student Affairs', true, now()
    ),
    (
      public._mock_uuid('violations-reporter:2'), 'teresa.santoscruz@baliuag.sti.edu.ph',
      'Teresa', 'Santos Cruz', 'Security'::app_role, 'approved'::approval_status,
      'Campus Security Office', true, now()
    ),
    (
      public._mock_uuid('violations-reporter:3'), 'miguel.reyesbautista@baliuag.sti.edu.ph',
      'Miguel', 'Reyes Bautista', 'Teacher'::app_role, 'approved'::approval_status,
      'College of Information Technology', true, now()
    )
  ) as t(id, email, first_name, last_name, role, status, department, is_active, created_at)
  on conflict (id) do update set
    role = excluded.role,
    status = excluded.status,
    department = excluded.department,
    is_active = excluded.is_active,
    first_name = excluded.first_name,
    last_name = excluded.last_name;
end $$;

-- ---------------------------------------------------------------------------
-- 3. student_violations for ~60% of existing students (2 each).
-- ---------------------------------------------------------------------------
do $$
declare
  v_reporter_count int;
begin
  if not exists (select 1 from public.students) then
    raise notice 'Skipping: public.students is empty — populate students first (see populate_mock_data.sql).';
    return;
  end if;

  if not exists (select 1 from public.handbook_offenses) then
    raise notice 'Skipping student_violations: public.handbook_offenses is still empty.';
    return;
  end if;

  select count(*) into v_reporter_count
    from public.profiles
    where status = 'approved'
      and role in ('Discipline_Officer'::app_role, 'Security'::app_role, 'Teacher'::app_role);

  if v_reporter_count = 0 then
    raise notice 'No approved Discipline_Officer/Security/Teacher profiles found — '
      'falling back to any approved staff account as reporter.';
  end if;

  insert into public.student_violations (
    student_id, offense_id, reported_by, status, is_escalated, sla_due_at,
    penalty_imposed, created_at, updated_at
  )
  select
    ts.id,
    (select id from public.handbook_offenses order by random() limit 1),
    coalesce(
      (select id from public.profiles
         where status = 'approved'
           and role in ('Discipline_Officer'::app_role, 'Security'::app_role, 'Teacher'::app_role)
         order by random() limit 1),
      (select id from public.profiles
         where status = 'approved' and role is not null
           and role not in ('Student'::app_role, 'Parent'::app_role)
         order by random() limit 1)
    ),
    (array['Pending', 'Under_Investigation', 'Resolved'])[1 + floor(random() * 3)::int]::violation_status,
    random() < 0.15,
    case when random() < 0.4 then now() + (random() * 48) * interval '1 hour' else null end,
    case (floor(random() * 4)::int)
      when 0 then 'Verbal warning issued.'
      when 1 then 'Written warning on file.'
      when 2 then 'Parent notified.'
      else null
    end,
    v.created_at,
    v.created_at + (random() * 5) * interval '1 day'
  from (
    select id from public.students order by random()
    limit greatest((select count(*) from public.students) * 6 / 10, 1)
  ) as ts
  cross join generate_series(1, 2) as gs(n)
  cross join lateral (
    select now() - (random() * 60) * interval '1 day' as created_at
  ) as v
  where exists (
    select 1 from public.profiles
    where status = 'approved' and role is not null
      and role not in ('Student'::app_role, 'Parent'::app_role)
  );
end $$;

-- ---------------------------------------------------------------------------
-- 4. good_moral_requests for ~30% of existing students (1 each).
-- ---------------------------------------------------------------------------
insert into public.good_moral_requests (
  student_id, document_type, purpose, requested_by, request_date, remarks
)
select
  s.id,
  case when random() < 0.5 then 'Good Moral Certificate' else 'Certificate of Clearance' end,
  (array[
    'Employment application', 'Scholarship application', 'School transfer',
    'Graduation requirement', 'Internship requirement'
  ])[1 + floor(random() * 5)::int],
  coalesce(
    nullif(trim(
      coalesce((select p.first_name from public.profiles p where p.id = s.id), '') || ' ' ||
      coalesce((select p.last_name from public.profiles p where p.id = s.id), '')
    ), ''),
    s.student_number
  ),
  now() - (random() * 45) * interval '1 day',
  case (floor(random() * 3)::int)
    when 0 then 'Clearance status: Eligible'
    when 1 then 'Clearance status: Conditional — pending sanction review'
    else 'Clearance status: Ineligible — active major offense on record'
  end
from (
  select id, student_number from public.students order by random()
  limit greatest((select count(*) from public.students) * 3 / 10, 1)
) as s;
