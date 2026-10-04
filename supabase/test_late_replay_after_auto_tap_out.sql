-- Self-cleaning test for fix_late_replay_after_auto_tap_out.sql.
--
-- Run it in the Supabase SQL Editor AFTER the fix. It writes NOTHING permanent:
-- it is one DO block that always ends by raising an error, which makes Postgres
-- roll back everything it did (taps, notifications, the SMS switch). Read the
-- error text at the bottom:
--     "TEST PASSED - everything was rolled back"   -> all good
--     "FAIL: <what went wrong>"                    -> do not rely on the fix
--
-- Safety: SMS are switched off INSIDE the same rolled-back transaction
-- (sms_settings.tap_alerts_enabled), and every tap is dated in 2020, so no
-- parent is texted and no real attendance day is touched. It uses one existing
-- student that has an RFID card and one active reader.
--
-- It needs 2 things to exist: sms_settings (add_sms_alerts_schema.sql) and the
-- auto_tap_out_open_students function from that same file.

do $$
declare
  v_serial text;
  v_uid text;
  v_student uuid;
  v_tap1 uuid;
  v_tap2 uuid;
  v_dir public.rfid_tap_direction;
  v_n int;
  v_auto_n int;
  v_auto_at timestamptz;
  v_out_at timestamptz;
  v_out_auto boolean;
  v_msg text;
begin
  -- No SMS during the test (rolled back with everything else).
  update public.sms_settings set tap_alerts_enabled = false where id;

  select usb_serial into v_serial
    from public.rfid_readers
    where is_active
    order by is_kiosk_reader desc
    limit 1;
  select rfid_uid, id into v_uid, v_student
    from public.students
    where rfid_uid is not null and btrim(rfid_uid) <> ''
    limit 1;
  if v_serial is null or v_student is null then
    raise exception 'FAIL: need one active reader and one student with an RFID card';
  end if;

  -- =========================================================================
  -- A. THE BUG CASE. 2020-03-02: tap in 8:00 AM, cron auto-out at 6:30 PM,
  --    then the real 3:00 PM tap-out arrives late.
  -- =========================================================================
  perform * from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-02 08:00:00+08');
  perform public.auto_tap_out_open_students(timestamptz '2020-03-02 18:30:00+08');

  select count(*), min(e.tapped_at) into v_auto_n, v_auto_at
    from public.rfid_tap_events e
    where e.student_id = v_student and e.auto_generated
      and e.tapped_at between timestamptz '2020-03-02 00:00+08' and timestamptz '2020-03-03 00:00+08';
  if v_auto_n <> 1 then
    raise exception 'FAIL A1: expected exactly 1 auto-generated out, found %', v_auto_n;
  end if;

  select t.tap_id, t.tap_direction into v_tap1, v_dir
    from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-02 15:00:00+08') t;
  if v_dir <> 'out' then
    raise exception 'FAIL A2: late real tap-out came back as %, expected out', v_dir;
  end if;

  select count(*) into v_n
    from public.rfid_tap_events e
    where e.student_id = v_student
      and e.tapped_at between timestamptz '2020-03-02 00:00+08' and timestamptz '2020-03-03 00:00+08';
  if v_n <> 2 then
    raise exception 'FAIL A3: expected 2 rows for the day (in + real out), found %', v_n;
  end if;

  select e.tapped_at, e.auto_generated into v_out_at, v_out_auto
    from public.rfid_tap_events e
    where e.id = v_tap1;
  if v_out_auto or v_out_at <> timestamptz '2020-03-02 15:00:00+08' then
    raise exception 'FAIL A4: the stored out is not the real 3:00 PM tap (auto=%, at=%)', v_out_auto, v_out_at;
  end if;

  select count(*) into v_n
    from public.rfid_tap_events e
    where e.student_id = v_student and e.auto_generated
      and e.tapped_at between timestamptz '2020-03-02 00:00+08' and timestamptz '2020-03-03 00:00+08';
  if v_n <> 0 then
    raise exception 'FAIL A5: the auto-generated out should have been replaced';
  end if;

  -- Replaying the same real tap again (e.g. kiosk crashed before it cleared
  -- its queue) must be harmless: same tap, no new row.
  select t.tap_id into v_tap2
    from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-02 15:00:00+08') t;
  select count(*) into v_n
    from public.rfid_tap_events e
    where e.student_id = v_student
      and e.tapped_at between timestamptz '2020-03-02 00:00+08' and timestamptz '2020-03-03 00:00+08';
  if v_tap2 is distinct from v_tap1 or v_n <> 2 then
    raise exception 'FAIL A6: replaying the same late tap must echo it (tap % vs %, rows %)', v_tap1, v_tap2, v_n;
  end if;

  -- =========================================================================
  -- B. NORMAL FLOW IS UNCHANGED. 2020-03-04: in, out, then a third tap is
  --    refused.
  -- =========================================================================
  select t.tap_direction into v_dir
    from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-04 08:00:00+08') t;
  if v_dir <> 'in' then raise exception 'FAIL B1: first tap of the day was %', v_dir; end if;

  -- a double tap 2 seconds later echoes the same tap
  select t.tap_direction into v_dir
    from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-04 08:00:02+08') t;
  if v_dir <> 'in' then raise exception 'FAIL B2: a 2-second double tap was %, expected the echoed in', v_dir; end if;

  select t.tap_direction into v_dir
    from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-04 09:00:00+08') t;
  if v_dir <> 'out' then raise exception 'FAIL B3: second tap was %, expected out', v_dir; end if;

  begin
    perform * from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-04 10:00:00+08');
    raise exception 'FAIL B4: a third tap in one school day was accepted';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'FAIL B4%' then raise; end if;
    if v_msg <> 'You have already tapped in and out for today.' then
      raise exception 'FAIL B4: wrong refusal message: %', v_msg;
    end if;
  end;

  -- =========================================================================
  -- C. A first tap on a fresh day is still an `in`.
  -- =========================================================================
  -- (2020-03-05: nothing for this student that day.)
  select t.tap_direction into v_dir
    from public.record_rfid_tap(v_serial, v_uid, timestamptz '2020-03-05 08:00:00+08') t;
  if v_dir <> 'in' then raise exception 'FAIL C1: a first tap of a fresh day was %', v_dir; end if;

  raise exception 'TEST PASSED - everything was rolled back';
end;
$$;
