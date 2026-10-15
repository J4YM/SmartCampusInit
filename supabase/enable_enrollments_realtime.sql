-- Lets the Professor dashboard react instantly when the Registrar enrolls or
-- drops a student (Student Records > View Subjects > Enroll in Subject).
-- Idempotent: safe to re-run.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'enrollments'
  ) then
    alter publication supabase_realtime add table public.enrollments;
  end if;
end $$;
