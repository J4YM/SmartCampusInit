-- Referrals belong to Guidance.
--
--   * A student's Self Referral (mental health or other troubles) goes to the
--     Guidance Associate only. The Discipline Officer / Student Affairs can no
--     longer read student_referrals.
--   * An Endorsement the Guidance Associate approves becomes a Referral
--     (source 'endorsement') so it can be worked and scheduled like a
--     self referral. Students never read these; they learn of one through a
--     meeting invitation.
--   * "Refer another student by number" is gone: submit_student_referral is
--     self only. Old classmate referrals were copied to concern_reports by
--     add_concern_reports.sql and are removed here.
--
-- Run in Supabase SQL Editor after add_concern_reports.sql. Idempotent.

-- ---------------------------------------------------------------------------
-- 1. Shape
-- ---------------------------------------------------------------------------

-- Classmate referrals were copied to concern_reports (same id) already.
delete from public.student_referrals r
 where r.is_self = false
   and exists (select 1 from public.concern_reports c where c.id = r.id);

alter table public.student_referrals
  add column if not exists source text not null default 'self';
alter table public.student_referrals
  drop constraint if exists student_referrals_source_check;
alter table public.student_referrals
  add constraint student_referrals_source_check
  check (source in ('self', 'endorsement'));

alter table public.student_referrals
  add column if not exists endorsement_id uuid
    references public.escalation_reports(id) on delete cascade;
create unique index if not exists student_referrals_endorsement_uidx
  on public.student_referrals (endorsement_id)
  where endorsement_id is not null;

-- An endorsement referral has no student author.
alter table public.student_referrals alter column referred_by drop not null;

-- ---------------------------------------------------------------------------
-- 2. Who can read: Guidance (and Admin) only
-- ---------------------------------------------------------------------------

drop policy if exists "student_referrals_staff_select" on public.student_referrals;
create policy "student_referrals_staff_select" on public.student_referrals
  for select to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Guidance_Counselor'::app_role));

drop policy if exists "student_referrals_staff_update" on public.student_referrals;
create policy "student_referrals_staff_update" on public.student_referrals
  for update to authenticated
  using (current_user_role() in ('Admin'::app_role, 'Guidance_Counselor'::app_role))
  with check (current_user_role() in ('Admin'::app_role, 'Guidance_Counselor'::app_role));

-- ---------------------------------------------------------------------------
-- 3. Self referral only
-- ---------------------------------------------------------------------------

drop function if exists public.submit_student_referral(uuid, text, text, text, boolean);

create or replace function public.submit_student_referral(
  p_referrer_id uuid,
  p_concern text,
  p_details text,
  p_urgent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_urgency text := case when p_urgent then 'Urgent' else 'Normal' end;
  v_concern text := coalesce(nullif(btrim(p_concern), ''), 'other');
  v_id uuid;
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

  -- A sensitive topic is never left as a routine request.
  if to_regproc('public.find_sensitive_terms(text)') is not null then
    if coalesce(array_length(public.find_sensitive_terms(p_details), 1), 0) > 0 then
      v_urgency := 'Urgent';
    end if;
  end if;

  insert into public.student_referrals (
    student_id, referred_by, is_self, concern, details, urgency, source
  )
  values (
    p_referrer_id, p_referrer_id, true, v_concern, btrim(p_details), v_urgency, 'self'
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_student_referral(uuid, text, text, boolean) from public;
grant execute on function public.submit_student_referral(uuid, text, text, boolean)
  to anon, authenticated;

-- The student's own self referrals, with the counselor's note.
drop function if exists public.my_student_referrals(uuid);

create or replace function public.my_student_referrals(p_referrer_id uuid)
returns table (
  id uuid,
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
  select r.id, r.concern, r.urgency, r.status, r.counselor_note, r.created_at
    from public.student_referrals r
   where r.referred_by = p_referrer_id
     and r.source = 'self'
     and (auth.role() <> 'authenticated' or p_referrer_id = auth.uid())
   order by r.created_at desc;
$$;

revoke all on function public.my_student_referrals(uuid) from public;
grant execute on function public.my_student_referrals(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Tell Guidance
-- ---------------------------------------------------------------------------

create or replace function public.trg_notify_student_referral()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source <> 'self' then
    return new;
  end if;
  insert into public.notifications (target_role, title, message)
  values (
    'Guidance_Counselor'::app_role,
    case when new.urgency = 'Urgent'
      then 'Urgent student referral'
      else 'New student referral' end,
    public.sms_student_name(new.student_id)
      || ' asked for help. Review it under Referrals.'
  );
  return new;
exception when others then
  raise warning 'trg_notify_student_referral failed: %', sqlerrm;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. An approved endorsement becomes a referral
-- ---------------------------------------------------------------------------

create or replace function public.trg_referral_from_endorsement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.student_referrals (
    student_id, referred_by, is_self, concern, details, source, endorsement_id
  )
  values (
    new.student_id,
    new.created_by,
    false,
    'other',
    btrim(coalesce(nullif(btrim(new.title), ''), 'Endorsement')
          || coalesce(': ' || nullif(btrim(new.summary), ''), '')),
    'endorsement',
    new.id
  )
  on conflict (endorsement_id) where endorsement_id is not null do nothing;

  insert into public.notifications (target_role, title, message)
  values (
    'Guidance_Counselor'::app_role,
    'New referral from Student Affairs',
    public.sms_student_name(new.student_id)
      || ' was endorsed by Student Affairs. Review it under Referrals.'
  );
  return new;
exception when others then
  raise warning 'trg_referral_from_endorsement failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists escalation_reports_to_referral on public.escalation_reports;
create trigger escalation_reports_to_referral
  after update of status on public.escalation_reports
  for each row
  when (old.status is distinct from new.status and new.status = 'Approved')
  execute function public.trg_referral_from_endorsement();
