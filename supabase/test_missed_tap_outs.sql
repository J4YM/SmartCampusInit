-- Assertions for replace_auto_tap_out.sql. Run in the Supabase SQL Editor on a
-- DEV project as an Admin session, AFTER replace_auto_tap_out.sql has been run
-- once (it also converts the old automatic tap-outs). It needs two students
-- and an rfid reader. Rolled back at the end. Run once BEFORE the migration
-- (fails at the first assertion) and once AFTER (prints "ALL PASSED").

begin;

do $$
declare
  v_a uuid; v_b uuid; v_c uuid; v_reader uuid;
  v_run timestamptz := timestamptz '2031-03-03 18:30:00+08';
  v_day date := date '2031-03-03';
  v_before int; v_n int;
begin
  select id into v_reader from public.rfid_readers limit 1;
  assert v_reader is not null, 'need an rfid reader';
  select id into v_a from public.students order by id limit 1;
  select id into v_b from public.students where id <> v_a order by id limit 1;
  select id into v_c from public.students where id not in (v_a, v_b) order by id limit 1;
  assert v_c is not null, 'need three students';

  -- A taps in and never out; B taps in and out; C never taps.
  insert into public.rfid_tap_events (reader_id, rfid_uid, student_id, tap_direction, tapped_at)
  values (v_reader, 'T-A', v_a, 'in',  (v_day + time '07:30') at time zone 'Asia/Manila'),
         (v_reader, 'T-B', v_b, 'in',  (v_day + time '07:35') at time zone 'Asia/Manila'),
         (v_reader, 'T-B', v_b, 'out', (v_day + time '16:40') at time zone 'Asia/Manila');
  select count(*) into v_before from public.rfid_tap_events;

  v_n := public.record_missed_tap_outs(v_run);
  assert v_n >= 1, 'the student who never tapped out is recorded';
  assert exists (select 1 from public.missed_tap_outs where student_id = v_a and school_day = v_day),
    'A did not tap out';
  assert not exists (select 1 from public.missed_tap_outs where student_id = v_b and school_day = v_day),
    'B tapped out';
  assert not exists (select 1 from public.missed_tap_outs where student_id = v_c and school_day = v_day),
    'C never tapped, so there is nothing to report';

  -- No tap event is invented.
  assert (select count(*) from public.rfid_tap_events) = v_before,
    'no automatic tap-out is inserted';

  -- One SMS per student per day, even if the job runs again.
  perform public.record_missed_tap_outs(v_run);
  assert (select count(*) from public.sms_outbox
           where kind = 'no_tap_out'
             and related_id = md5(v_a::text || '|no_tap_out|' || v_day::text)::uuid) = 1,
    'a second run does not text again';
  assert (select message from public.sms_outbox
           where kind = 'no_tap_out'
             and related_id = md5(v_a::text || '|no_tap_out|' || v_day::text)::uuid)
         like '%did not tap out today.',
    'the SMS says the student did not tap out today';
  assert (select count(*) from public.missed_tap_outs
           where student_id = v_a and school_day = v_day) = 1;

  -- A late real tap-out (a replay after the kiosk was offline) replaces the
  -- "did not tap out" record.
  insert into public.rfid_tap_events (reader_id, rfid_uid, student_id, tap_direction, tapped_at)
  values (v_reader, 'T-A', v_a, 'out', (v_day + time '16:00') at time zone 'Asia/Manila');
  assert not exists (select 1 from public.missed_tap_outs
                      where student_id = v_a and school_day = v_day),
    'a late real tap-out removes the did-not-tap-out record';

  -- No automatic tap-outs remain, the old function and cron job are gone.
  assert not exists (select 1 from public.rfid_tap_events where auto_generated),
    'old automatic tap-outs were converted';
  assert to_regproc('public.auto_tap_out_open_students(timestamptz)') is null,
    'the auto tap-out function is dropped';
  assert not exists (select 1 from cron.job where jobname = 'auto-tap-out-open-students'),
    'the auto tap-out job is unscheduled';
  assert exists (select 1 from cron.job where jobname = 'missed-tap-outs'),
    'the missed tap-out job is scheduled';

  raise notice 'ALL PASSED';
end $$;

rollback;
