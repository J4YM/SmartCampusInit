-- Professor identity vs. login email: ONE professor record per real person,
-- and the Microsoft login email is attached by a human (Registrar/Admin),
-- never guessed from an uploaded name.
--
-- Why: Course/Professor uploads carry names in inconsistent order
-- ("First Last MI" vs "Last First MI"), so any email derived from the name
-- is unreliable. add_professor_email_and_linking.sql derived one anyway and
-- auto-approved a Teacher on a matching sign-in; a wrong guess either
-- stranded the real login as an unlinked pending account or, worse, matched
-- the wrong person. This file replaces that with an explicit override:
--
--   * A professor stub is created from the upload with NO usable email (a
--     placeholder address only) and a `name_key` (order-insensitive:
--     "Paulino Kar-El M" and "Kar-El Paulino" share a key) so repeated
--     uploads find the same record.
--   * connect_professor_email(): Registrar/Admin set the professor's login
--     email. If that person already signed in, they are linked at once;
--     otherwise it is stored and the first sign-in with exactly that
--     address links automatically (a human typed it, so that is safe).
--   * link_login_to_professor(): link an existing pending login to a
--     professor record from the Staff Accounts page.
--   * merge_professors(): fold a duplicate record into another.
--   * handle_new_auth_user no longer matches a stub by guessed email — only
--     by `claimed_email`.
--
-- Run in Supabase SQL Editor after add_professor_email_and_linking.sql and
-- add_registration_sync_log_schema.sql. Idempotent.

alter table public.profiles
  add column if not exists name_key text,
  add column if not exists claimed_email text;

create unique index if not exists profiles_claimed_email_key
  on public.profiles (lower(claimed_email)) where claimed_email is not null;

-- ---------------------------------------------------------------------------
-- 1. Order-insensitive name key (mirrors professorNameKey() in
--    lib/data/schedule_import_repository.dart)
-- ---------------------------------------------------------------------------
create or replace function public.professor_name_key(p_name text)
returns text
language sql
immutable
as $$
  select coalesce(string_agg(t, ' ' order by t), '')
  from (
    select regexp_replace(lower(tok), '[^a-z0-9]', '', 'g') as t
    from regexp_split_to_table(
           regexp_replace(coalesce(p_name, ''), '[.,]', ' ', 'g'), '\s+') as tok
    where regexp_replace(lower(tok), '[^a-z]', '', 'g')
          not in ('mr', 'mrs', 'ms', 'dr', 'engr', 'prof', 'sir', 'madam')
  ) x
  where length(t) > 1;
$$;

-- A "stub" is a system-created professor record (anonymous placeholder auth
-- user); a real Microsoft login is never anonymous.
create or replace function public._is_professor_stub(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.id = p_id
       and u.is_anonymous
       and p.role = 'Teacher'::app_role
  );
$$;

create or replace function public._assert_professor_admin()
returns void
language plpgsql
as $$
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Only the Registrar or Admin can manage professor accounts.'
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Backfill: name keys, and take back any email that was guessed
-- ---------------------------------------------------------------------------
update public.profiles p
   set name_key = public.professor_name_key(
         btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')))
 where role = 'Teacher'::app_role and name_key is null;

update public.profiles p
   set email = 'auto.professor.' || p.id::text || '@placeholder.baliuag.sti.edu.ph'
 where p.role = 'Teacher'::app_role
   and public._is_professor_stub(p.id)
   and p.email not like 'auto.professor.%@placeholder.baliuag.sti.edu.ph';

-- ---------------------------------------------------------------------------
-- 3. Stub creation: placeholder email only, plus the name key
-- ---------------------------------------------------------------------------
drop function if exists public.create_auto_professor_profile(text, text, boolean, text);
drop function if exists public.create_auto_professor_profile(text, text, boolean);

create or replace function public.create_auto_professor_profile(
  p_employee_id text,
  p_full_name text,
  p_is_placeholder boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
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
    id, email, first_name, last_name, employee_id, role, status, name_key, created_at
  )
  values (
    v_id,
    'auto.professor.' || v_id::text || '@placeholder.baliuag.sti.edu.ph',
    p_full_name, '', p_employee_id, 'Teacher'::app_role, v_status,
    public.professor_name_key(p_full_name), now()
  );

  return v_id;
end;
$$;

revoke all on function public.create_auto_professor_profile(text, text, boolean) from public;
grant execute on function public.create_auto_professor_profile(text, text, boolean)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Merge helper: move everything from a stub onto a real login/record
-- ---------------------------------------------------------------------------
create or replace function public._merge_professor_into(p_stub uuid, p_target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.profiles;
begin
  select * into s from public.profiles where id = p_stub;
  if not found or p_stub = p_target then
    return;
  end if;

  update public.class_sections set professor_id = p_target where professor_id = p_stub;
  update public.class_assignments set professor_id = p_target where professor_id = p_stub;

  -- Remove the stub BEFORE copying its details: profiles.employee_id is
  -- unique, so setting the target's employee_id while the stub still holds
  -- the same value raises profiles_employee_id_key. `s` already has a copy.
  delete from public.profiles where id = p_stub;
  delete from auth.users where id = p_stub;

  update public.profiles t
     set employee_id = coalesce(t.employee_id, s.employee_id),
         first_name = case when coalesce(btrim(t.first_name), '') = '' then s.first_name else t.first_name end,
         last_name = case when coalesce(btrim(t.first_name), '') = '' then s.last_name else t.last_name end,
         name_key = coalesce(t.name_key, s.name_key),
         is_active = coalesce(t.is_active, s.is_active)
   where t.id = p_target;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. connect_professor_email — the override
-- ---------------------------------------------------------------------------
create or replace function public.connect_professor_email(
  p_professor_id uuid,
  p_email text,
  p_actor_name text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_login public.profiles;
begin
  perform public._assert_professor_admin();

  if not public._is_professor_stub(p_professor_id) then
    raise exception 'That professor already has a login; change it from Staff Accounts.';
  end if;

  if v_email = '' then
    update public.profiles set claimed_email = null where id = p_professor_id;
    return 'cleared';
  end if;

  if v_email !~ '^[a-z]+(\.[a-z]+)+@baliuag\.sti\.edu\.ph$' then
    raise exception '% is not a valid staff address (firstname.lastname@baliuag.sti.edu.ph).', v_email;
  end if;

  if exists (select 1 from public.profiles
              where lower(claimed_email) = v_email and id <> p_professor_id) then
    raise exception '% is already connected to another professor.', v_email;
  end if;

  select p.* into v_login
    from public.profiles p
    join auth.users u on u.id = p.id
   where lower(p.email) = v_email and not u.is_anonymous and p.id <> p_professor_id
   limit 1;

  if found then
    if v_login.status <> 'pending'::approval_status
       and v_login.role is distinct from 'Teacher'::app_role then
      raise exception '% already belongs to a % account.', v_email, coalesce(v_login.role::text, 'staff');
    end if;
    update public.profiles
       set role = 'Teacher'::app_role, status = 'approved'::approval_status
     where id = v_login.id;
    perform public._merge_professor_into(p_professor_id, v_login.id);
    return 'linked';
  end if;

  update public.profiles set claimed_email = v_email where id = p_professor_id;
  return 'stored';
end;
$$;

revoke all on function public.connect_professor_email(uuid, text, text) from public;
grant execute on function public.connect_professor_email(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. link_login_to_professor — attach an existing pending login
-- ---------------------------------------------------------------------------
create or replace function public.link_login_to_professor(
  p_login_id uuid,
  p_professor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_login public.profiles;
begin
  perform public._assert_professor_admin();

  select * into v_login from public.profiles where id = p_login_id;
  if not found or v_login.status <> 'pending'::approval_status then
    raise exception 'That sign-in is not waiting for approval.';
  end if;
  if not public._is_professor_stub(p_professor_id) then
    raise exception 'Choose a professor record that has no login yet.';
  end if;

  update public.profiles
     set role = 'Teacher'::app_role, status = 'approved'::approval_status
   where id = p_login_id;
  perform public._merge_professor_into(p_professor_id, p_login_id);
end;
$$;

revoke all on function public.link_login_to_professor(uuid, uuid) from public;
grant execute on function public.link_login_to_professor(uuid, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. merge_professors — fold a duplicate record into another
-- ---------------------------------------------------------------------------
create or replace function public.merge_professors(p_keep uuid, p_remove uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed text;
begin
  perform public._assert_professor_admin();
  if p_keep = p_remove then
    raise exception 'Choose two different professor records.';
  end if;
  if not public._is_professor_stub(p_remove) then
    raise exception 'Only a record without a login can be merged away.';
  end if;

  -- Keep any email already connected to the record being removed (cleared
  -- on it first so the unique index on claimed_email is never violated).
  select claimed_email into v_claimed from public.profiles where id = p_remove;
  update public.profiles set claimed_email = null where id = p_remove;
  if v_claimed is not null then
    update public.profiles
       set claimed_email = v_claimed
     where id = p_keep and claimed_email is null;
  end if;
  perform public._merge_professor_into(p_remove, p_keep);
end;
$$;

revoke all on function public.merge_professors(uuid, uuid) from public;
grant execute on function public.merge_professors(uuid, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Listing for the override screens
-- ---------------------------------------------------------------------------
create or replace function public.list_professor_links()
returns table (
  kind text,            -- 'professor' | 'pending_login'
  id uuid,
  full_name text,
  employee_id text,
  email text,           -- real login email (null for a stub)
  claimed_email text,   -- email a human connected, not yet signed in
  is_stub boolean,
  name_key text,
  class_count int
)
language sql
stable
security definer
set search_path = public
as $$
  select 'professor'::text, p.id,
         btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
         p.employee_id,
         case when public._is_professor_stub(p.id) then null else p.email end,
         p.claimed_email,
         public._is_professor_stub(p.id),
         p.name_key,
         (select count(*)::int from public.class_sections c where c.professor_id = p.id)
    from public.profiles p
   where p.role = 'Teacher'::app_role
     and p.status in ('approved'::approval_status, 'Placeholder'::approval_status)
  union all
  select 'pending_login'::text, p.id,
         btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
         p.employee_id, p.email, null, false, null, 0
    from public.profiles p
   where p.status = 'pending'::approval_status;
$$;

revoke all on function public.list_professor_links() from public;
grant execute on function public.list_professor_links() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Sign-in trigger: link ONLY by an explicitly connected email
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text;
  v_stub public.profiles;
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
     where lower(claimed_email) = v_email
       and id <> new.id
       and public._is_professor_stub(id)
     limit 1;

    if found then
      insert into public.profiles (
        id, email, first_name, last_name, employee_id, role, status, is_active, name_key
      )
      values (
        -- employee_id is left null here and filled by the merge below,
        -- after the stub (which still holds it) is gone — it is unique.
        new.id, v_email, v_stub.first_name, v_stub.last_name, null,
        'Teacher'::app_role, 'approved', v_stub.is_active, v_stub.name_key
      )
      on conflict (id) do nothing;

      update public.profiles set claimed_email = null where id = v_stub.id;
      perform public._merge_professor_into(v_stub.id, new.id);

      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('account_registered', new.id,
              'Professor account linked to connected email: ' || v_email);
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
-- 10. Change / remove the login tied to a professor
-- ---------------------------------------------------------------------------
-- Once a professor is linked to a real Microsoft login, connect_professor_email
-- no longer applies (that record is not a stub any more). Unlinking turns the
-- professor back into a stub that carries their name, Employee ID and every
-- class, and sends the old login back to "waiting for approval" so it can be
-- linked elsewhere or left alone.
create or replace function public._unlink_professor_login(p_professor_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  old public.profiles;
  v_stub uuid := gen_random_uuid();
begin
  select * into old from public.profiles where id = p_professor_id;
  if not found or old.role is distinct from 'Teacher'::app_role then
    raise exception 'That is not a professor account.';
  end if;
  if public._is_professor_stub(p_professor_id) then
    return p_professor_id;
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at
  )
  values (
    v_stub, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
    null, '', now(),
    '{"provider":"system","providers":["system"]}'::jsonb, '{}'::jsonb, true, now(), now()
  );

  -- employee_id is unique: free it on the old login before the stub takes it.
  update public.profiles
     set employee_id = null, role = null, status = 'pending'::approval_status
   where id = p_professor_id;

  insert into public.profiles (
    id, email, first_name, last_name, employee_id, role, status, is_active,
    name_key, created_at
  )
  values (
    v_stub,
    'auto.professor.' || v_stub::text || '@placeholder.baliuag.sti.edu.ph',
    old.first_name, old.last_name, old.employee_id, 'Teacher'::app_role,
    'approved'::approval_status, old.is_active,
    coalesce(old.name_key, public.professor_name_key(
      btrim(coalesce(old.first_name, '') || ' ' || coalesce(old.last_name, '')))),
    now()
  );

  update public.class_sections set professor_id = v_stub where professor_id = p_professor_id;
  update public.class_assignments set professor_id = v_stub where professor_id = p_professor_id;

  return v_stub;
end;
$$;

-- One entry point for the UI, for a stub or an already-linked professor:
--   * empty email  -> unlink (a stub with no email stays as is)
--   * same email   -> unchanged
--   * otherwise    -> unlink if needed, then connect the new email
-- Everything is one transaction, so an invalid or taken email leaves the
-- professor exactly as they were.
create or replace function public.change_professor_email(
  p_professor_id uuid,
  p_email text,
  p_actor_name text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_current text;
  v_target uuid := p_professor_id;
  v_result text;
begin
  perform public._assert_professor_admin();

  if public._is_professor_stub(p_professor_id) then
    return public.connect_professor_email(p_professor_id, v_email, p_actor_name);
  end if;

  select lower(email) into v_current from public.profiles where id = p_professor_id;
  if v_email = coalesce(v_current, '') then
    return 'unchanged';
  end if;

  v_target := public._unlink_professor_login(p_professor_id);
  if v_email = '' then
    return 'unlinked';
  end if;

  v_result := public.connect_professor_email(v_target, v_email, p_actor_name);
  return v_result;
end;
$$;

revoke all on function public._unlink_professor_login(uuid) from public;
revoke all on function public.change_professor_email(uuid, text, text) from public;
grant execute on function public.change_professor_email(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 11. One-click cleanup of exact duplicate professor records
-- ---------------------------------------------------------------------------
-- Records created before the name key existed ("Mr. Kar-El Paulino" vs
-- "PAULINO KAR-EL, M") share a name_key now. This folds the placeholder
-- records of each such group into one:
--   * keeper = a real login if the group has one, else the record with an
--     Employee ID, else the one with the most classes, else the oldest;
--   * only records WITHOUT a login are merged away (two real logins with the
--     same name are never merged);
--   * keys with a single word, and placeholder positions ("New IT Faculty"),
--     are left for a manual merge.
-- p_dry_run = true only counts how many records would be merged.
create or replace function public.merge_duplicate_professors(p_dry_run boolean default false)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  g record;
  r record;
  v_keeper uuid;
  v_claimed text;
  v_count int := 0;
begin
  perform public._assert_professor_admin();

  for g in
    select name_key
      from public.profiles
     where role = 'Teacher'::app_role
       and status = 'approved'::approval_status
       and name_key is not null
       and position(' ' in name_key) > 0
     group by name_key
    having count(*) > 1
  loop
    select p.id into v_keeper
      from public.profiles p
     where p.role = 'Teacher'::app_role
       and p.status = 'approved'::approval_status
       and p.name_key = g.name_key
     order by (not public._is_professor_stub(p.id)) desc,
              (p.employee_id is not null) desc,
              (select count(*) from public.class_sections c where c.professor_id = p.id) desc,
              p.created_at asc
     limit 1;

    for r in
      select p.id
        from public.profiles p
       where p.role = 'Teacher'::app_role
         and p.status = 'approved'::approval_status
         and p.name_key = g.name_key
         and p.id <> v_keeper
         and public._is_professor_stub(p.id)
    loop
      v_count := v_count + 1;
      if not p_dry_run then
        select claimed_email into v_claimed from public.profiles where id = r.id;
        update public.profiles set claimed_email = null where id = r.id;
        if v_claimed is not null then
          update public.profiles
             set claimed_email = v_claimed
           where id = v_keeper and claimed_email is null;
        end if;
        perform public._merge_professor_into(r.id, v_keeper);
      end if;
    end loop;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.merge_duplicate_professors(boolean) from public;
grant execute on function public.merge_duplicate_professors(boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 12. The Instructor ID is the strongest identity signal
-- ---------------------------------------------------------------------------
-- The Classes+Professor upload carries an Instructor ID per professor (CFL and
-- Room Schedule files carry names only). A professor first met by NAME has no
-- Employee ID; when the same person later arrives WITH an ID, the importer
-- calls this to settle who they are:
--   * nobody else holds that ID  -> record it on this professor;
--   * another record holds it    -> by the ID they are the same person, so
--     the name-only stub is merged into the record that has the ID (or, if
--     this one is a real login and the other a stub, the stub is merged into
--     the login);
--   * both are real logins       -> left alone.
-- Returns the id of the professor record that should be used from now on.
create or replace function public.adopt_professor_employee_id(
  p_professor_id uuid,
  p_employee_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := nullif(btrim(coalesce(p_employee_id, '')), '');
  v_other uuid;
  v_claimed text;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Scheduling_Officer'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to update a professor record.';
  end if;

  if v_id is null then
    return p_professor_id;
  end if;

  select id into v_other
    from public.profiles
   where employee_id = v_id and id <> p_professor_id
   limit 1;

  if v_other is null then
    update public.profiles
       set employee_id = v_id
     where id = p_professor_id and employee_id is null;
    return p_professor_id;
  end if;

  -- Someone else already holds this ID.
  if public._is_professor_stub(p_professor_id) then
    select claimed_email into v_claimed from public.profiles where id = p_professor_id;
    update public.profiles set claimed_email = null where id = p_professor_id;
    if v_claimed is not null then
      update public.profiles set claimed_email = v_claimed
       where id = v_other and claimed_email is null;
    end if;
    perform public._merge_professor_into(p_professor_id, v_other);
    return v_other;
  elsif public._is_professor_stub(v_other) then
    select claimed_email into v_claimed from public.profiles where id = v_other;
    update public.profiles set claimed_email = null where id = v_other;
    if v_claimed is not null then
      update public.profiles set claimed_email = v_claimed
       where id = p_professor_id and claimed_email is null;
    end if;
    perform public._merge_professor_into(v_other, p_professor_id);
    return p_professor_id;
  end if;

  return p_professor_id;
end;
$$;

revoke all on function public.adopt_professor_employee_id(uuid, text) from public;
grant execute on function public.adopt_professor_employee_id(uuid, text) to anon, authenticated;
