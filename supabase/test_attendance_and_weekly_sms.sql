-- Run AFTER add_attendance_per_class_section.sql and add_weekly_absence_sms.sql.
-- Rollback-only: leaves no data behind. Every `do` block raises on failure.
begin;

-- A. attendance_records has class_section_id and the new unique key.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'attendance_records'
       and column_name = 'class_section_id'
  ) then
    raise exception 'FAIL A1: attendance_records.class_section_id missing';
  end if;

  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (student_id, section_id, session_date)'
  ) then
    raise exception 'FAIL A2: old unique (student_id, section_id, session_date) still present';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) like '%class_section_id%session_date%'
  ) then
    raise exception 'FAIL A3: new unique key missing';
  end if;
end $$;

-- B. Weekly absence SMS: grouping, idempotency, no-absence week, settings gate.
do $$
declare
  v_student uuid;
  v_cs1 uuid;
  v_cs2 uuid;
  v_section uuid;
  v_week date := date '2030-01-07'; -- a Monday far from real data
  v_week2 date := date '2030-02-04'; -- another far-future Monday
  v_n int;
  v_msg text;
begin
  select s.id, s.section_id into v_student, v_section
    from public.students s
   where s.section_id is not null
   limit 1;
  if v_student is null then raise exception 'FAIL B0: no student with a section to test with'; end if;

  select id into v_cs1 from public.class_sections where section_id = v_section limit 1;
  select id into v_cs2 from public.class_sections
   where section_id = v_section and id <> v_cs1 limit 1;
  if v_cs1 is null then raise exception 'FAIL B0: section has no class_sections'; end if;

  -- 2 absences in cs1, 1 in cs2 (or a 3rd date in cs1 if the section has one class)
  insert into public.attendance_records (student_id, section_id, class_section_id, session_date, status)
  values (v_student, v_section, v_cs1, v_week,     'Absent'),
         (v_student, v_section, v_cs1, v_week + 1, 'Absent'),
         (v_student, v_section, coalesce(v_cs2, v_cs1), v_week + 2, 'Absent'),
         (v_student, v_section, v_cs1, v_week + 3, 'Late');

  v_n := public.queue_weekly_absence_sms(v_week);
  if v_n < 1 then raise exception 'FAIL B1: expected >= 1 SMS queued, got %', v_n; end if;

  select message into v_msg from public.sms_outbox
   where kind = 'weekly_absence' and student_id = v_student
   order by created_at desc limit 1;
  if v_msg is null then raise exception 'FAIL B2: no weekly_absence row'; end if;
  if v_msg !~ ' x[0-9]' then raise exception 'FAIL B3: message lacks counts: %', v_msg; end if;
  if v_msg !~ '^[ -~]*$' then raise exception 'FAIL B3a: message has non-ASCII chars: %', v_msg; end if;
  if length(v_msg) > 300 then raise exception 'FAIL B3b: message over 300 chars (%)', length(v_msg); end if;
  if v_msg like '%Late%' then raise exception 'FAIL B4: Late must not be reported: %', v_msg; end if;

  -- Idempotent re-run.
  if public.queue_weekly_absence_sms(v_week) <> 0 then
    raise exception 'FAIL B5: second run queued duplicates';
  end if;

  -- A week with no absences queues nothing.
  if public.queue_weekly_absence_sms(date '2030-03-04') <> 0 then
    raise exception 'FAIL B6: empty week queued SMS';
  end if;

  -- Legacy NULL-class absences: one on the same date as a class-specific
  -- absence (counted once, by the class), one alone (reported as 'a class').
  -- Assumes the section's subject title is non-blank.
  insert into public.attendance_records (student_id, section_id, class_section_id, session_date, status)
  values (v_student, v_section, v_cs1, v_week2, 'Absent'),
         (v_student, v_section, null,  v_week2, 'Absent'),
         (v_student, v_section, null,  v_week2 + 1, 'Absent');
  perform public.queue_weekly_absence_sms(v_week2);
  select message into v_msg from public.sms_outbox
   where kind = 'weekly_absence' and student_id = v_student
     and related_id = md5(v_student::text || '|weekly_absence|' || v_week2::text)::uuid;
  if v_msg is null then raise exception 'FAIL B8: no legacy-row message'; end if;
  if v_msg !~ ' x1' or v_msg ~ ' x[2-9]' then
    raise exception 'FAIL B8: legacy duplicate double counted: %', v_msg;
  end if;
  if v_msg not like '%a class x1%' then
    raise exception 'FAIL B8a: lone legacy absence not reported as a class: %', v_msg;
  end if;
  -- Disabled setting queues nothing.
  update public.sms_settings set weekly_absence_enabled = false where id;
  delete from public.sms_outbox where kind = 'weekly_absence' and student_id = v_student;
  if public.queue_weekly_absence_sms(v_week) <> 0 then
    raise exception 'FAIL B7: disabled setting still queued SMS';
  end if;
end $$;

rollback;
