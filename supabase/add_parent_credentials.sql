-- Parent credential login (embedded, demo-grade — see StaticDemoAccounts's own
-- doc comment for why this app runs on the `anon` session rather than a real
-- Supabase Auth session for most accounts).
--
-- Why this exists: batch enrollment (create_batch_guardian_account in
-- add_batch_enrollment_rpc.sql) creates a Parent `profiles` row from the
-- file's "Parent/s Email" column but gave that parent no way to sign in —
-- no password on the placeholder auth.users row, and a gmail address can't
-- claim it through the school's Microsoft sign-in. This adds:
--
--   * public.parent_credentials — one row per parent: email + bcrypt hash +
--     must_change flag. RLS on, NO policies, and all table privileges revoked
--     from anon/authenticated: the hash can only be touched by the RPCs below.
--   * issue_parent_credential(parent_id, reset) — mints a random temporary
--     password, stores only its hash, returns the plaintext ONCE to the
--     caller (the registrar's import result). Returns null when a credential
--     already exists and `reset` is false, so a re-uploaded batch file never
--     silently invalidates a password the guardian already changed.
--   * parent_login(email, password) — verifies the hash, returns the parent
--     plus the ids of the students linked to them via parent_student_links.
--   * parent_change_password(parent_id, old, new) — clears must_change.
--   * parent_session(parent_id) — lets the app restore a remembered sign-in
--     after a reload (and tells it whether a password change is still due).
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.parent_credentials (
  parent_id uuid primary key references public.profiles(id) on delete cascade,
  email text not null,
  password_hash text not null,
  must_change boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists parent_credentials_email_key
  on public.parent_credentials (lower(email));

alter table public.parent_credentials enable row level security;
revoke all on public.parent_credentials from anon, authenticated;

-- ---------------------------------------------------------------------------
-- issue_parent_credential
-- ---------------------------------------------------------------------------
create or replace function public.issue_parent_credential(
  p_parent_id uuid,
  p_reset boolean default false
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  -- No 0/O/1/l/I: the registrar reads this out or prints it for a guardian.
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  v_password text := '';
  v_email text;
  v_role text;
  i int;
begin
  if auth.role() = 'authenticated' and current_user_role() not in (
    'Registrar'::app_role, 'Admin'::app_role
  ) then
    raise exception 'Not authorized to issue a parent credential.';
  end if;

  select lower(trim(email)), role::text
    into v_email, v_role
    from public.profiles
   where id = p_parent_id;

  if v_role is null then
    raise exception 'No such parent profile.';
  end if;
  if v_role <> 'Parent' then
    raise exception 'Profile is not a Parent account.';
  end if;
  if v_email is null or v_email = '' then
    raise exception 'This parent has no email on file.';
  end if;

  if not p_reset and exists (
    select 1 from public.parent_credentials where parent_id = p_parent_id
  ) then
    return null;
  end if;

  for i in 1..10 loop
    v_password := v_password || substr(
      v_alphabet,
      1 + (get_byte(gen_random_bytes(1), 0) % length(v_alphabet)),
      1
    );
  end loop;

  insert into public.parent_credentials (parent_id, email, password_hash, must_change)
  values (p_parent_id, v_email, crypt(v_password, gen_salt('bf')), true)
  on conflict (parent_id) do update
    set email = excluded.email,
        password_hash = excluded.password_hash,
        must_change = true,
        updated_at = now();

  return v_password;
end;
$$;

revoke all on function public.issue_parent_credential(uuid, boolean) from public;
grant execute on function public.issue_parent_credential(uuid, boolean)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- parent_login
-- ---------------------------------------------------------------------------
create or replace function public.parent_login(
  p_email text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cred public.parent_credentials;
  v_name text;
  v_students jsonb;
begin
  select * into v_cred
    from public.parent_credentials
   where lower(email) = lower(trim(p_email));

  if not found then
    return null;
  end if;
  if v_cred.password_hash <> crypt(p_password, v_cred.password_hash) then
    return null;
  end if;

  -- A parent an Admin has switched off in Staff Accounts must not get in.
  if exists (
    select 1 from public.profiles
     where id = v_cred.parent_id and is_active = false
  ) then
    return jsonb_build_object('deactivated', true);
  end if;

  select nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), '')
    into v_name
    from public.profiles
   where id = v_cred.parent_id;

  select coalesce(jsonb_agg(student_id), '[]'::jsonb)
    into v_students
    from public.parent_student_links
   where parent_id = v_cred.parent_id;

  return jsonb_build_object(
    'parent_id', v_cred.parent_id,
    'display_name', coalesce(v_name, v_cred.email),
    'email', v_cred.email,
    'must_change', v_cred.must_change,
    'student_ids', v_students
  );
end;
$$;

revoke all on function public.parent_login(text, text) from public;
grant execute on function public.parent_login(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- parent_change_password
-- ---------------------------------------------------------------------------
create or replace function public.parent_change_password(
  p_parent_id uuid,
  p_old_password text,
  p_new_password text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
begin
  if p_new_password is null or length(p_new_password) < 8 then
    raise exception 'The new password must be at least 8 characters.';
  end if;
  if p_new_password = p_old_password then
    raise exception 'Choose a password different from the temporary one.';
  end if;

  select password_hash into v_hash
    from public.parent_credentials
   where parent_id = p_parent_id;

  if v_hash is null or v_hash <> crypt(p_old_password, v_hash) then
    return false;
  end if;

  update public.parent_credentials
     set password_hash = crypt(p_new_password, gen_salt('bf')),
         must_change = false,
         updated_at = now()
   where parent_id = p_parent_id;

  return true;
end;
$$;

revoke all on function public.parent_change_password(uuid, text, text) from public;
grant execute on function public.parent_change_password(uuid, text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- parent_session — restore after reload (only names a parent who has a
-- credential, so it can't be used to enumerate arbitrary profiles).
-- ---------------------------------------------------------------------------
create or replace function public.parent_session(p_parent_id uuid)
returns jsonb
language sql
security definer
set search_path = public, extensions
stable
as $$
  select jsonb_build_object(
    'parent_id', c.parent_id,
    'display_name', coalesce(
      nullif(trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
      c.email
    ),
    'email', c.email,
    'must_change', c.must_change,
    'active', coalesce(p.is_active, true)
  )
  from public.parent_credentials c
  join public.profiles p on p.id = c.parent_id
  where c.parent_id = p_parent_id;
$$;

revoke all on function public.parent_session(uuid) from public;
grant execute on function public.parent_session(uuid) to anon, authenticated;
