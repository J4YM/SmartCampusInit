-- Weekly parent SMS: which subjects the student was marked ABSENT in this week.
--
-- Runs Saturdays 8:00 PM Asia/Manila (pg_cron, UTC: 12:00) so Saturday classes
-- are included. Covers Mon-Sat of the current week. One SMS per student per week through the existing sms_outbox /
-- send-sms pipeline (see add_sms_alerts_schema.sql). All rows are queued in ONE
-- INSERT statement (one statement-level dispatcher ping), reusing
-- normalize_ph_mobile and the same skipped/pending logic as queue_sms.
-- Students with no absences get nothing.
--
-- The message text is plain ASCII (GSM-7) so it is billed as one SMS segment
-- where possible: "x2" not a multiplication sign, "-" not an en dash, "..."
-- not an ellipsis character.
--
-- Run in Supabase SQL Editor after add_sms_alerts_schema.sql and
-- add_attendance_per_class_section.sql. Idempotent.
-- NOTE: re-run this file in the SQL Editor to pick up the legacy-row
-- double-counting guard in queue_weekly_absence_sms.

alter table public.sms_settings
  add column if not exists weekly_absence_enabled boolean not null default true;

-- Builds one student's message, capped at 300 chars. Items are listed until
-- the next one would not fit; the remainder becomes " ...and N more". Room for
-- that suffix (up to " ...and 999 more" = 16 chars) plus the closing "." is
-- reserved whenever more items remain.
create or replace function public.build_weekly_absence_message(
  p_school text,
  p_name text,
  p_label text,
  p_items text[]
)
returns text
language plpgsql
immutable
as $$
declare
  v_max_len constant int := 300;
  v_suffix_reserve constant int := 16;
  v_prefix text;
  v_listed text := '';
  v_candidate text;
  v_n int := coalesce(array_length(p_items, 1), 0);
  v_i int;
  v_reserve int;
begin
  v_prefix := coalesce(p_school, 'STI Baliuag') || ': Weekly absences for '
    || coalesce(p_name, 'your child') || ' (' || p_label || '): ';

  for v_i in 1 .. v_n loop
    v_candidate := v_listed || case when v_i > 1 then ', ' else '' end
      || p_items[v_i];
    -- Computed outside the IF: PL/pgSQL ends an IF condition at the FIRST
    -- `then` token, so a CASE ... THEN inside the condition is a syntax error.
    v_reserve := case when v_i < v_n then v_suffix_reserve else 0 end;
    if v_i > 1
       and length(v_prefix || v_candidate) + 1 + v_reserve > v_max_len
    then
      v_listed := v_listed || ' ...and ' || (v_n - v_i + 1) || ' more';
      exit;
    end if;
    v_listed := v_candidate;
  end loop;

  -- Hard cap as a last resort (e.g. an absurdly long name on the first item).
  return left(v_prefix || v_listed || '.', v_max_len);
end;
$$;

create or replace function public.queue_weekly_absence_sms(
  p_week_start date default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_week date;
  v_label text;
  v_count int;
begin
  select * into s from public.sms_settings where id;
  if not coalesce(s.weekly_absence_enabled, true) then
    return 0;
  end if;

  -- Monday of the given (or current Manila) week.
  v_week := date_trunc(
    'week',
    coalesce(p_week_start, (now() at time zone 'Asia/Manila')::date)
  )::date;
  v_label := to_char(v_week, 'FMMon FMDD') || '-' || to_char(v_week + 5, 'FMMon FMDD');

  insert into public.sms_outbox
    (kind, student_id, related_id, recipient, message, status, error)
  select
    'weekly_absence',
    x.student_id,
    md5(x.student_id::text || '|weekly_absence|' || v_week::text)::uuid,
    x.v_to,
    public.build_weekly_absence_message(
      s.school_name, public.sms_student_name(x.student_id), v_label, x.items
    ),
    case when x.v_to is null then 'skipped' else 'pending' end,
    case
      when x.v_to is not null then null
      when coalesce(btrim(x.v_raw), '') = '' then 'No guardian contact number on file'
      else 'Guardian contact number is not a valid PH mobile number: ' || x.v_raw
    end
  from (
    select t.student_id,
           array_agg(t.subject || ' x' || t.n order by t.subject) as items,
           st.guardian_contact_no as v_raw,
           public.normalize_ph_mobile(st.guardian_contact_no) as v_to
      from (
        select ar.student_id,
               coalesce(nullif(btrim(sub.title), ''), 'a class') as subject,
               count(*) as n
          from public.attendance_records ar
          left join public.class_sections cs on cs.id = ar.class_section_id
          left join public.subjects sub on sub.id = cs.subject_id
         where ar.status::text = 'Absent'
           and ar.session_date between v_week and v_week + 5
           -- Legacy NULL-class absence is ignored when the student has any
           -- class-specific row that day (avoids double counting).
           and (ar.class_section_id is not null
                or not exists (
                  select 1 from public.attendance_records ar2
                   where ar2.student_id = ar.student_id
                     and ar2.session_date = ar.session_date
                     and ar2.class_section_id is not null))
         group by ar.student_id, coalesce(nullif(btrim(sub.title), ''), 'a class')
      ) t
      left join public.students st on st.id = t.student_id
     group by t.student_id, st.guardian_contact_no
  ) x
  on conflict (kind, related_id) do nothing;

  -- Counts only rows actually inserted (conflicts are skipped).
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.queue_weekly_absence_sms(date)
  from public, anon, authenticated;
grant execute on function public.queue_weekly_absence_sms(date) to service_role;

-- Saturdays 8:00 PM Manila = 12:00 UTC Saturday. Scheduling under the same job
-- name replaces the earlier Friday 09:00 UTC schedule when this file is re-run.
select cron.schedule(
  'weekly-absence-sms',
  '0 12 * * 6',
  $$select public.queue_weekly_absence_sms();$$
);
