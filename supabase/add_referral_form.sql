-- The External Referral Form (STI Guidance and Counseling Office, FT-SDW-164-00)
-- for a student's Self Referral.
--
-- The Request Support sheet now also collects what the paper form asks: who to
-- refer to, the specific concerns, and the student's address / birthdate /
-- program. It is stored with the referral as `form` (jsonb) so the student and
-- the Guidance Associate can both view and print the form afterwards.
--
--   * student_referrals.form: the form as the student filled it in (see
--     ReferralFormData in packages/dashboard_layout). {} for referrals sent
--     before this file was run and for endorsement referrals.
--   * submit_student_referral gains p_form; the old four-argument version is
--     replaced, so run this BEFORE shipping the app that sends p_form.
--   * my_student_referrals also returns details and form, so the student can
--     open the form again from their own list.
--
-- Run in Supabase SQL Editor after add_guidance_referrals.sql. Idempotent.

alter table public.student_referrals
  add column if not exists form jsonb not null default '{}'::jsonb;

alter table public.student_referrals
  drop constraint if exists student_referrals_form_check;
alter table public.student_referrals
  add constraint student_referrals_form_check
  check (jsonb_typeof(form) = 'object' and pg_column_size(form) <= 20000);

-- ---------------------------------------------------------------------------
-- Self referral with the form
-- ---------------------------------------------------------------------------

drop function if exists public.submit_student_referral(uuid, text, text, boolean);

create or replace function public.submit_student_referral(
  p_referrer_id uuid,
  p_concern text,
  p_details text,
  p_urgent boolean default false,
  p_form jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_urgency text := case when p_urgent then 'Urgent' else 'Normal' end;
  v_concern text := coalesce(nullif(btrim(p_concern), ''), 'other');
  v_form jsonb := case when jsonb_typeof(p_form) = 'object' then p_form else '{}'::jsonb end;
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
    student_id, referred_by, is_self, concern, details, urgency, source, form
  )
  values (
    p_referrer_id, p_referrer_id, true, v_concern, btrim(p_details), v_urgency,
    'self', v_form
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_student_referral(uuid, text, text, boolean, jsonb)
  from public;
grant execute on function public.submit_student_referral(uuid, text, text, boolean, jsonb)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The student's own list, with what they wrote and the form
-- ---------------------------------------------------------------------------

drop function if exists public.my_student_referrals(uuid);

create or replace function public.my_student_referrals(p_referrer_id uuid)
returns table (
  id uuid,
  concern text,
  urgency text,
  status text,
  counselor_note text,
  created_at timestamptz,
  details text,
  form jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.concern, r.urgency, r.status, r.counselor_note, r.created_at,
         r.details, r.form
    from public.student_referrals r
   where r.referred_by = p_referrer_id
     and r.source = 'self'
     and (auth.role() <> 'authenticated' or p_referrer_id = auth.uid())
   order by r.created_at desc;
$$;

revoke all on function public.my_student_referrals(uuid) from public;
grant execute on function public.my_student_referrals(uuid) to anon, authenticated;
