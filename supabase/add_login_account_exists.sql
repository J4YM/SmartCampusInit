-- login_account_exists: does a sign-in name belong to an account?
--
-- The login lockout (add_login_lockout.sql) should only count failed passwords
-- for accounts that exist. Typing a name that belongs to nobody (a typo, a
-- stranger guessing) must not lock the session out for 15 minutes. The app asks
-- this before it counts a failure.
--
-- It matches an email against real accounts (profiles.email: staff, students,
-- Microsoft sign-ins) and guardian logins (parent_credentials.email). The
-- built-in demo usernames are known to the app itself and are not checked here.
--
-- Trade-off to be aware of: because an unknown name is never counted, how the
-- lockout behaves reveals whether an email has an account. The sign-in error
-- message itself is identical either way.
--
-- Callable before sign-in (anon), so it returns only a boolean.
-- Run in Supabase SQL Editor. Idempotent.

create or replace function public.login_account_exists(p_username text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_name text := lower(left(btrim(coalesce(p_username, '')), 100));
begin
  if v_name = '' then
    return false;
  end if;

  if exists (select 1 from public.profiles where lower(email) = v_name) then
    return true;
  end if;

  if to_regclass('public.parent_credentials') is not null
     and exists (select 1 from public.parent_credentials
                  where lower(email) = v_name) then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.login_account_exists(text) from public;
grant execute on function public.login_account_exists(text) to anon, authenticated;
