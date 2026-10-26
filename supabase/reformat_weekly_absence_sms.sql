-- Clearer layout for the weekly absence SMS.
--
-- The message used to be one run-on line ("STI Baliuag: Weekly absences for
-- Ana Cruz (Oct 19-Oct 24): Math x2, English x1."). It is now a short notice,
-- one subject per line:
--
--   STI Baliuag - Weekly Absence Notice
--   Student: Ana Cruz
--   Week: Oct 19-Oct 24
--   Absences:
--   - Math: 2 absences
--   - English: 1 absence
--   Please contact the school if this is incorrect.
--
-- Still plain ASCII (GSM-7, line feeds included) and capped at 300 characters.
-- Subjects are listed until the next one would not fit; the rest becomes
-- "...and N more". The closing line is dropped only when even the first
-- subject would not fit with it. A very long student name is cut to 40
-- characters so the layout always fits.
--
-- queue_weekly_absence_sms is unchanged: it still passes items as
-- 'Subject xN', which this function turns into "Subject: N absences".
--
-- Run in Supabase SQL Editor after add_weekly_absence_sms.sql. Idempotent.

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
  -- Room for "\n...and 999 more" when more subjects remain.
  v_more_reserve constant int := 16;
  v_footer constant text := E'\nPlease contact the school if this is incorrect.';
  v_prefix text;
  v_lines text := '';
  v_line text;
  v_candidate text;
  v_n int := coalesce(array_length(p_items, 1), 0);
  v_i int;
  v_count text;
  v_use_footer boolean := true;
  v_reserve int;
begin
  v_prefix := coalesce(p_school, 'STI Baliuag') || ' - Weekly Absence Notice'
    || E'\nStudent: ' || left(coalesce(p_name, 'your child'), 40)
    || E'\nWeek: ' || p_label
    || E'\nAbsences:';

  for v_i in 1 .. v_n loop
    v_count := substring(p_items[v_i] from ' x([0-9]+)$');
    v_line := case
      when v_count is null then E'\n- ' || p_items[v_i]
      else E'\n- ' || regexp_replace(p_items[v_i], ' x[0-9]+$', '')
           || ': ' || v_count
           || case when v_count = '1' then ' absence' else ' absences' end
    end;

    -- The footer goes first if it keeps even the first subject out.
    if v_i = 1 and length(v_prefix || v_line || v_footer) > v_max_len then
      v_use_footer := false;
    end if;

    v_candidate := v_lines || v_line;
    v_reserve := case when v_i < v_n then v_more_reserve else 0 end
      + case when v_use_footer then length(v_footer) else 0 end;
    if v_i > 1 and length(v_prefix || v_candidate) + v_reserve > v_max_len then
      v_lines := v_lines || E'\n...and ' || (v_n - v_i + 1) || ' more';
      exit;
    end if;
    v_lines := v_candidate;
  end loop;

  -- Hard cap as a last resort.
  return left(
    v_prefix || v_lines || case when v_use_footer then v_footer else '' end,
    v_max_len);
end;
$$;
