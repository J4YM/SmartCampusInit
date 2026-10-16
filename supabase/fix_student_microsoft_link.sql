-- Fix: a batch-enrolled student's first Microsoft sign-in failed with
-- "Sign-in rejected: only accounts from STI College Baliuag Branch can be used".
--
-- Cause: the Registrar's batch upload (create_batch_student_account) gives the
-- student a placeholder profile that already holds their school email
-- (e.g. ventura.338958@baliuag.sti.edu.ph) and their students row. Signing in
-- with Microsoft creates a BRAND-NEW auth.users row, and handle_new_auth_user
-- then tried to insert a second profile with the same email. profiles.email is
-- unique, so that insert failed and Supabase reported the generic
-- "Database error saving new user" the app turns into the message above.
--
-- Fix: when a student-pattern email signs in for the first time and a
-- placeholder (anonymous / system-created) student already exists for that
-- email or student number, MOVE the placeholder onto the new Microsoft account:
-- the profile, the students row, and every row anywhere in public that points
-- at the old id (enrollments, grades, attendance, violations, GPA records,
-- parent links, ...). The student is therefore tied to their Microsoft login the
-- moment they first sign in, with the enrolled information already attached —
-- no registration form. If nothing matches, the original behaviour is kept.
--
-- Run in Supabase SQL Editor after add_professor_identity_override.sql.
-- Idempotent.

-- ---------------------------------------------------------------------------
-- 1. Move a placeholder student onto a real login.
-- ---------------------------------------------------------------------------
create or replace function public._rehome_student(p_old uuid, p_new uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  op public.profiles;
  os public.students;
  pcols text;
  scols text;
  fk record;
begin
  select * into op from public.profiles where id = p_old;
  select * into os from public.students where id = p_old;
  if op.id is null or os.id is null then
    raise exception 'No placeholder student record for %', p_old;
  end if;

  -- Free the unique values (email, RFID card, student number) the copy needs.
  update public.profiles set email = null, rfid_card_id = null where id = p_old;
  update public.students
     set student_number = student_number || '#old', rfid_uid = null
   where id = p_old;

  -- Copy every real (non-generated) column onto the new id.
  select string_agg(quote_ident(attname), ',' order by attnum) into pcols
    from pg_attribute
   where attrelid = 'public.profiles'::regclass
     and attnum > 0 and not attisdropped and attgenerated = '';
  select string_agg(quote_ident(attname), ',' order by attnum) into scols
    from pg_attribute
   where attrelid = 'public.students'::regclass
     and attnum > 0 and not attisdropped and attgenerated = '';

  execute format(
    'insert into public.profiles (%1$s) select %1$s from jsonb_populate_record(null::public.profiles, $1)',
    pcols
  ) using to_jsonb(op) || jsonb_build_object('id', p_new, 'email', p_email);

  execute format(
    'insert into public.students (%1$s) select %1$s from jsonb_populate_record(null::public.students, $1)',
    scols
  ) using to_jsonb(os) || jsonb_build_object('id', p_new);

  -- Re-point every single-column foreign key that references the old student
  -- or profile id (children first, before the old rows are removed).
  for fk in
    select c.conrelid::regclass as tbl, a.attname as col
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f'
       and array_length(c.conkey, 1) = 1
       and c.confrelid in ('public.students'::regclass, 'public.profiles'::regclass)
       and c.conrelid not in ('public.students'::regclass, 'public.profiles'::regclass)
       and c.connamespace = 'public'::regnamespace
  loop
    execute format('update %s set %I = $1 where %I = $2', fk.tbl, fk.col, fk.col)
      using p_new, p_old;
  end loop;

  delete from public.students where id = p_old;
  delete from public.profiles where id = p_old;
  delete from auth.users where id = p_old;
end;
$$;

revoke all on function public._rehome_student(uuid, uuid, text) from public;

-- ---------------------------------------------------------------------------
-- 2. Sign-in trigger: link a pre-enrolled student instead of colliding with them.
--    Identical to the version in add_professor_identity_override.sql except for
--    the student branch.
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
  v_old uuid;
  v_linked boolean := false;
begin
  if new.is_anonymous or new.email is null then
    return new;
  end if;

  v_email := lower(trim(new.email));

  if v_email ~ '^[a-z]+(\.[a-z]+)*\.[0-9]{6}@baliuag\.sti\.edu\.ph$' then
    -- A student the Registrar already enrolled (batch upload / Add New Student /
    -- RFID pre-registration): a placeholder profile with this email, or with this
    -- student number, owned by an anonymous / system-created auth user.
    select p.id into v_old
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.id <> new.id
       and p.role = 'Student'::app_role
       and coalesce(u.is_anonymous, false)
       and lower(p.email) = v_email
     limit 1;

    if v_old is null then
      select s.id into v_old
        from public.students s
        join auth.users u on u.id = s.id
       where s.id <> new.id
         and coalesce(u.is_anonymous, false)
         and s.student_number = public._student_number_from_email(v_email)
       limit 1;
    end if;

    if v_old is not null then
      begin
        perform public._rehome_student(v_old, new.id, v_email);
        v_linked := true;
      exception when others then
        -- Sub-transaction: every partial change above is rolled back.
        raise warning 'Could not link enrolled student % to %: %', v_old, v_email, sqlerrm;
      end;
    end if;

    if v_linked then
      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('account_registered', new.id, 'Enrolled student linked to Microsoft account: ' || v_email);
    else
      begin
        insert into public.profiles (id, email, first_name, last_name, role, status)
        values (new.id, v_email, '', '', 'Student'::app_role, 'approved')
        on conflict (id) do nothing;
      exception when unique_violation then
        -- The email is held by a record that could not be linked: still let
        -- the sign-in through (the app will say the student is not enrolled).
        insert into public.profiles (id, email, first_name, last_name, role, status)
        values (new.id, null, '', '', 'Student'::app_role, 'approved')
        on conflict (id) do nothing;
      end;

      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('account_registered', new.id, 'Student account registered: ' || v_email);
    end if;
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
-- 3. Already tried and failed? Nothing to clean up: the failed sign-in rolled
--    back, so no half-created account exists. Just sign in again after this runs.
-- ---------------------------------------------------------------------------
