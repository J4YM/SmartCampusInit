-- Weekly parent SMS: which subjects the student was marked ABSENT in this week.
--
-- Runs Fridays 5:00 PM Asia/Manila (pg_cron, UTC: 09:00). Covers Mon-Sat of the
-- current week. One SMS per student per week through the existing sms_outbox /
-- send-sms pipeline (see add_sms_alerts_schema.sql); queue_sms resolves and
-- validates the guardian number. Students with no absences get nothing.
--
-- Run in Supabase SQL Editor after add_sms_alerts_schema.sql and
-- add_attendance_per_class_section.sql. Idempotent.

alter table public.sms_settings
  add column if not exists weekly_absence_enabled boolean not null default true;

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
  v_before int;
  v_after int;
  r record;
  v_items text[];
  v_msg text;
  v_listed text;
  v_i int;
  v_prefix text;
  v_max_len constant int := 300;
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
  v_label := to_char(v_week, 'FMMon FMDD') || '–' || to_char(v_week + 5, 'FMMon FMDD');

  select count(*) into v_before
    from public.sms_outbox where kind = 'weekly_absence';

  for r in
    select t.student_id,
           array_agg(t.subject || ' ×' || t.n order by t.subject) as items
      from (
        select ar.student_id,
               coalesce(nullif(btrim(sub.title), ''), 'a class') as subject,
               count(*) as n
          from public.attendance_records ar
          left join public.class_sections cs on cs.id = ar.class_section_id
          left join public.subjects sub on sub.id = cs.subject_id
         where ar.status::text = 'Absent'
           and ar.session_date between v_week and v_week + 5
         group by ar.student_id, coalesce(nullif(btrim(sub.title), ''), 'a class')
      ) t
     group by t.student_id
  loop
    v_prefix := coalesce(s.school_name, 'STI Baliuag') || ': Weekly absences for '
      || public.sms_student_name(r.student_id) || ' (' || v_label || '): ';

    v_items := r.items;
    v_listed := '';
    for v_i in 1 .. array_length(v_items, 1) loop
      if length(v_prefix || v_listed || v_items[v_i]) > v_max_len and v_i > 1 then
        v_listed := v_listed || ' …and ' || (array_length(v_items, 1) - v_i + 1) || ' more';
        exit;
      end if;
      v_listed := v_listed || case when v_i > 1 then ', ' else '' end || v_items[v_i];
    end loop;

    v_msg := v_prefix || v_listed || '.';

    perform public.queue_sms(
      'weekly_absence',
      r.student_id,
      md5(r.student_id::text || '|weekly_absence|' || v_week::text)::uuid,
      v_msg
    );

  end loop;

  -- queue_sms is `on conflict do nothing`, so the number of NEW rows is the
  -- difference in total weekly_absence rows across the run.
  select count(*) into v_after
    from public.sms_outbox where kind = 'weekly_absence';

  return v_after - v_before;
exception when others then
  raise warning 'queue_weekly_absence_sms failed: %', sqlerrm;
  return 0;
end;
$$;

revoke all on function public.queue_weekly_absence_sms(date)
  from public, anon, authenticated;
grant execute on function public.queue_weekly_absence_sms(date) to service_role;

-- Fridays 5:00 PM Manila = 09:00 UTC.
select cron.schedule(
  'weekly-absence-sms',
  '0 9 * * 5',
  $$select public.queue_weekly_absence_sms();$$
);
