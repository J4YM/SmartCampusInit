-- Professor stubs created by a Classes+Professor / CFL / Room Schedule
-- upload used to get a synthetic `auto.professor.<uuid>@placeholder...`
-- email on public.profiles, which never matched the address the professor
-- actually signs in with (firstname.lastname@baliuag.sti.edu.ph).
--
-- This file:
--   1. create_auto_professor_profile takes p_email (derived client-side by
--      professorEmailFor in lib/data/schedule_import_repository.dart) and
--      stores it on the stub; falls back to the old placeholder address when
--      null (placeholder positions, single-word names) and to a numeric
--      suffix if that address is already taken.
--   2. handle_new_auth_user (latest version: add_registration_sync_log_schema.sql)
--      now adopts a matching approved Teacher stub on first Microsoft
--      sign-in: the new profile is created already `approved` as Teacher
--      (the stub proves they're a known professor), takes over the stub's
--      class_sections/class_assignments, employee_id, name and is_active,
--      and the stub + its placeholder auth.users row are removed. No
--      matching stub -> unchanged behaviour (pending, Admin approves).
--   3. Backfills existing auto.professor.* stubs with the derived email.
--
-- Run in Supabase SQL Editor after add_registration_sync_log_schema.sql and
-- add_professor_stub_reconciliation.sql. Idempotent.

-- ---------------------------------------------------------------------------
-- 1. create_auto_professor_profile(+p_email)
-- ---------------------------------------------------------------------------

drop function if exists public.create_auto_professor_profile(text, text, boolean);

create or replace function public.create_auto_professor_profile(
  p_employee_id text,
  p_full_name text,
  p_is_placeholder boolean,
  p_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text;
  v_base text;
  v_n int := 1;
  v_status public.approval_status;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to auto-create a professor profile.';
  end if;

  v_status := case when p_is_placeholder
    then 'Placeholder'::approval_status
    else 'approved'::approval_status
  end;

  v_base := nullif(lower(trim(p_email)), '');
  if v_base is null or v_base !~ '^[a-z]+(\.[a-z]+)+@baliuag\.sti\.edu\.ph$' then
    v_email := 'auto.professor.' || v_id::text || '@placeholder.baliuag.sti.edu.ph';
  else
    v_email := v_base;
    -- Two different professors can derive the same address; keep both
    -- rows distinct. (A suffixed address won't auto-link at sign-in.)
    while exists (select 1 from public.profiles where lower(email) = v_email) loop
      v_n := v_n + 1;
      v_email := regexp_replace(v_base, '@', v_n::text || '@');
    end loop;
  end if;

  -- auth.users.email stays null / is_anonymous true: see the original
  -- comments in add_scheduling_officer_role.sql (handle_new_auth_user skips
  -- anonymous rows, and the stub never authenticates).
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    v_id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    null, '', now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, true, now(), now()
  );

  insert into public.profiles (
    id, email, first_name, last_name, employee_id, role, status, created_at
  )
  values (
    v_id, v_email, p_full_name, '', p_employee_id, 'Teacher'::app_role, v_status, now()
  );

  return v_id;
end;
$$;

revoke all on function public.create_auto_professor_profile(text, text, boolean, text) from public;
grant execute on function public.create_auto_professor_profile(text, text, boolean, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. handle_new_auth_user — adopt a matching professor stub
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text;
  v_stub public.profiles%rowtype;
begin
  if new.is_anonymous or new.email is null then
    return new;
  end if;

  v_email := lower(trim(new.email));

  if v_email ~ '^[a-z]+(\.[a-z]+)*\.[0-9]{6}@baliuag\.sti\.edu\.ph$' then
    insert into public.profiles (id, email, first_name, last_name, role, status)
    values (new.id, v_email, '', '', 'Student'::app_role, 'approved')
    on conflict (id) do nothing;

    insert into public.registration_sync_events (event_type, profile_id, detail)
    values ('account_registered', new.id, 'Student account registered: ' || v_email);
  elsif v_email ~ '^[a-z]+(\.[a-z]+)+@baliuag\.sti\.edu\.ph$' then
    select * into v_stub
      from public.profiles
      where lower(email) = v_email
        and id <> new.id
        and role = 'Teacher'::app_role
        and status = 'approved'::approval_status
      limit 1;

    if found then
      update public.class_sections set professor_id = new.id where professor_id = v_stub.id;
      update public.class_assignments set professor_id = new.id where professor_id = v_stub.id;
      delete from public.profiles where id = v_stub.id;
      delete from auth.users where id = v_stub.id;

      insert into public.profiles (
        id, email, first_name, last_name, employee_id, role, status, is_active
      )
      values (
        new.id, v_email, v_stub.first_name, v_stub.last_name, v_stub.employee_id,
        'Teacher'::app_role, 'approved', v_stub.is_active
      )
      on conflict (id) do nothing;

      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('account_registered', new.id,
              'Professor account linked to imported schedule and auto-approved: ' || v_email);
    else
      insert into public.profiles (id, email, first_name, last_name, role, status)
      values (new.id, v_email, '', '', null, 'pending')
      on conflict (id) do nothing;

      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('account_registered', new.id, 'Staff account pending approval: ' || v_email);
    end if;
  else
    raise exception 'Sign-in rejected: % is not an authorized @baliuag.sti.edu.ph account.', new.email
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- 3. Backfill existing stubs (same derivation as professorEmailFor)
-- ---------------------------------------------------------------------------

do $$
declare
  r record;
  v_tokens text[];
  v_email text;
  v_name text;
begin
  for r in
    select id, first_name from public.profiles
    where email like 'auto.professor.%@placeholder.baliuag.sti.edu.ph'
      and status = 'approved'::approval_status
  loop
    v_name := trim(r.first_name);
    if position(',' in v_name) > 0 then
      v_name := trim(split_part(v_name, ',', 2)) || ' ' || trim(split_part(v_name, ',', 1));
    end if;
    select array_agg(t order by ord) into v_tokens
      from (
        select regexp_replace(lower(tok), '[^a-z]', '', 'g') as t, ord
        from regexp_split_to_table(replace(v_name, '.', ' '), '\s+') with ordinality as s(tok, ord)
        where lower(regexp_replace(tok, '\.', '', 'g')) not in
              ('mr','mrs','ms','dr','engr','prof','sir','madam')
      ) x
      where t <> '';
    continue when v_tokens is null or array_length(v_tokens, 1) < 2;
    v_email := v_tokens[1] || '.' || v_tokens[array_length(v_tokens, 1)] || '@baliuag.sti.edu.ph';
    if not exists (select 1 from public.profiles where lower(email) = v_email) then
      update public.profiles set email = v_email where id = r.id;
    end if;
  end loop;
end $$;
