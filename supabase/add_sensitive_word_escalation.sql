-- Sensitive-word triggers: a violation whose free-text notes or description
-- mention a sensitive topic (Sexual Assault, Violence, …) is escalated
-- automatically, no matter which screen filed it.
--
-- Why in the database: violations come in through several paths (the kiosk's
-- submit_admission_slip RPC, the Professor's Conduct Report, the Security
-- report, Discipline Officer edits). One BEFORE INSERT/UPDATE trigger on
-- `student_violations` covers all of them, the same way
-- `apply_sanction_progression()` (fix_sanction_progression_target_offense.sql)
-- already flags repeat offenders.
--
-- What it does when a keyword matches `incident_notes` (the notes/description
-- the reporter typed) or `penalty_imposed`:
--   * sets `is_escalated = true` — the existing flag that puts the case in the
--     Student Affairs escalated list and the Guidance "Parental Intervention"
--     tab's Escalated Violation History;
--   * records which topics matched in `sensitive_terms` and adds a note to
--     `penalty_imposed` for context (once).
-- It only ever turns escalation ON; it never un-escalates a case.
--
-- The words live in `sensitive_keywords`, so staff can add or retire topics
-- without a deploy (insert / update `active`). Matching is case-insensitive
-- on whole words; a keyword may be a phrase ("sexual assault").
--
-- Run in Supabase SQL Editor after add_discipline_officer_schema.sql and
-- fix_sanction_progression_target_offense.sql. Idempotent.

create table if not exists public.sensitive_keywords (
  term text primary key,
  -- Free-form label shown in the case note, e.g. 'Sexual misconduct'.
  topic text not null default 'Sensitive',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint sensitive_keywords_term_lower check (term = lower(btrim(term)))
);

alter table public.sensitive_keywords enable row level security;

drop policy if exists "sensitive_keywords_select" on public.sensitive_keywords;
create policy "sensitive_keywords_select" on public.sensitive_keywords
  for select to anon, authenticated using (true);

-- Starter list. Edit freely; re-running never overwrites a row you changed.
insert into public.sensitive_keywords (term, topic) values
  ('sexual assault',     'Sexual misconduct'),
  ('sexually assaulted', 'Sexual misconduct'),
  ('sexual abuse',       'Sexual misconduct'),
  ('sexual harassment',  'Sexual misconduct'),
  ('molest',             'Sexual misconduct'),
  ('molested',           'Sexual misconduct'),
  ('molestation',        'Sexual misconduct'),
  ('rape',               'Sexual misconduct'),
  ('raped',              'Sexual misconduct'),
  ('violence',           'Violence'),
  ('violent',            'Violence'),
  ('assault',            'Violence'),
  ('assaulted',          'Violence'),
  ('physical abuse',     'Violence'),
  ('abuse',              'Abuse'),
  ('abused',             'Abuse'),
  ('weapon',             'Violence'),
  ('stabbing',           'Violence'),
  ('threatened to kill', 'Violence'),
  ('self-harm',          'Welfare'),
  ('suicide',            'Welfare'),
  ('suicidal',           'Welfare')
on conflict (term) do nothing;

alter table public.student_violations
  add column if not exists sensitive_terms text[];

-- Matches whole words / phrases, case-insensitively. Returns the distinct
-- terms found in p_text (empty when none).
create or replace function public.find_sensitive_terms(p_text text)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(k.term order by k.term), '{}'::text[])
    from public.sensitive_keywords k
   where k.active
     and p_text is not null
     and lower(p_text) ~ (
       '(^|[^[:alnum:]])' ||
       regexp_replace(k.term, '([\\.^$*+?()\[\]{}|-])', '\\\1', 'g') ||
       '($|[^[:alnum:]])'
     );
$$;

create or replace function public.escalate_sensitive_violation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_terms text[];
  v_topics text;
begin
  v_terms := public.find_sensitive_terms(
    concat_ws(E'\n', new.incident_notes, new.penalty_imposed)
  );

  if coalesce(array_length(v_terms, 1), 0) = 0 then
    return new;
  end if;

  new.is_escalated := true;
  new.sensitive_terms := v_terms;

  select string_agg(distinct k.topic, ', ' order by k.topic)
    into v_topics
    from public.sensitive_keywords k
   where k.term = any (v_terms);

  if coalesce(new.penalty_imposed, '') not like '%Auto-escalated: sensitive%' then
    new.penalty_imposed := concat_ws(
      ' | ',
      nullif(new.penalty_imposed, ''),
      'Auto-escalated: sensitive topic (' || coalesce(v_topics, 'Sensitive') || ')'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists student_violations_sensitive_escalation on public.student_violations;
create trigger student_violations_sensitive_escalation
  before insert or update of incident_notes, penalty_imposed
  on public.student_violations
  for each row execute function public.escalate_sensitive_violation();

-- Existing open cases get the same treatment once, so nothing already filed
-- slips through. Resolved / archived cases are left alone.
update public.student_violations
   set incident_notes = incident_notes
 where archived_at is null
   and status in ('Pending', 'Under_Investigation')
   and incident_notes is not null;
