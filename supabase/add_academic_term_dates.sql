-- Academic year start and end dates.
--
-- academic_terms.started_at / closed_at record WHEN the Admin migrated the
-- system (a timestamp). The school calendar is a different thing: the date the
-- academic year/semester actually begins and ends. These two columns hold it,
-- set by the Admin when starting a term (and editable afterwards).
--
-- Run in Supabase SQL Editor after add_academic_term_migration.sql. Idempotent.

alter table public.academic_terms
  add column if not exists starts_on date,
  add column if not exists ends_on date;

do $$
begin
  alter table public.academic_terms
    add constraint academic_terms_dates_order
    check (starts_on is null or ends_on is null or ends_on > starts_on);
exception when duplicate_object then null;
end $$;
