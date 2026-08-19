-- "Register Syncs" page (Admin Dashboard > System Configuration) — the
-- latest history of account registrations, RFID card assignments, and
-- pre-registered-record claims. None of that was logged anywhere before, so
-- this adds a small event table and re-declares (`create or replace`, safe
-- to rerun) the five existing functions that perform these actions —
-- `handle_new_auth_user` (add_oauth_role_approval_schema.sql),
-- `approve_staff_member` / `batch_approve_staff` / `link_rfid_card` (same
-- file), and `complete_student_registration` / `claim_preregistered_student`
-- (add_student_self_registration_schema.sql) — with one added insert each.
-- Every other line of each function body is unchanged from those files.
--
-- Run in Supabase SQL Editor, after add_oauth_role_approval_schema.sql and
-- add_student_self_registration_schema.sql.

-- ---------------------------------------------------------------------------
-- 1. Event log table
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.registration_sync_event_type as enum (
    'account_registered',
    'rfid_assigned',
    'record_claimed'
  );
exception
  when duplicate_object then null;
end $$;

create table if not exists public.registration_sync_events (
  id uuid primary key default gen_random_uuid(),
  event_type public.registration_sync_event_type not null,
  -- Nullable + on delete set null: claiming a pre-registered record deletes
  -- the old profile row outright (see claim_preregistered_student below),
  -- so this can't be a hard reference kept alive forever. `detail` is
  -- denormalized precisely so the history stays readable even then.
  profile_id uuid references public.profiles(id) on delete set null,
  detail text not null,
  occurred_at timestamptz not null default now()
);

create index if not exists registration_sync_events_occurred_at_idx
  on public.registration_sync_events (occurred_at desc);

alter table public.registration_sync_events enable row level security;

drop policy if exists "registration_sync_events_admin_select" on public.registration_sync_events;
create policy "registration_sync_events_admin_select"
  on public.registration_sync_events
  for select
  to authenticated
  using (current_user_role() = 'Admin'::app_role);

-- Demo-mode anon read, same tradeoff as rls_discipline_demo_anon.sql (the
-- static demo admin account has no Supabase JWT).
drop policy if exists "registration_sync_events_anon_select" on public.registration_sync_events;
create policy "registration_sync_events_anon_select"
  on public.registration_sync_events
  for select
  to anon
  using (true);

-- No insert/update/delete policy for anon/authenticated: every row is
-- written from inside the `security definer` functions below, which run
-- with the function owner's privileges and so aren't blocked by RLS here —
-- same as those functions' existing `update public.profiles ...` calls.

-- ---------------------------------------------------------------------------
-- 2. handle_new_auth_user — logs 'account_registered' for every new profile
--    (both the auto-approved Student branch and the pending-staff branch).
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
    insert into public.profiles (id, email, first_name, last_name, role, status)
    values (new.id, v_email, '', '', null, 'pending')
    on conflict (id) do nothing;

    insert into public.registration_sync_events (event_type, profile_id, detail)
    values ('account_registered', new.id, 'Staff account pending approval: ' || v_email);
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
-- 3. approve_staff_member / batch_approve_staff — log 'rfid_assigned' only
--    when an RFID card is actually supplied as part of the approval.
-- ---------------------------------------------------------------------------

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

  if p_rfid_card_id is not null then
    insert into public.registration_sync_events (event_type, profile_id, detail)
    values ('rfid_assigned', p_user_id, 'RFID card ' || p_rfid_card_id || ' assigned during staff approval');
  end if;
end;
$$;

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

    if v_rfid is not null then
      insert into public.registration_sync_events (event_type, profile_id, detail)
      values ('rfid_assigned', v_user_id, 'RFID card ' || v_rfid || ' assigned during staff approval');
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. link_rfid_card — always logs 'rfid_assigned' (that's this RPC's whole
--    purpose, behind the RFID Mapping page's "Fast-Assign" form).
-- ---------------------------------------------------------------------------

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

  insert into public.registration_sync_events (event_type, profile_id, detail)
  values ('rfid_assigned', p_profile_id, 'RFID card ' || p_rfid_card_id || ' linked via RFID Mapping');
end;
$$;

revoke all on function public.approve_staff_member(uuid, app_role, text) from public;
grant execute on function public.approve_staff_member(uuid, app_role, text) to authenticated;

revoke all on function public.batch_approve_staff(jsonb) from public;
grant execute on function public.batch_approve_staff(jsonb) to authenticated;

revoke all on function public.link_rfid_card(uuid, text, app_role) from public;
grant execute on function public.link_rfid_card(uuid, text, app_role) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. complete_student_registration — logs 'account_registered' once the
--    student fills in course/year/section (distinct milestone from the
--    trigger's initial auth-account-created event above).
-- ---------------------------------------------------------------------------

create or replace function public.complete_student_registration(
  p_first_name text,
  p_middle_initial text,
  p_last_name text,
  p_course text,
  p_year_level int,
  p_section_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_email text;
  v_role public.app_role;
  v_student_number text;
  v_composed_first text;
begin
  if v_caller is null then
    raise exception 'Not authenticated.';
  end if;

  select email, role into v_email, v_role
    from public.profiles where id = v_caller;

  if v_role is distinct from 'Student'::public.app_role then
    raise exception 'Only student accounts can self-register.';
  end if;

  if exists (select 1 from public.students where id = v_caller) then
    raise exception 'This account already has a linked student record.';
  end if;

  v_student_number := public._student_number_from_email(v_email);
  if v_student_number is null then
    raise exception 'Could not determine a student number from %.', v_email;
  end if;

  if exists (select 1 from public.students where student_number = v_student_number) then
    raise exception 'Student number % is already registered. Use "Claim my record" instead.', v_student_number
      using errcode = 'P0002';
  end if;

  if not exists (select 1 from public.sections where id = p_section_id) then
    raise exception 'Unknown section.';
  end if;

  v_composed_first := trim(p_first_name) ||
    case when trim(p_middle_initial) = '' then ''
         else ' ' || upper(trim(p_middle_initial)) || '.' end;

  update public.profiles
    set first_name = v_composed_first, last_name = trim(p_last_name)
    where id = v_caller;

  insert into public.students (id, student_number, course, year_level, section_id)
  values (v_caller, v_student_number, p_course, p_year_level, p_section_id);

  insert into public.registration_sync_events (event_type, profile_id, detail)
  values ('account_registered', v_caller, 'Student self-registration completed: ' || v_student_number);
end;
$$;

revoke all on function public.complete_student_registration(text, text, text, text, int, uuid) from public;
grant execute on function public.complete_student_registration(text, text, text, text, int, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. claim_preregistered_student — logs 'record_claimed'.
-- ---------------------------------------------------------------------------

create or replace function public.claim_preregistered_student()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_email text;
  v_role public.app_role;
  v_student_number text;
  v_old_id uuid;
  v_old_is_anonymous boolean;
  v_old_rfid_uid text;
  v_old_course text;
  v_old_year_level int;
  v_old_section_id uuid;
  v_old_first_name text;
  v_old_last_name text;
begin
  if v_caller is null then
    raise exception 'Not authenticated.';
  end if;

  select email, role into v_email, v_role
    from public.profiles where id = v_caller;

  if v_role is distinct from 'Student'::public.app_role then
    raise exception 'Only student accounts can claim a pre-registered record.';
  end if;

  if exists (select 1 from public.students where id = v_caller) then
    raise exception 'This account already has a linked student record.';
  end if;

  v_student_number := public._student_number_from_email(v_email);
  if v_student_number is null then
    raise exception 'Could not determine a student number from %.', v_email;
  end if;

  select s.id, s.rfid_uid, s.course, s.year_level, s.section_id,
         p.first_name, p.last_name
    into v_old_id, v_old_rfid_uid, v_old_course, v_old_year_level, v_old_section_id,
         v_old_first_name, v_old_last_name
    from public.students s
    join public.profiles p on p.id = s.id
    where s.student_number = v_student_number;

  if v_old_id is null then
    raise exception 'No pre-registered record found for student number %.', v_student_number
      using errcode = 'P0004';
  end if;

  select u.is_anonymous into v_old_is_anonymous
    from auth.users u where u.id = v_old_id;

  if coalesce(v_old_is_anonymous, false) is not true then
    raise exception 'Student number % is already linked to another account.', v_student_number;
  end if;

  delete from public.students where id = v_old_id;
  delete from public.profiles where id = v_old_id;

  insert into public.students (id, student_number, rfid_uid, course, year_level, section_id)
  values (v_caller, v_student_number, v_old_rfid_uid, v_old_course, v_old_year_level, v_old_section_id);

  update public.profiles
    set first_name = coalesce(nullif(trim(v_old_first_name), ''), first_name),
        last_name = coalesce(nullif(trim(v_old_last_name), ''), last_name)
    where id = v_caller;

  -- profile_id is left null: the old profile row (v_old_id) was just
  -- deleted above, and the new identity is v_caller — the same row that
  -- already got its own 'account_registered' event when it first signed
  -- in, so it isn't repeated here.
  insert into public.registration_sync_events (event_type, profile_id, detail)
  values ('record_claimed', v_caller, 'Pre-registered record claimed for student number ' || v_student_number);
end;
$$;

revoke all on function public.claim_preregistered_student() from public;
grant execute on function public.claim_preregistered_student() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Realtime — lets the Register Syncs page live-update when a new event
--    is logged, matching add_realtime_publication.sql's pattern.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'registration_sync_events'
  ) then
    alter publication supabase_realtime add table public.registration_sync_events;
  end if;
end $$;
