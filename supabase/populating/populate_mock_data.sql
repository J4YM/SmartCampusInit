-- Mock / sample data for local development — fills every dashboard (System
-- Overview, Student Directory, RFID Mapping, Staff Accounts, Audit Logs,
-- Good Moral requests) with realistic-looking data so they're not empty
-- while real enrollment/hardware isn't hooked up yet.
--
-- Run this AFTER (in this order):
--   add_oauth_role_approval_schema.sql   (profiles.status/email/rfid_card_id,
--                                          `approval_status` type)
--   add_admin_dashboard_schema.sql       (profiles.department/phone_number/
--                                          is_active/last_login_at, audit_logs)
--   add_discipline_officer_schema.sql    (student_violations.is_escalated/
--                                          sla_due_at — optional, see part 6)
--   add_good_moral_requests_schema.sql   (good_moral_requests table)
--   seed_sections.sql                    (not required — this script seeds
--                                          the same sections itself)
--
-- What this creates:
--   - 250 mock students (`students_repository.dart`'s program list, spread
--     across years 1-4 and A/B sections), student numbers 900001-900250 so
--     they never collide with a real enrollment number.
--     - ~19 of them are left "pre-registered but unclaimed" (is_anonymous
--       auth user, no email) — exactly the RFID-Management-module state that
--       `claim_preregistered_student()` (see
--       ../add_student_self_registration_schema.sql) is meant to reconcile,
--       so you can test that flow against real-looking data by signing in
--       with a matching email locally.
--     - ~70% of the rest have an RFID card on file (`students.rfid_uid` AND
--       `profiles.rfid_card_id`, kept equal); the remainder are
--       intentionally unassigned so the RFID Mapping / "Unassigned" badge
--       has something to show too.
--   - 15 mock staff accounts (13 approved across every staff role, 2 left
--     `pending` for the Staff Accounts approval queue).
--   - ~16 Good Moral / clearance requests against the claimed students.
--   - 90 audit log entries spread over the last 30 days.
--   - Up to 40 `student_violations` rows — best-effort, see part 6; this is
--     the one section you're most likely to need to adjust, since this
--     table's full column set isn't versioned anywhere in this repo.
--
-- Every row is deterministic (IDs are derived from stable seeds via
-- `_mock_uuid`), so it's safe to run more than once: no duplicate students/
-- staff/sections get created. `profiles` specifically uses `on conflict (id)
-- do update` rather than `do nothing` — re-running repairs, rather than
-- duplicates, anything the auth trigger raced ahead of on a prior run.
--
-- To remove everything this script created:
--   delete from public.profiles where id in (
--     select id from public.students where student_number between '900001' and '900250'
--   );
--   delete from public.profiles where email in (
--     'ramon.santos@baliuag.sti.edu.ph','teresa.manalo@baliuag.sti.edu.ph',
--     'antonio.cruz@baliuag.sti.edu.ph','carmen.reyes@baliuag.sti.edu.ph',
--     'manuel.torres@baliuag.sti.edu.ph','elena.bautista@baliuag.sti.edu.ph',
--     'rosa.fernandez@baliuag.sti.edu.ph','miguel.villanueva@baliuag.sti.edu.ph',
--     'precious.aquino@baliuag.sti.edu.ph','nathaniel.domingo@baliuag.sti.edu.ph',
--     'bianca.mercado@baliuag.sti.edu.ph','joshua.pascual@baliuag.sti.edu.ph',
--     'kristine.ocampo@baliuag.sti.edu.ph','vincent.navarro@baliuag.sti.edu.ph',
--     'faith.rivera@baliuag.sti.edu.ph'
--   );
--   -- (both deletes cascade to `students`, `student_violations`,
--   -- `good_moral_requests`, and `auth.users` rows created for them, per
--   -- their existing FK setup — audit_logs.actor_id references profiles
--   -- `on delete set null`, so log rows are kept for history.)
--
-- Run in Supabase SQL Editor.

do $$ begin
  create extension if not exists pgcrypto;
exception when others then
  raise notice 'Could not ensure pgcrypto extension (may already be enabled): %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 0. Deterministic UUID helper — same seed always maps to the same id, so
--    every insert below can safely use `on conflict (id) do nothing` and
--    this script is idempotent.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 1. Sections (kept in sync with ../seed_sections.sql; harmless if already seeded)
-- ---------------------------------------------------------------------------
insert into public.sections (name, program, year_level) values
  ('BSIT-1A', 'BS Information Technology', 1), ('BSIT-1B', 'BS Information Technology', 1),
  ('BSIT-2A', 'BS Information Technology', 2), ('BSIT-2B', 'BS Information Technology', 2),
  ('BSIT-3A', 'BS Information Technology', 3), ('BSIT-3B', 'BS Information Technology', 3),
  ('BSIT-4A', 'BS Information Technology', 4), ('BSIT-4B', 'BS Information Technology', 4),
  ('BSHM-1A', 'BS Hospitality Management', 1), ('BSHM-1B', 'BS Hospitality Management', 1),
  ('BSHM-2A', 'BS Hospitality Management', 2), ('BSHM-2B', 'BS Hospitality Management', 2),
  ('BSHM-3A', 'BS Hospitality Management', 3), ('BSHM-3B', 'BS Hospitality Management', 3),
  ('BSHM-4A', 'BS Hospitality Management', 4), ('BSHM-4B', 'BS Hospitality Management', 4),
  ('BSBA-1A', 'BS Business Administration', 1), ('BSBA-1B', 'BS Business Administration', 1),
  ('BSBA-2A', 'BS Business Administration', 2), ('BSBA-2B', 'BS Business Administration', 2),
  ('BSBA-3A', 'BS Business Administration', 3), ('BSBA-3B', 'BS Business Administration', 3),
  ('BSBA-4A', 'BS Business Administration', 4), ('BSBA-4B', 'BS Business Administration', 4),
  ('BSTM-1A', 'BS Tourism Management', 1), ('BSTM-1B', 'BS Tourism Management', 1),
  ('BSTM-2A', 'BS Tourism Management', 2), ('BSTM-2B', 'BS Tourism Management', 2),
  ('BSTM-3A', 'BS Tourism Management', 3), ('BSTM-3B', 'BS Tourism Management', 3),
  ('BSTM-4A', 'BS Tourism Management', 4), ('BSTM-4B', 'BS Tourism Management', 4)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. 250 mock students
-- ---------------------------------------------------------------------------
drop table if exists _mock_students;
create temporary table _mock_students as
with params as (
  select
    array[
      'Juan','Maria','Jose','Ana','Pedro','Rosa','Antonio','Carmen','Manuel','Elena',
      'Ramon','Teresa','Miguel','Andrea','Rafael','Kimberly','Christian','Precious',
      'Nathaniel','Bianca','Samantha','Josh','Angel','Joshua','Kyle','Erika','Mark',
      'Nicole','John','Grace','Paolo','Bea','Vincent','Kristine','Marc','Cielo',
      'Adrian','Jasmine','Xander','Faith'
    ]::text[] as first_names,
    array[
      'Dela Cruz','Santos','Reyes','Cruz','Bautista','Villanueva','Mercado','Domingo',
      'Fernandez','Torres','Lopez','Garcia','Gonzales','Ramos','Aquino','Castillo',
      'Pascual','Mendoza','Rivera','Salazar','Navarro','Ocampo','Del Rosario','Tolentino',
      'Manalo','Ignacio','Bernardo','Villareal','Marquez','Cortez','Agustin','Espino',
      'Roque','Guevarra','Panganiban','Lim','Tan','Uy','Yu','Sy'
    ]::text[] as last_names,
    array['BS Information Technology','BS Hospitality Management',
          'BS Business Administration','BS Tourism Management']::text[] as programs,
    array['BSIT','BSHM','BSBA','BSTM']::text[] as program_codes
),
generated as (
  select
    i,
    params.first_names[1 + (i % array_length(params.first_names, 1))] as first_name,
    params.last_names[1 + ((i * 7) % array_length(params.last_names, 1))] as last_name,
    1 + (i % 4) as year_level,
    params.programs[1 + (i % 4)] as program,
    params.program_codes[1 + (i % 4)] as program_code,
    (case when i % 2 = 0 then 'A' else 'B' end) as section_letter,
    lpad((900000 + i)::text, 6, '0') as student_number,
    (i % 13 = 0) as is_unclaimed,
    (i % 10 < 7) as has_rfid,
    now() - (i % 180) * interval '1 day' - (i % 24) * interval '1 hour' as created_at
  from generate_series(1, 250) as i
  cross join params
),
slugged as (
  select
    *,
    regexp_replace(lower(last_name), '[^a-z]', '', 'g') as last_name_slug,
    program_code || '-' || year_level || section_letter as section_name
  from generated
)
select
  public._mock_uuid('student:' || i::text) as id,
  i,
  first_name,
  last_name,
  year_level,
  program,
  section_name,
  student_number,
  is_unclaimed,
  has_rfid,
  created_at,
  case when is_unclaimed then null
       else last_name_slug || '.' || student_number || '@baliuag.sti.edu.ph' end as email,
  case when has_rfid and not is_unclaimed then
    upper(substr(md5(student_number || ':rfid'), 1, 2)) || ':' ||
    upper(substr(md5(student_number || ':rfid'), 3, 2)) || ':' ||
    upper(substr(md5(student_number || ':rfid'), 5, 2)) || ':' ||
    upper(substr(md5(student_number || ':rfid'), 7, 2))
  else null end as rfid_uid
from slugged;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
)
select
  id,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'authenticated', 'authenticated',
  email,
  crypt('mock-data-not-a-real-login', gen_salt('bf')),
  case when is_unclaimed then null else created_at end,
  case when is_unclaimed
       then '{"provider":"anonymous","providers":["anonymous"]}'::jsonb
       else '{"provider":"azure","providers":["azure"]}'::jsonb end,
  '{}'::jsonb,
  is_unclaimed,
  created_at,
  created_at
from _mock_students
on conflict (id) do nothing;

-- `do update`, not `do nothing`: inserting into auth.users above fires
-- `on_auth_user_created` (add_oauth_role_approval_schema.sql) for every
-- claimed student (real, non-anonymous email), which immediately creates
-- its own blank public.profiles row (first_name='', last_name='') before
-- this insert runs. `do nothing` would lose that race and leave every
-- claimed mock student's name blank — which is exactly what happened.
insert into public.profiles (id, email, first_name, last_name, role, status, rfid_card_id, created_at)
select
  id, email, first_name, last_name,
  'Student'::app_role, 'approved'::approval_status, rfid_uid, created_at
from _mock_students
on conflict (id) do update set
  email = excluded.email,
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  role = excluded.role,
  status = excluded.status,
  rfid_card_id = excluded.rfid_card_id;

insert into public.students (id, student_number, rfid_uid, course, year_level, section_id)
select m.id, m.student_number, m.rfid_uid, m.program, m.year_level, sec.id
from _mock_students m
join public.sections sec
  on sec.program = m.program and sec.year_level = m.year_level and sec.name = m.section_name
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. 15 mock staff accounts (13 approved across every role, 2 pending)
-- ---------------------------------------------------------------------------
drop table if exists _mock_staff;
create temporary table _mock_staff as
select t.*, now() - (row_number() over () % 90) * interval '1 day' as created_at
from (values
  ('staff:1',  'ramon.santos@baliuag.sti.edu.ph',      'Ramon',      'Santos',      'Admin',              'approved', 'Information Technology Office',  '+63 917 000 0001', true),
  ('staff:2',  'teresa.manalo@baliuag.sti.edu.ph',      'Teresa',     'Manalo',      'Admin',              'approved', 'Office of the Registrar',        '+63 917 000 0002', true),
  ('staff:3',  'antonio.cruz@baliuag.sti.edu.ph',       'Antonio',    'Cruz',        'Teacher',            'approved', 'College of Information Technology','+63 917 000 0003', true),
  ('staff:4',  'carmen.reyes@baliuag.sti.edu.ph',       'Carmen',     'Reyes',       'Teacher',            'approved', 'College of Business Administration','+63 917 000 0004', true),
  ('staff:5',  'manuel.torres@baliuag.sti.edu.ph',      'Manuel',     'Torres',      'Teacher',            'approved', 'College of Tourism Management',  '+63 917 000 0005', false),
  ('staff:6',  'elena.bautista@baliuag.sti.edu.ph',     'Elena',      'Bautista',    'Registrar',          'approved', 'Office of the Registrar',         '+63 917 000 0006', true),
  ('staff:7',  'rosa.fernandez@baliuag.sti.edu.ph',     'Rosa',       'Fernandez',   'Registrar',          'approved', 'Office of the Registrar',         '+63 917 000 0007', true),
  ('staff:8',  'miguel.villanueva@baliuag.sti.edu.ph',  'Miguel',     'Villanueva',  'Discipline_Officer', 'approved', 'Office of Student Affairs',       '+63 917 000 0008', true),
  ('staff:9',  'precious.aquino@baliuag.sti.edu.ph',    'Precious',   'Aquino',      'Discipline_Officer', 'approved', 'Office of Student Affairs',       '+63 917 000 0009', true),
  ('staff:10', 'nathaniel.domingo@baliuag.sti.edu.ph',  'Nathaniel',  'Domingo',     'Guidance_Counselor', 'approved', 'Guidance and Counseling Office',  '+63 917 000 0010', true),
  ('staff:11', 'bianca.mercado@baliuag.sti.edu.ph',     'Bianca',     'Mercado',     'Guidance_Counselor', 'approved', 'Guidance and Counseling Office',  '+63 917 000 0011', true),
  ('staff:12', 'joshua.pascual@baliuag.sti.edu.ph',     'Joshua',     'Pascual',     'Security',           'approved', 'Campus Security Office',          '+63 917 000 0012', true),
  ('staff:13', 'kristine.ocampo@baliuag.sti.edu.ph',    'Kristine',   'Ocampo',      'Security',           'approved', 'Campus Security Office',          '+63 917 000 0013', false),
  ('staff:14', 'vincent.navarro@baliuag.sti.edu.ph',    'Vincent',    'Navarro',     null,                 'pending',  null,                              null,               true),
  ('staff:15', 'faith.rivera@baliuag.sti.edu.ph',       'Faith',      'Rivera',      null,                 'pending',  null,                              null,               true)
) as t(seed, email, first_name, last_name, role, status, department, phone_number, is_active);

alter table _mock_staff add column id uuid;
update _mock_staff set id = public._mock_uuid(seed);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
)
select
  id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
  email, crypt('mock-data-not-a-real-login', gen_salt('bf')), created_at,
  '{"provider":"azure","providers":["azure"]}'::jsonb, '{}'::jsonb, false,
  created_at, created_at
from _mock_staff
on conflict (id) do nothing;

-- Same trigger race as the student profiles insert above: `do update` so
-- this script's real name/role/approved-status always wins over the blank
-- pending row `on_auth_user_created` creates first.
insert into public.profiles (
  id, email, first_name, last_name, role, status, department, phone_number,
  is_active, last_login_at, created_at
)
select
  id, email, first_name, last_name,
  case when role is null then null else role::app_role end,
  status::approval_status,
  department, phone_number, is_active,
  case when status = 'approved' then created_at + interval '2 hours' else null end,
  created_at
from _mock_staff
on conflict (id) do update set
  email = excluded.email,
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  role = excluded.role,
  status = excluded.status,
  department = excluded.department,
  phone_number = excluded.phone_number,
  is_active = excluded.is_active,
  last_login_at = excluded.last_login_at;

-- ---------------------------------------------------------------------------
-- 4. Good Moral / clearance requests (against claimed students only)
-- ---------------------------------------------------------------------------
insert into public.good_moral_requests (student_id, document_type, purpose, requested_by, request_date, remarks)
select
  s.id,
  (array['Good Moral Certificate', 'Certificate of Clearance'])[1 + (m.i % 2)],
  (array['Employment application', 'Scholarship application', 'School transfer',
         'Graduation requirement', 'Internship requirement'])[1 + (m.i % 5)],
  m.first_name || ' ' || m.last_name,
  m.created_at + ((m.i % 60) * interval '1 day'),
  'Mock data — clearance status: ' ||
    (array['Eligible', 'Conditional', 'Ineligible'])[1 + (m.i % 3)]
from _mock_students m
join public.students s on s.id = m.id
where m.is_unclaimed = false and m.i % 15 = 0;

-- ---------------------------------------------------------------------------
-- 5. Audit log entries (90 rows over the last 30 days, mock staff as actors)
-- ---------------------------------------------------------------------------
insert into public.audit_logs (occurred_at, actor_id, actor_email, actor_role, action, ip_address, severity)
select
  now() - (g.n % 30) * interval '1 day' - (g.n % 24) * interval '1 hour',
  st.id, st.email, st.role::app_role,
  (array[
    'Signed in', 'Viewed student record', 'Approved staff account',
    'Linked RFID card', 'Exported compliance report', 'Updated violation status',
    'Retrained ML risk model', 'Sent parent notification'
  ])[1 + (g.n % 8)],
  '10.0.' || (1 + (g.n % 254))::text || '.' || (1 + ((g.n * 3) % 254))::text,
  (array['INFO', 'INFO', 'INFO', 'WARN', 'CRITICAL'])[1 + (g.n % 5)]::audit_severity
from generate_series(1, 90) as g(n)
join lateral (
  select id, email, role from _mock_staff
  where role is not null
  order by md5(seed || g.n::text)
  limit 1
) st on true;

-- ---------------------------------------------------------------------------
-- 6. student_violations
--
-- Confirmed columns (via Table Editor): id, student_id, offense_id,
-- reported_by, evidence_url, status (`violation_status` enum),
-- acknowledged_at, penalty_imposed, created_at, updated_at, is_escalated,
-- sla_due_at. Two FKs besides `student_id` are NOT NULL with no default —
-- `offense_id` (an offenses/violation-type lookup table) and `reported_by`
-- (the staff member who filed it, almost certainly `profiles`) — so both
-- need a value on every insert. This block:
--   - resolves every such FK column generically (reuses an existing row in
--     whatever table it references; for `reported_by` it prefers a mock
--     Discipline Officer/Security/Teacher account over an arbitrary row;
--     failing that, inserts one empty placeholder row if the referenced
--     table's own columns all have defaults);
--   - auto-picks a "pending"-like `violation_status` label (falls back to
--     the enum's first label) so this doesn't have to hardcode a guess at
--     your actual enum values;
--   - leaves `evidence_url` / `acknowledged_at` / `penalty_imposed` unset
--     (all nullable);
--   - wraps each row's insert in its own exception handler so anything
--     still unresolved is reported via `raise notice` and that row is
--     skipped, rather than aborting the whole script.
-- ---------------------------------------------------------------------------
do $$
declare
  v_cols text[];
  v_cols_present text[];
  v_vals_present text[];
  v_sql text;
  v_row_num int;
  v_inserted int := 0;
  v_skipped int := 0;
  v_fk record;
  v_fk_value text;
  v_fk_values jsonb := '{}'::jsonb;
  v_status_label text;
begin
  if to_regclass('public.student_violations') is null then
    raise notice 'Skipping student_violations mock data: table public.student_violations not found.';
    return;
  end if;

  select array_agg(column_name) into v_cols
    from information_schema.columns
    where table_schema = 'public' and table_name = 'student_violations';

  -- Resolve every NOT NULL, no-default FK column other than `student_id`
  -- (expected: offense_id, reported_by — written generically in case your
  -- schema has more or fewer).
  for v_fk in
    select kcu.column_name as col, ccu.table_schema as ref_schema,
           ccu.table_name as ref_table, ccu.column_name as ref_col
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on kcu.constraint_name = tc.constraint_name and kcu.constraint_schema = tc.constraint_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name and ccu.constraint_schema = tc.constraint_schema
    join information_schema.columns col
      on col.table_schema = tc.table_schema and col.table_name = tc.table_name
     and col.column_name = kcu.column_name
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and tc.table_name = 'student_violations'
      and kcu.column_name <> 'student_id'
      and col.is_nullable = 'NO'
      and col.column_default is null
  loop
    v_fk_value := null;

    -- Prefer a real mock staff member (matters most for `reported_by`);
    -- harmless no-op if `_mock_staff` doesn't exist or shares no ids with
    -- whatever table this FK actually points to.
    begin
      execute format(
        'select %I::text from %I.%I where id in ('
        '  select id from _mock_staff where role in (''Discipline_Officer'', ''Security'', ''Teacher'')'
        ') limit 1',
        v_fk.ref_col, v_fk.ref_schema, v_fk.ref_table
      ) into v_fk_value;
    exception when others then
      v_fk_value := null;
    end;

    if v_fk_value is null then
      execute format('select %I::text from %I.%I limit 1', v_fk.ref_col, v_fk.ref_schema, v_fk.ref_table)
        into v_fk_value;
    end if;

    if v_fk_value is null then
      begin
        execute format(
          'insert into %I.%I default values returning %I::text',
          v_fk.ref_schema, v_fk.ref_table, v_fk.ref_col
        ) into v_fk_value;
        raise notice 'Seeded one placeholder row in %.% to satisfy student_violations.%.',
          v_fk.ref_schema, v_fk.ref_table, v_fk.col;
      exception when others then
        v_fk_value := null;
      end;
    end if;

    if v_fk_value is not null then
      v_fk_values := v_fk_values || jsonb_build_object(v_fk.col, v_fk_value);
      raise notice 'Auto-resolved student_violations.% using row % from %.%.',
        v_fk.col, v_fk_value, v_fk.ref_schema, v_fk.ref_table;
    else
      raise notice 'Could not auto-resolve required column "%" (references %.%, which has no rows '
        'and would not accept a blank placeholder row). Rows needing this column will be skipped — '
        'insert at least one row into %.% yourself, then re-run this section.',
        v_fk.col, v_fk.ref_schema, v_fk.ref_table, v_fk.ref_schema, v_fk.ref_table;
    end if;
  end loop;

  -- Auto-pick a "pending"-like `violation_status` label without hardcoding
  -- your actual enum values.
  if 'status' = any(v_cols) then
    select e.enumlabel into v_status_label
    from information_schema.columns c
    join pg_type t on t.typname = c.udt_name
    join pg_enum e on e.enumtypid = t.oid
    where c.table_schema = 'public' and c.table_name = 'student_violations' and c.column_name = 'status'
    order by (lower(e.enumlabel) not like '%pend%'), e.enumsortorder
    limit 1;
  end if;

  for v_row_num in 1..40 loop
    v_cols_present := array['student_id'];
    v_vals_present := array[(
      select quote_literal(id::text)
      from _mock_students
      where is_unclaimed = false
      order by md5(id::text || v_row_num::text)
      limit 1
    )];

    if v_fk_values ? 'offense_id' then
      v_cols_present := v_cols_present || 'offense_id'::text;
      v_vals_present := v_vals_present || quote_literal(v_fk_values ->> 'offense_id');
    end if;

    if v_fk_values ? 'reported_by' then
      v_cols_present := v_cols_present || 'reported_by'::text;
      v_vals_present := v_vals_present || quote_literal(v_fk_values ->> 'reported_by');
    end if;

    if 'is_escalated' = any(v_cols) then
      v_cols_present := v_cols_present || 'is_escalated'::text;
      v_vals_present := v_vals_present || (case when v_row_num % 6 = 0 then 'true' else 'false' end)::text;
    end if;

    if 'sla_due_at' = any(v_cols) then
      v_cols_present := v_cols_present || 'sla_due_at'::text;
      v_vals_present := v_vals_present ||
        (quote_literal((now() + (v_row_num % 12) * interval '1 hour')::text) || '::timestamptz');
    end if;

    if 'status' = any(v_cols) and v_status_label is not null then
      v_cols_present := v_cols_present || 'status'::text;
      v_vals_present := v_vals_present || quote_literal(v_status_label);
    end if;

    if 'created_at' = any(v_cols) then
      v_cols_present := v_cols_present || 'created_at'::text;
      v_vals_present := v_vals_present ||
        (quote_literal((now() - (v_row_num % 45) * interval '1 day')::text) || '::timestamptz');
    end if;

    if 'updated_at' = any(v_cols) then
      v_cols_present := v_cols_present || 'updated_at'::text;
      v_vals_present := v_vals_present || (quote_literal(now()::text) || '::timestamptz');
    end if;

    v_sql := format(
      'insert into public.student_violations (%s) values (%s)',
      array_to_string(v_cols_present, ', '),
      array_to_string(v_vals_present, ', ')
    );

    begin
      execute v_sql;
      v_inserted := v_inserted + 1;
    exception when others then
      v_skipped := v_skipped + 1;
      if v_skipped = 1 then
        raise notice 'student_violations insert failed (showing first failure only): % — SQL: %',
          sqlerrm, v_sql;
      end if;
    end;
  end loop;

  raise notice 'student_violations: inserted %, skipped % (columns used: %)',
    v_inserted, v_skipped, array_to_string(v_cols_present, ', ');
end $$;

-- ---------------------------------------------------------------------------
-- Cleanup of session-local helper tables (the `_mock_uuid` function is left
-- in place — harmless, and handy if you extend this script later).
-- ---------------------------------------------------------------------------
drop table if exists _mock_students;
drop table if exists _mock_staff;
