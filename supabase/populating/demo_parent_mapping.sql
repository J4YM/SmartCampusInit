-- Demo data for showing that each parent maps to THEIR OWN children.
--
-- Requires supabase/add_parent_credentials.sql (and at least 3 students).
-- Run in Supabase SQL Editor. Idempotent: re-running re-links and resets the
-- two demo passwords below, nothing else.
--
--   guardian.two.kids@example.com   / Guardian2026!   -> first TWO students
--       (child switcher appears in the Parent Portal)
--   guardian.one.kid@example.com    / Guardian2026!   -> the THIRD student
--       (sees only that child — never the other two)
--
-- These are fixed, documented demo passwords; real enrollments get a random
-- one-time temporary password instead (issue_parent_credential).

do $$
declare
  v_students uuid[];
  v_two uuid;
  v_one uuid;
begin
  select array_agg(id order by student_number)
    into v_students
    from (
      select id, student_number
        from public.students
       order by student_number
       limit 3
    ) s;

  if v_students is null or array_length(v_students, 1) < 3 then
    raise exception 'Need at least 3 students to seed the parent mapping demo.';
  end if;

  -- Guardian with two children.
  select id into v_two from public.profiles
   where lower(email) = 'guardian.two.kids@example.com' and role = 'Parent';
  if v_two is null then
    v_two := public.create_batch_guardian_account(
      'guardian.two.kids@example.com', 'Two Kids Guardian');
  end if;

  -- Guardian with one child.
  select id into v_one from public.profiles
   where lower(email) = 'guardian.one.kid@example.com' and role = 'Parent';
  if v_one is null then
    v_one := public.create_batch_guardian_account(
      'guardian.one.kid@example.com', 'One Kid Guardian');
  end if;

  -- Links (kept exclusive: a demo guardian never keeps a stale extra child).
  delete from public.parent_student_links where parent_id in (v_two, v_one);
  insert into public.parent_student_links (parent_id, student_id) values
    (v_two, v_students[1]),
    (v_two, v_students[2]),
    (v_one, v_students[3]);

  -- Known demo passwords, no forced change so the demo goes straight in.
  insert into public.parent_credentials (parent_id, email, password_hash, must_change)
  values
    (v_two, 'guardian.two.kids@example.com',
     extensions.crypt('Guardian2026!', extensions.gen_salt('bf')), false),
    (v_one, 'guardian.one.kid@example.com',
     extensions.crypt('Guardian2026!', extensions.gen_salt('bf')), false)
  on conflict (parent_id) do update
    set password_hash = excluded.password_hash,
        must_change = false,
        updated_at = now();
end $$;

-- Show the mapping.
select p.email as guardian_email,
       sp.first_name || ' ' || sp.last_name as child,
       st.student_number
  from public.parent_student_links l
  join public.profiles p on p.id = l.parent_id
  join public.students st on st.id = l.student_id
  join public.profiles sp on sp.id = st.id
 where lower(p.email) in ('guardian.two.kids@example.com',
                          'guardian.one.kid@example.com')
 order by p.email, st.student_number;
