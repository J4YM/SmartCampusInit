-- Lets a person reply to an IT Technician's message straight from the
-- notification popup.
--
-- A technical-issue reply used to create a plain notification with no link
-- back to the report it was about, so the app could show the message but not
-- say which ticket a reply belonged to. This adds that link:
--
--   1. notifications.report_id — the technical issue report the notification
--      is about (null for every other kind of notification).
--   2. add_technical_issue_comment() now stamps it on the notification it
--      creates, in both directions.
--   3. A best-effort backfill for IT replies that already exist.
--
-- The app works without this script (the Reply box just does not appear);
-- run it once in the Supabase SQL Editor to turn replies on. Idempotent.

-- ---------------------------------------------------------------------------
-- 1. The link
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column if not exists report_id uuid
    references public.technical_issue_reports(id) on delete cascade;

create index if not exists notifications_report_id_idx
  on public.notifications (report_id)
  where report_id is not null;

-- ---------------------------------------------------------------------------
-- 2. add_technical_issue_comment — same behaviour as before, plus report_id
-- ---------------------------------------------------------------------------
create or replace function public.add_technical_issue_comment(
  p_report_id uuid,
  p_message text,
  p_author_id uuid,
  p_author_role text
)
returns public.technical_issue_comments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comment public.technical_issue_comments;
  v_reporter_id uuid;
  v_reporter_role text;
begin
  insert into public.technical_issue_comments (
    report_id, author_id, author_role, message
  )
  values (
    p_report_id, p_author_id, p_author_role, p_message
  )
  returning * into v_comment;

  select reported_by, reported_by_role into v_reporter_id, v_reporter_role
    from public.technical_issue_reports
    where id = p_report_id;

  -- IT Technician/Admin replying routes straight back to the original
  -- reporter; the reporter replying broadcasts to IT Technician again.
  -- target_role must be the reporter's ACTUAL role (an Admin can file a
  -- ticket too), or the reply is invisible to the person who reported it.
  -- An Admin who filed the ticket and replies on it is the reporter, so that
  -- goes to IT, not back to themselves.
  if p_author_role = 'IT_Technician'
     or (p_author_role = 'Admin'
         and p_author_id is distinct from v_reporter_id) then
    insert into public.notifications (
      target_role, title, message, user_id, report_id
    )
    values (
      v_reporter_role::app_role,
      'Update on your technical issue report',
      p_message,
      v_reporter_id,
      p_report_id
    );
  else
    insert into public.notifications (
      target_role, title, message, report_id
    )
    values (
      'IT_Technician'::app_role,
      'New reply on a technical issue report',
      p_message,
      p_report_id
    );
  end if;

  return v_comment;
end;
$$;

revoke all on function public.add_technical_issue_comment(
  uuid, text, uuid, text
) from public;
grant execute on function public.add_technical_issue_comment(
  uuid, text, uuid, text
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2b. report_technical_issue — the "New technical issue reported" notification
--     to IT carries the link too, so IT can answer from the bell.
-- ---------------------------------------------------------------------------
create or replace function public.report_technical_issue(
  p_category public.technical_issue_category,
  p_description text,
  p_reporter_id uuid,
  p_reporter_role text,
  p_location text default null
)
returns public.technical_issue_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report public.technical_issue_reports;
begin
  insert into public.technical_issue_reports (
    category, description, location, reported_by, reported_by_role
  )
  values (
    p_category, p_description, p_location, p_reporter_id, p_reporter_role
  )
  returning * into v_report;

  insert into public.notifications (target_role, title, message, report_id)
  values (
    'IT_Technician'::app_role,
    'New technical issue reported',
    p_description,
    v_report.id
  );

  return v_report;
end;
$$;

revoke all on function public.report_technical_issue(
  public.technical_issue_category, text, uuid, text, text
) from public;
grant execute on function public.report_technical_issue(
  public.technical_issue_category, text, uuid, text, text
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Backfill — match each existing "Update on your technical issue report"
--    notification to the IT comment it was made from (same reporter, same
--    text; the newest comment wins when the text repeats).
-- ---------------------------------------------------------------------------
update public.notifications n
set report_id = m.report_id
from (
  select distinct on (r.reported_by, c.message)
         r.reported_by, c.message, c.report_id
  from public.technical_issue_comments c
  join public.technical_issue_reports r on r.id = c.report_id
  where c.author_role in ('IT_Technician', 'Admin')
  order by r.reported_by, c.message, c.created_at desc
) m
where n.report_id is null
  and n.title = 'Update on your technical issue report'
  and n.user_id = m.reported_by
  and n.message = m.message;

-- The same for IT's own side: "New technical issue reported" carries the
-- ticket's description as its message, so match it back to its report (the
-- newest report wins when a description repeats).
update public.notifications n
set report_id = m.id
from (
  select distinct on (description) description, id
  from public.technical_issue_reports
  order by description, created_at desc
) m
where n.report_id is null
  and n.title = 'New technical issue reported'
  and n.message = m.description;
