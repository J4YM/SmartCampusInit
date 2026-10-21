-- Creates REAL staff accounts (email + password in Supabase Auth) next to the
-- built-in demo logins. Unlike a demo login, a real account has a Supabase
-- session, so the database knows who it is and the role checks / RLS apply.
--
--   Email                                   Role
--   demo.admin@baliuag.sti.edu.ph           Admin
--   demo.registrar@baliuag.sti.edu.ph       Registrar
--   demo.discipline@baliuag.sti.edu.ph      Discipline_Officer
--   demo.guidance@baliuag.sti.edu.ph        Guidance_Counselor
--   demo.teacher@baliuag.sti.edu.ph         Teacher
--   demo.security@baliuag.sti.edu.ph        Security
--   demo.ittech@baliuag.sti.edu.ph          IT_Technician
--   demo.scheduling@baliuag.sti.edu.ph      Scheduling_Officer
--
-- THIS IS A TEMPLATE. The passwords below are placeholders (__PW_...__). Do
-- not put real passwords in a committed file: copy this to
-- supabase/local/create_real_accounts.sql (that folder is git-ignored), replace
-- every __PW_...__ with the password you want, and run THAT file in the
-- Supabase SQL Editor. Passwords must be strong (12+ characters, upper and
-- lower case, a number and a symbol): the in-app "Update password" refuses
-- anything weaker.
--
-- Idempotent. Running it again resets each account's password to the value in
-- the file, which is also how an Admin resets a forgotten password:
--   edit the password in your local copy, run it again.
-- To change ONE password without this script:
--   update auth.users
--      set encrypted_password = crypt('NewStrong#Pass2026!', gen_salt('bf'))
--    where email = 'demo.discipline@baliuag.sti.edu.ph';
--
-- The addresses use the school's staff pattern (first.last@baliuag.sti.edu.ph)
-- because the sign-up trigger (handle_new_auth_user) rejects anything else.
-- They are not real mailboxes, so "forgot password" emails never arrive: reset
-- with the SQL above instead.
--
-- Run after add_oauth_role_approval_schema.sql. Needs the pgcrypto extension
-- (enabled below).

create extension if not exists pgcrypto with schema extensions;

do $$
declare
  acct record;
  v_id uuid;
begin
  for acct in
    select * from (values
      ('demo.admin@baliuag.sti.edu.ph',      '__PW_ADMIN__',      'Admin',              'Demo', 'Administrator'),
      ('demo.registrar@baliuag.sti.edu.ph',  '__PW_REGISTRAR__',  'Registrar',          'Demo', 'Registrar'),
      ('demo.discipline@baliuag.sti.edu.ph', '__PW_DISCIPLINE__', 'Discipline_Officer', 'Demo', 'Discipline Officer'),
      ('demo.guidance@baliuag.sti.edu.ph',   '__PW_GUIDANCE__',   'Guidance_Counselor', 'Demo', 'Guidance Counselor'),
      ('demo.teacher@baliuag.sti.edu.ph',    '__PW_TEACHER__',    'Teacher',            'Demo', 'Teacher'),
      ('demo.security@baliuag.sti.edu.ph',   '__PW_SECURITY__',   'Security',           'Demo', 'Security'),
      ('demo.ittech@baliuag.sti.edu.ph',     '__PW_ITTECH__',     'IT_Technician',      'Demo', 'IT Technician'),
      ('demo.scheduling@baliuag.sti.edu.ph', '__PW_SCHEDULING__', 'Scheduling_Officer', 'Demo', 'Scheduling Officer')
    ) as t(email, pw, role_name, first_name, last_name)
  loop
    if acct.pw like '\_\_PW\_%' then
      raise exception 'Replace the placeholder password for % before running this script.', acct.email;
    end if;

    select id into v_id from auth.users where lower(email) = acct.email;

    if v_id is null then
      v_id := gen_random_uuid();

      -- The token columns must be '' (not null) or Supabase Auth fails the
      -- first sign-in with "Database error querying schema".
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new,
        email_change, email_change_token_current, reauthentication_token,
        phone_change, phone_change_token
      )
      values (
        '00000000-0000-0000-0000-000000000000', v_id, 'authenticated',
        'authenticated', acct.email,
        extensions.crypt(acct.pw, extensions.gen_salt('bf')),
        now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        now(), now(),
        '', '', '', '', '', '', '', ''
      );

      insert into auth.identities (
        id, user_id, identity_data, provider, provider_id,
        last_sign_in_at, created_at, updated_at
      )
      values (
        gen_random_uuid(), v_id,
        jsonb_build_object('sub', v_id::text, 'email', acct.email,
                           'email_verified', true, 'phone_verified', false),
        'email', v_id::text, now(), now(), now()
      );
    else
      -- Already there: this run resets its password to the file's value.
      update auth.users
         set encrypted_password = extensions.crypt(acct.pw, extensions.gen_salt('bf')),
             email_confirmed_at = coalesce(email_confirmed_at, now()),
             updated_at = now()
       where id = v_id;
    end if;

    -- The sign-up trigger just made a pending profile with no role; make it
    -- an approved, active one with the right role.
    insert into public.profiles
      (id, email, first_name, last_name, role, status, is_active)
    values
      (v_id, acct.email, acct.first_name, acct.last_name,
       acct.role_name::public.app_role, 'approved', true)
    on conflict (id) do update
      set email = excluded.email,
          first_name = excluded.first_name,
          last_name = excluded.last_name,
          role = excluded.role,
          status = 'approved',
          is_active = true;
  end loop;
end $$;

-- Check: every row should show the right role, approved, active.
select email, role, status, is_active
  from public.profiles
 where email like 'demo.%@baliuag.sti.edu.ph'
 order by email;
