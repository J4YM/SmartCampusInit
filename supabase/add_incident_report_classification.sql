-- Incident reports are filed by professors / security with WHAT happened,
-- WHEN it happened and photo evidence. They do NOT pick the violation: the
-- Discipline Officer (DO) classifies the report afterwards.
--
--   * student_violations.incident_at   - when the incident actually happened
--                                        (created_at stays "when it was filed")
--   * student_violations.offense_id    - now nullable (null until classified)
--   * classified_by / classified_at    - who classified it and when
--   * violation_status 'Investigation_Complete' - guidance finished; DO may sanction
--   * violation_evidence + bucket      - photo evidence per report
--   * submit_incident_report(...)      - new report entry point
--   * classify_violation(...)          - DO picks the handbook offense(s)
--
-- Run in Supabase SQL Editor, after add_professor_violation_confirmation.sql
-- and add_notifications_schema.sql. Idempotent.
--
-- IMPORTANT: run change_auto_escalation_to_suggestion.sql right after this
-- one — the older BEFORE INSERT triggers on student_violations assume
-- offense_id is never null.
--
-- NOTE: `alter type ... add value` must commit before the new value is used;
-- if the editor complains, run that one statement on its own first.

alter type public.violation_status add value if not exists 'Investigation_Complete';

alter table public.student_violations
  add column if not exists incident_at timestamptz,
  add column if not exists classified_by uuid references public.profiles(id) on delete set null,
  add column if not exists classified_at timestamptz,
  add column if not exists incident_notes text,
  -- Also added by change_violation_expiry_to_flag.sql; classify_violation
  -- copies them to sibling rows, so they must exist whichever script ran first.
  add column if not exists expiry_warned_at timestamptz,
  add column if not exists expiry_notified_at timestamptz;

-- Legacy rows: the best available incident time is the filing time.
update public.student_violations
   set incident_at = created_at
 where incident_at is null;

alter table public.student_violations
  alter column offense_id drop not null;

create index if not exists student_violations_unclassified_idx
  on public.student_violations (created_at)
  where offense_id is null;

-- ---------------------------------------------------------------------------
-- Shared audit helper (also used by the sanction / guidance scripts).
-- A logging failure never breaks the action being logged.
-- ---------------------------------------------------------------------------

create or replace function public.log_audit(
  p_action text,
  p_record_id text default null,
  p_severity text default 'INFO'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_role app_role;
begin
  select coalesce(email, ''), role into v_email, v_role
    from public.profiles where id = auth.uid();
  if v_role is null then
    return;  -- anon/kiosk caller: no profile to attribute the entry to
  end if;
  insert into public.audit_logs (actor_id, actor_email, actor_role, action, record_id, severity)
  values (auth.uid(), v_email, v_role, p_action, p_record_id, p_severity::audit_severity);
exception when others then
  raise warning 'log_audit failed: %', sqlerrm;
end;
$$;

revoke all on function public.log_audit(text, text, text) from public;
grant execute on function public.log_audit(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Evidence
-- ---------------------------------------------------------------------------

create table if not exists public.violation_evidence (
  id uuid primary key default gen_random_uuid(),
  violation_id uuid not null references public.student_violations(id) on delete cascade,
  storage_path text not null,
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists violation_evidence_violation_id_idx
  on public.violation_evidence (violation_id);

alter table public.violation_evidence enable row level security;

drop policy if exists "violation_evidence_select" on public.violation_evidence;
create policy "violation_evidence_select"
  on public.violation_evidence for select to authenticated
  using (
    current_user_role() in
      ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role)
    or uploaded_by = auth.uid()
  );

-- Rows are written only by submit_incident_report (SECURITY DEFINER).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'violation-evidence', 'violation-evidence', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types,
      public = false;

-- Reporters (including the kiosk, which runs on the anon key like the rest of
-- the kiosk flow) may upload; only staff who handle the case may read.
drop policy if exists "violation_evidence_upload" on storage.objects;
create policy "violation_evidence_upload"
  on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'violation-evidence');

drop policy if exists "violation_evidence_read" on storage.objects;
create policy "violation_evidence_read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'violation-evidence'
    and current_user_role() in
      ('Admin'::app_role, 'Discipline_Officer'::app_role, 'Guidance_Counselor'::app_role)
  );

-- ---------------------------------------------------------------------------
-- submit_incident_report
-- ---------------------------------------------------------------------------
-- Files one unclassified report. Returns the new student_violations id.

create or replace function public.submit_incident_report(
  p_student_id uuid,
  p_incident_at timestamptz,
  p_description text,
  p_evidence_paths text[],
  p_reported_by uuid,
  p_professor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_path text;
begin
  if p_incident_at is null then
    raise exception 'Incident date and time are required.';
  end if;
  if p_incident_at > now() + interval '1 minute' then
    raise exception 'Incident date and time cannot be in the future.';
  end if;
  if btrim(coalesce(p_description, '')) = '' then
    raise exception 'A description of the incident is required.';
  end if;
  if auth.role() = 'authenticated' and p_reported_by is distinct from auth.uid() then
    raise exception 'You can only file reports as yourself.' using errcode = '42501';
  end if;

  insert into public.student_violations (
    student_id, offense_id, reported_by, professor_id, status,
    incident_at, incident_notes
  )
  values (
    p_student_id, null, p_reported_by, p_professor_id, 'Pending',
    p_incident_at, btrim(p_description)
  )
  returning id into v_id;

  foreach v_path in array coalesce(p_evidence_paths, '{}'::text[]) loop
    insert into public.violation_evidence (violation_id, storage_path, uploaded_by)
    values (v_id, v_path, p_reported_by);
  end loop;

  begin
    insert into public.notifications (target_role, title, message)
    values (
      'Discipline_Officer'::app_role,
      'New incident report to classify',
      public.sms_student_name(p_student_id)
        || ' has a new incident report awaiting classification.'
    );
  exception when others then
    raise warning 'submit_incident_report notify failed: %', sqlerrm;
  end;

  perform public.log_audit('Filed incident report', v_id::text);

  return v_id;
end;
$$;

-- Signed-in reporters only. The kiosk files through submit_admission_slip.
revoke all on function public.submit_incident_report(
  uuid, timestamptz, text, text[], uuid, uuid) from public, anon;
grant execute on function public.submit_incident_report(
  uuid, timestamptz, text, text[], uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- classify_violation
-- ---------------------------------------------------------------------------
-- The DO picks the handbook offense(s). The first offense is set on the
-- existing row; each additional offense becomes a sibling row copied from it
-- (same student, incident, notes, evidence) so every offense is counted.

create or replace function public.classify_violation(
  p_violation_id uuid,
  p_offense_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.student_violations;
  v_first uuid;
  v_extra uuid;
  v_new_id uuid;
begin
  if not coalesce(current_user_role() in
     ('Admin'::app_role, 'Discipline_Officer'::app_role), false) then
    raise exception 'Only the Discipline Officer can classify a report.'
      using errcode = '42501';
  end if;
  if array_length(p_offense_ids, 1) is null then
    raise exception 'At least one offense is required.';
  end if;

  select * into v from public.student_violations
   where id = p_violation_id for update;
  if not found then
    raise exception 'Report not found.';
  end if;
  if v.offense_id is not null then
    raise exception 'This report is already classified.';
  end if;

  v_first := p_offense_ids[1];
  update public.student_violations
     set offense_id = v_first,
         classified_by = auth.uid(),
         classified_at = now()
   where id = p_violation_id;

  foreach v_extra in array p_offense_ids[2:array_length(p_offense_ids, 1)] loop
    -- A sibling is the same incident under another offense, so it carries the
    -- original's whole timeline (filed time, 72-hour clock, professor answer)
    -- rather than starting fresh.
    insert into public.student_violations (
      student_id, offense_id, reported_by, professor_id, status,
      incident_at, incident_notes, classified_by, classified_at,
      admission_slip_id, created_at, restored_at, expired_at,
      expiry_warned_at, expiry_notified_at, professor_decision,
      professor_decision_note, professor_decided_at, sla_due_at, is_escalated
    )
    values (
      v.student_id, v_extra, v.reported_by, v.professor_id, v.status,
      v.incident_at, v.incident_notes, auth.uid(), now(),
      v.admission_slip_id, v.created_at, v.restored_at, v.expired_at,
      v.expiry_warned_at, v.expiry_notified_at, v.professor_decision,
      v.professor_decision_note, v.professor_decided_at, v.sla_due_at,
      v.is_escalated
    )
    returning id into v_new_id;

    insert into public.violation_evidence (violation_id, storage_path, uploaded_by)
    select v_new_id, storage_path, uploaded_by
      from public.violation_evidence where violation_id = p_violation_id;
  end loop;

  perform public.log_audit('Classified violation report', p_violation_id::text);
end;
$$;

revoke all on function public.classify_violation(uuid, uuid[]) from public, anon;
grant execute on function public.classify_violation(uuid, uuid[])
  to authenticated;
