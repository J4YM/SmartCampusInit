-- Microsoft OAuth (Azure AD) email classification, staff approval queue, and
-- RFID card linking for @baliuag.sti.edu.ph accounts.
--
-- Run in Supabase SQL Editor.
--
-- *** WARNING — this installs an `AFTER INSERT ON auth.users` trigger ***
-- It runs on every new auth user, including Microsoft OAuth sign-ins AND the
-- anonymous sign-ins used by the existing RFID student-registration flow
-- (see `StudentsRepository.create()` in `lib/data/students_repository.dart`,
-- used by `packages/rfid_management_module`). A bad regex or an unhandled
-- edge case here can lock out all new sign-ins or silently break that
-- existing, already-working registration flow. Before relying on this in
-- production:
--   1. Apply it on a staging project first if you have one.
--   2. Test three cases with throwaway/test accounts: a student-pattern
--      email (e.g. cruz.204890@baliuag.sti.edu.ph), a staff-pattern email
--      (e.g. j.doe@baliuag.sti.edu.ph), and a non-matching email/domain.
--      The first two should succeed; the third should have its sign-in
--      rejected outright.
--   3. Confirm "Register Student" (via the RFID Management module, which
--      uses anonymous sign-in) still works after this is applied.

-- ---------------------------------------------------------------------------
-- 1. `profiles` schema additions
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.approval_status as enum ('pending', 'approved');
exception
  when duplicate_object then null;
end $$;

alter table public.profiles
  -- Existing rows (including ones created by the anonymous RFID flow, which
  -- never sets `status`) default to 'approved' so nothing already in the
  -- table is retroactively locked out.
  add column if not exists status public.approval_status not null default 'approved',
  -- Independent of `students.rfid_uid` (that column belongs to the separate,
  -- unaffected kiosk/registration flow). This one backs the new admin
  -- RFID-linking workflow and is usable by staff and student profiles alike.
  add column if not exists rfid_card_id text,
  -- `profiles` has no email column today and `auth.users` isn't queryable
  -- via PostgREST for `authenticated`/`anon` roles, so the admin UI needs
  -- its own copy to display/search by email.
  add column if not exists email text,
  add column if not exists created_at timestamptz not null default now();

do $$ begin
  alter table public.profiles add constraint profiles_rfid_card_id_key unique (rfid_card_id);
exception
  when duplicate_object then null;
end $$;

create unique index if not exists profiles_email_key
  on public.profiles (email) where email is not null;

-- Pending staff have no role yet (assigned by an admin at approval time).
alter table public.profiles alter column role drop not null;

-- Belt-and-braces: nothing should ever be marked approved without a role.
do $$ begin
  alter table public.profiles
    add constraint profiles_role_required_when_approved
    check (status <> 'approved' or role is not null);
exception
  when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Sign-up trigger: domain/pattern validation + role classification
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text;
begin
  -- Anonymous sign-ins (rfid_management_module / students_repository.dart)
  -- have no email and manage their own `profiles` row elsewhere — never
  -- touch them here, or student registration breaks.
  if new.is_anonymous or new.email is null then
    return new;
  end if;

  v_email := lower(trim(new.email));

  -- Student format: lastname (one or more dot-separated words) + dot +
  -- 6-digit student number, e.g. cruz.204890@baliuag.sti.edu.ph. Checked
  -- before the staff pattern since it's the more specific of the two —
  -- ending in digits is what distinguishes it from a staff account.
  if v_email ~ '^[a-z]+(\.[a-z]+)*\.[0-9]{6}@baliuag\.sti\.edu\.ph$' then
    insert into public.profiles (id, email, first_name, last_name, role, status)
    values (new.id, v_email, '', '', 'Student'::app_role, 'approved')
    on conflict (id) do nothing;
  elsif v_email ~ '^[a-z]+(\.[a-z]+)+@baliuag\.sti\.edu\.ph$' then
    insert into public.profiles (id, email, first_name, last_name, role, status)
    values (new.id, v_email, '', '', null, 'pending')
    on conflict (id) do nothing;
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
-- 3. Admin RPCs — approval + RFID linking
-- ---------------------------------------------------------------------------

-- Roles an admin may hand-assign to a pending staff sign-in. Student/Parent
-- are excluded — those are only ever set by the trigger above.
create or replace function public._assert_staff_assignable_role(p_role app_role)
returns void
language plpgsql
as $$
begin
  if p_role in ('Student'::app_role, 'Parent'::app_role) then
    raise exception 'Role % cannot be assigned via staff approval.', p_role;
  end if;
end;
$$;

create or replace function public.approve_staff_member(
  p_user_id uuid,
  p_role app_role,
  p_rfid_card_id text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may approve staff accounts.' using errcode = '42501';
  end if;

  perform public._assert_staff_assignable_role(p_role);

  update public.profiles
    set role = p_role,
        status = 'approved',
        rfid_card_id = coalesce(p_rfid_card_id, rfid_card_id)
    where id = p_user_id and status = 'pending';

  if not found then
    raise exception 'No pending profile found for %.', p_user_id;
  end if;
end;
$$;

-- p_approvals: jsonb array of {"user_id": "...", "role": "Teacher", "rfid_card_id": null}.
-- Per-row roles, not one shared role — each pending staffer likely needs a
-- different specific role. All-or-nothing (single function call = single
-- transaction).
create or replace function public.batch_approve_staff(p_approvals jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
  v_user_id uuid;
  v_role app_role;
  v_rfid text;
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may approve staff accounts.' using errcode = '42501';
  end if;

  for v_item in select * from jsonb_array_elements(p_approvals) loop
    v_user_id := (v_item ->> 'user_id')::uuid;
    v_role := (v_item ->> 'role')::app_role;
    v_rfid := v_item ->> 'rfid_card_id';

    perform public._assert_staff_assignable_role(v_role);

    update public.profiles
      set role = v_role,
          status = 'approved',
          rfid_card_id = coalesce(v_rfid, rfid_card_id)
      where id = v_user_id and status = 'pending';

    if not found then
      raise exception 'No pending profile found for %.', v_user_id;
    end if;
  end loop;
end;
$$;

-- Assigns ONE role to every currently-pending staff account. Only correct
-- when an admin has visually confirmed the whole batch genuinely shares a
-- role (e.g. onboarding one department) — the UI must show a confirmation
-- dialog before calling this with p_confirm := true; use batch_approve_staff
-- for the general (mixed-role) case.
create or replace function public.approve_all_pending_staff(
  p_role app_role,
  p_confirm boolean default false
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may approve staff accounts.' using errcode = '42501';
  end if;

  if not p_confirm then
    raise exception 'approve_all_pending_staff requires p_confirm = true.';
  end if;

  perform public._assert_staff_assignable_role(p_role);

  update public.profiles set role = p_role, status = 'approved'
    where status = 'pending';
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

-- Single action behind the RFID Mapping page's "Fast-Assign" form: always
-- links the card; if the target profile is still pending, also requires and
-- applies p_role to approve it in the same call.
create or replace function public.link_rfid_card(
  p_profile_id uuid,
  p_rfid_card_id text,
  p_role app_role default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status public.approval_status;
begin
  if current_user_role() <> 'Admin'::app_role then
    raise exception 'Only admins may link RFID cards.' using errcode = '42501';
  end if;

  select status into v_status from public.profiles where id = p_profile_id;
  if not found then
    raise exception 'No profile found for %.', p_profile_id;
  end if;

  if v_status = 'pending' then
    if p_role is null then
      raise exception 'A role must be selected to approve this pending profile.';
    end if;
    perform public._assert_staff_assignable_role(p_role);
    update public.profiles
      set rfid_card_id = p_rfid_card_id, role = p_role, status = 'approved'
      where id = p_profile_id;
  else
    update public.profiles
      set rfid_card_id = p_rfid_card_id
      where id = p_profile_id;
  end if;
end;
$$;

revoke all on function public.approve_staff_member(uuid, app_role, text) from public;
grant execute on function public.approve_staff_member(uuid, app_role, text) to authenticated;

revoke all on function public.batch_approve_staff(jsonb) from public;
grant execute on function public.batch_approve_staff(jsonb) to authenticated;

revoke all on function public.approve_all_pending_staff(app_role, boolean) from public;
grant execute on function public.approve_all_pending_staff(app_role, boolean) to authenticated;

revoke all on function public.link_rfid_card(uuid, text, app_role) from public;
grant execute on function public.link_rfid_card(uuid, text, app_role) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------
-- No new policies needed: `profiles_admin_manage_staff` (from
-- add_admin_dashboard_schema.sql) is `for all` with no column restriction,
-- so it already covers admin SELECT/UPDATE of the new `status`,
-- `rfid_card_id`, `email`, and `created_at` columns. Self-row-select (part
-- of the un-versioned base schema, since `first_name`/`last_name`/`role`
-- are already selectable by the signed-in user) likewise covers the new
-- columns automatically.
