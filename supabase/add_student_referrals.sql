-- Student referrals for intervention.
--
-- A student can ask Guidance for help from their own dashboard, either for
-- themselves or on behalf of a classmate they are worried about.
--
-- Flow
--   1. The student submits the form on the Student Dashboard. For a
--      classmate they type that student's number; the lookup happens inside
--      submit_student_referral() so a student never gets read access to
--      other students' records.
--   2. The row is saved as `Pending`; a trigger notifies the Guidance
--      Counselor role (urgent ones are labelled as such).
--   3. The Guidance Counselor moves it to `In_Progress` / `Closed` from the
--      Referrals tab, optionally leaving a note the referrer can read.
--
-- The referrer's identity is never shown to the student the referral is
-- about; only staff see who filed it.
--
-- A referral that mentions a sensitive topic (see sensitive_keywords in
-- add_sensitive_word_escalation.sql) is raised to `Urgent` automatically when
-- that file has been run.
--
-- Run in Supabase SQL Editor after add_notifications_schema.sql
-- (and, optionally, add_sensitive_word_escalation.sql). Idempotent.

create table if not exists public.student_referrals (
  id uuid primary key default gen_random_uuid(),
  -- The student the referral is about (the referrer themselves for a
  -- self-referral).
  student_id uuid not null references public.students(id) on delete cascade,
  -- The student who filed it.
  referred_by uuid not null references public.profiles(id) on delete cascade,
  is_self boolean not null default true,
  -- 'academic' | 'attendance' | 'behavior' | 'emotional' | 'family'
  -- | 'bullying' | 'safety' | 'other'
  concern text not null default 'other',
  details text not null default '',
  urgency text not null default 'Normal',
  status text not null default 'Pending',
  -- Visible to the referrer on their dashboard.
  counselor_note text,
  handled_by uuid references public.profiles(id) on delete set null,
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint student_referrals_status_check
    check (status in ('Pending', 'In_Progress', 'Closed')),
  constraint student_referrals_urgency_check
    check (urgency in ('Normal', 'Urgent')),
  constraint student_referrals_concern_check
    check (concern in ('academic', 'attendance', 'behavior', 'emotional',
                       'family', 'bullying', 'safety', 'other'))
);

create index if not exists student_referrals_status_idx
  on public.student_referrals (status, created_at desc);
create index if not exists student_referrals_referrer_idx
  on public.student_referrals (referred_by, created_at desc);
create index if not exists student_referrals_student_idx
  on public.student_referrals (student_id, created_at desc);

alter table public.student_referrals enable row level security;

-- Staff who work referrals read everything and update status / note.
drop policy if exists "student_referrals_staff_select" on public.student_referrals;
create policy "student_referrals_staff_select" on public.student_referrals
  for select to authenticated
  using (current_user_role() in
    ('Admin'::app_role, 'Guidance_Counselor'::app_role, 'Discipline_Officer'::app_role));

drop policy if exists "student_referrals_staff_update" on public.student_referrals;
create policy "student_referrals_staff_update" on public.student_referrals
  for update to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Guidance_Counselor'::app_role))
  with check (current_user_role() in ('Admin'::app_role, 'Guidance_Counselor'::app_role));

-- A student reads only the referrals they filed themselves (never ones that
-- are about them but were filed by someone else).
drop policy if exists "student_referrals_referrer_select" on public.student_referrals;
create policy "student_referrals_referrer_select" on public.student_referrals
  for select to authenticated
  using (referred_by = auth.uid());

-- Demo mode: static demo accounts run under the anon key (same tradeoff as
-- add_escalation_reports.sql / add_notifications_schema.sql). Tighten before
-- production.
drop policy if exists "student_referrals_anon_select" on public.student_referrals;
create policy "student_referrals_anon_select" on public.student_referrals
  for select to anon using (true);
drop policy if exists "student_referrals_anon_update" on public.student_referrals;
create policy "student_referrals_anon_update" on public.student_referrals
  for update to anon using (true) with check (true);

-- ---------------------------------------------------------------------------
-- submit_student_referral — the only way a student creates one
-- ---------------------------------------------------------------------------
create or replace function public.submit_student_referral(
  p_referrer_id uuid,
  p_concern text,
  p_details text,
  p_about_student_number text default null,   -- null/blank = about myself
  p_urgent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subject uuid;
  v_is_self boolean := coalesce(btrim(p_about_student_number), '') = '';
  v_urgency text := case when p_urgent then 'Urgent' else 'Normal' end;
  v_id uuid;
  v_concern text := coalesce(nullif(btrim(p_concern), ''), 'other');
begin
  if auth.role() = 'authenticated' and p_referrer_id is distinct from auth.uid() then
    raise exception 'You can only file a referral as yourself.' using errcode = '42501';
  end if;

  if not exists (select 1 from public.students where id = p_referrer_id) then
    raise exception 'Only a student can file a referral.';
  end if;

  if coalesce(btrim(p_details), '') = '' then
    raise exception 'Please describe your concern.';
  end if;

  if v_is_self then
    v_subject := p_referrer_id;
  else
    select id into v_subject
      from public.students
     where lower(student_number) = lower(btrim(p_about_student_number))
     limit 1;
    if v_subject is null then
      raise exception 'No student found with number %.', btrim(p_about_student_number);
    end if;
    if v_subject = p_referrer_id then
      v_is_self := true;
    end if;
  end if;

  -- A sensitive topic is never left as a routine request.
  if to_regproc('public.find_sensitive_terms(text)') is not null then
    if coalesce(array_length(public.find_sensitive_terms(p_details), 1), 0) > 0 then
      v_urgency := 'Urgent';
    end if;
  end if;
  if v_concern in ('safety', 'bullying') and not v_is_self then
    v_urgency := 'Urgent';
  end if;

  insert into public.student_referrals (
    student_id, referred_by, is_self, concern, details, urgency
  )
  values (
    v_subject, p_referrer_id, v_is_self, v_concern, btrim(p_details), v_urgency
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_student_referral(uuid, text, text, text, boolean) from public;
grant execute on function public.submit_student_referral(uuid, text, text, text, boolean)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The referrer's own list, with the counselor's note — no data about
-- anyone else.
-- ---------------------------------------------------------------------------
create or replace function public.my_student_referrals(p_referrer_id uuid)
returns table (
  id uuid,
  is_self boolean,
  concern text,
  urgency text,
  status text,
  counselor_note text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.is_self, r.concern, r.urgency, r.status, r.counselor_note, r.created_at
    from public.student_referrals r
   where r.referred_by = p_referrer_id
     and (auth.role() <> 'authenticated' or p_referrer_id = auth.uid())
   order by r.created_at desc;
$$;

revoke all on function public.my_student_referrals(uuid) from public;
grant execute on function public.my_student_referrals(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Notify the Guidance Counselor when one comes in.
-- ---------------------------------------------------------------------------
create or replace function public.trg_notify_student_referral()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (target_role, title, message)
  values (
    'Guidance_Counselor'::app_role,
    case when new.urgency = 'Urgent'
      then 'Urgent student referral'
      else 'New student referral' end,
    public.sms_student_name(new.student_id)
      || case when new.is_self
           then ' asked for help.'
           else ' was referred by a classmate.' end
      || ' Review it under Referrals.'
  );
  return new;
exception when others then
  raise warning 'trg_notify_student_referral failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists student_referrals_notify on public.student_referrals;
create trigger student_referrals_notify
  after insert on public.student_referrals
  for each row execute function public.trg_notify_student_referral();
