-- LIVE test of the weekly absenteeism SMS: sends ONE real text to YOUR phone.
-- (For the no-SMS logic test, run test_attendance_and_weekly_sms.sql instead.)
--
-- Safe by design:
--   * Only the student named below is touched, and only inside an isolated
--     test week (2030-01-07 .. 01-12) that has no real attendance. Calling
--     queue_weekly_absence_sms() with no argument would instead text EVERY
--     student with an absence this week — never do that for a test.
--   * The student's real guardian number is saved first and put back in
--     STEP 5, which also deletes every test row.
--
-- Run the steps one at a time in the Supabase SQL Editor, in order.
-- Edit the two values marked  <<  in STEP 1 (and nothing else).
--
-- Needs the one-time SMS setup from add_sms_alerts_schema.sql: the send-sms
-- function deployed, PHILSMS_API_TOKEN / PHILSMS_SENDER_ID / SMS_WEBHOOK_SECRET
-- set, and sms_config pointing at the function. STEP 0 checks the database
-- side; if the function or the PhilSMS credentials are wrong, STEP 4 shows the
-- provider's error.

-- ---------------------------------------------------------------------------
-- STEP 0 — preflight. Every row should say OK.
-- ---------------------------------------------------------------------------
select 'sms_config.function_url set' as check,
       case when function_url is not null and shared_secret is not null
            then 'OK' else 'MISSING - run the sms_config update from add_sms_alerts_schema.sql' end as result
  from public.sms_config
union all
select 'weekly_absence_enabled',
       case when coalesce(weekly_absence_enabled, true) then 'OK'
            else 'OFF - update public.sms_settings set weekly_absence_enabled = true' end
  from public.sms_settings
union all
select 'weekly-absence-sms cron job',
       case when exists (select 1 from cron.job where jobname = 'weekly-absence-sms')
            then 'OK (Saturdays 8 PM Manila)' else 'MISSING - run add_weekly_absence_sms.sql' end;

-- ---------------------------------------------------------------------------
-- STEP 1 — point one student's guardian number at YOUR phone, saving the
-- original first. Pick any student that has a section.
-- ---------------------------------------------------------------------------
create table if not exists public._sms_test_backup (
  student_id uuid primary key,
  guardian_contact_no text
);

insert into public._sms_test_backup (student_id, guardian_contact_no)
select id, guardian_contact_no
  from public.students
 where student_number = 'PUT-STUDENT-NUMBER-HERE'          -- <<
on conflict (student_id) do nothing;

update public.students
   set guardian_contact_no = '09XXXXXXXXX'                  -- << your own mobile number
 where student_number = 'PUT-STUDENT-NUMBER-HERE';          -- << same student number

-- Should show 1 row with your number; if it shows 0 the student number is wrong.
select student_number, guardian_contact_no, public.normalize_ph_mobile(guardian_contact_no) as will_send_to
  from public.students
 where id in (select student_id from public._sms_test_backup);

-- ---------------------------------------------------------------------------
-- STEP 2 — two fake absences (two subjects if the section has two classes)
-- in the isolated test week.
-- ---------------------------------------------------------------------------
do $$
declare
  v_student uuid;
  v_section uuid;
  v_cs1 uuid;
  v_cs2 uuid;
  v_week date := date '2030-01-07';
begin
  select s.id, s.section_id into v_student, v_section
    from public.students s
   where s.id in (select student_id from public._sms_test_backup);
  if v_section is null then
    raise exception 'That student has no section; pick one that does.';
  end if;

  -- Classes the student is actually enrolled in come first; failing that,
  -- any class schedule on file (the foreign key only needs it to exist);
  -- failing that, no class at all (reported in the text as "a class").
  select class_section_id into v_cs1
    from public.enrollments where student_id = v_student limit 1;
  select class_section_id into v_cs2
    from public.enrollments
   where student_id = v_student and class_section_id is distinct from v_cs1
   limit 1;
  if v_cs1 is null then
    select id into v_cs1 from public.class_sections limit 1;
    select id into v_cs2 from public.class_sections
     where id is distinct from v_cs1 limit 1;
  end if;

  insert into public.attendance_records
    (student_id, section_id, class_section_id, session_date, status)
  values (v_student, v_section, v_cs1, v_week,     'Absent'),
         (v_student, v_section, v_cs1, v_week + 1, 'Absent'),
         (v_student, v_section, coalesce(v_cs2, v_cs1), v_week + 2, 'Absent')
  on conflict do nothing;
end $$;

-- Should show 3 rows (class_section_id may be empty if no schedules exist).
select session_date, status, class_section_id
  from public.attendance_records
 where student_id in (select student_id from public._sms_test_backup)
   and session_date between date '2030-01-07' and date '2030-01-12'
 order by session_date;

-- ---------------------------------------------------------------------------
-- STEP 3 — queue the weekly message for the test week ONLY. Returns 1.
-- Inserting into sms_outbox pings the send-sms function immediately.
-- ---------------------------------------------------------------------------
select public.queue_weekly_absence_sms(date '2030-01-07') as messages_queued;

-- ---------------------------------------------------------------------------
-- STEP 4 — watch the result (re-run after ~10 seconds).
--   pending/sending -> still going        sent    -> check your phone
--   failed          -> read "error" and "provider_response" below; the
--                      sweeper retries failed rows every 5 minutes (5 tries)
--   skipped         -> the number was not a valid PH mobile (09XXXXXXXXX)
-- ---------------------------------------------------------------------------
select status, attempts, recipient, message, error, provider_response, sent_at
  from public.sms_outbox
 where kind = 'weekly_absence'
   and student_id in (select student_id from public._sms_test_backup)
 order by created_at desc;

-- ---------------------------------------------------------------------------
-- STEP 5 — CLEANUP. Restores the real guardian number and removes every test
-- row. Run it even if the text failed. Safe to run twice: if the backup table
-- is already gone it says so instead of erroring (and then the guardian number
-- can no longer be restored automatically — check it by hand).
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public._sms_test_backup') is null then
    raise notice 'No backup table: cleanup already ran (or STEP 1 never committed). '
      'Check the student''s guardian_contact_no by hand.';
    return;
  end if;

  update public.students s
     set guardian_contact_no = b.guardian_contact_no
    from public._sms_test_backup b
   where s.id = b.student_id;

  delete from public.sms_outbox o
   using public._sms_test_backup b
   where o.kind = 'weekly_absence'
     and o.student_id = b.student_id
     and o.related_id = md5(b.student_id::text || '|weekly_absence|2030-01-07')::uuid;

  delete from public.attendance_records a
   using public._sms_test_backup b
   where a.student_id = b.student_id
     and a.session_date between date '2030-01-07' and date '2030-01-12';

  drop table public._sms_test_backup;
end $$;
