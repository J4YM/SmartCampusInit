-- Fixes `apply_sanction_progression()` (a BEFORE INSERT trigger on
-- `student_violations`, previously created directly in Supabase — not
-- checked into this repo until now): it used to overwrite a repeat Minor
-- offender's new violation's `offense_id` with an arbitrary, unrelated
-- Major_A offense (in practice, always "Cheating during quizzes, exams, or
-- graded activities" — whichever Major_A row happened to have the
-- earliest created_at), losing the actual violation the student committed.
--
-- The real, specific offense the student committed must always be what's
-- recorded — so this version leaves `offense_id` untouched and instead
-- flags the row via the existing `is_escalated` column (already
-- surfaced in the DO dashboard as DisciplineCaseModel.isEscalated), with
-- a note in `penalty_imposed` for context. Detection logic (3+ prior
-- Minor violations) is unchanged.
--
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.

create or replace function public.apply_sanction_progression()
returns trigger
language plpgsql
as $function$
declare
  v_minor_count int;
begin
  if (select category from public.handbook_offenses where id = new.offense_id) <> 'Minor' then
    return new;
  end if;

  select count(*) into v_minor_count
  from public.student_violations sv
  join public.handbook_offenses ho on ho.id = sv.offense_id
  where sv.student_id = new.student_id and ho.category = 'Minor';

  if v_minor_count >= 3 then
    new.is_escalated := true;
    new.penalty_imposed := concat_ws(
      ' | ',
      nullif(new.penalty_imposed, ''),
      'Flagged for escalation: 3 or more prior Minor violations on record'
    );
  end if;

  return new;
end;
$function$;
