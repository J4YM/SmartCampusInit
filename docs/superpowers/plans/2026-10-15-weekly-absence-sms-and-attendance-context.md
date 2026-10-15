# Weekly Absence SMS + Professor Attendance Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attendance becomes per class (subject), guardians get one weekly "absent in these subjects" SMS, and professors see each student's earlier-classes-today outcomes (with the professor) while taking attendance, with a cleaner tap-in row.

**Architecture:** Add `attendance_records.class_section_id`; reuse the existing `sms_outbox` → `send-sms` pipeline with a new weekly `pg_cron` job; add a read-only repository query for earlier classes that day, surfaced as chips in the attendance matrix's name cell only while in edit mode.

**Tech Stack:** Supabase Postgres (plpgsql, pg_cron), Flutter/Dart (`packages/professor_module`, `lib/data/professor_repository.dart`, `lib/ui/professor_connected_page.dart`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-15-weekly-absence-sms-and-attendance-context-design.md`

## Global Constraints

- Timezone is `Asia/Manila` (UTC+8, no DST); pg_cron runs in UTC → Friday 5:00 PM Manila = cron `0 9 * * 5`.
- Weekly SMS counts `Absent` only (not `Late`, not `Excuse`); no absences → no SMS.
- Idempotency via `sms_outbox unique (kind, related_id)`; kind is `weekly_absence`.
- Guardian number comes only from `students.guardian_contact_no` via existing `queue_sms` (invalid numbers become `skipped`).
- No change to `supabase/functions/send-sms/*` or the kiosk tap flow.
- SQL migrations are idempotent and run in the Supabase SQL Editor (repo convention: `supabase/*.sql`, header comment lists prerequisites).
- Earlier-classes chips are read-only, visible only in attendance edit mode, never in the weekly matrix view mode.
- Status strings in the app are `'Present' | 'Absent' | 'Late' | 'Excuse'`.

## Review Focus

- Student enrolled in only one class today → no earlier chain, no empty chips or layout jump.
- Earlier class on the same day has no attendance recorded yet → chip reads "Not recorded", never "Absent".
- Two classes starting at the same time or missing meeting times → ordered deterministically, never crash.
- Legacy rows with `class_section_id is null` → ignored by per-class views, reported as "a class" in the SMS.
- Week with 30+ absent subjects for one student → SMS truncated with "…and N more", still one row.
- Re-running the weekly job (or cron firing twice) → no duplicate SMS rows.
- Guardian number missing/invalid → row is `skipped` with a reason, job does not fail for other students.

## File Structure

- Create `supabase/add_attendance_per_class_section.sql` — column, backfill, unique key, index.
- Create `supabase/add_weekly_absence_sms.sql` — setting column, `queue_weekly_absence_sms`, cron job.
- Create `supabase/test_attendance_and_weekly_sms.sql` — rollback-only SQL assertions.
- Modify `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart` — `classSectionId` on section model, `EarlierClassStatus`, chips/pill UI, focused-date state, new callback.
- Modify `lib/data/professor_repository.dart` — class-section aware reads/writes, `fetchEarlierClassesToday`, pure helper `groupEarlierClasses`.
- Modify `lib/ui/professor_connected_page.dart` — pass class section ids, wire callback.
- Create `test/professor_earlier_classes_test.dart` — helper + widget tests.

---

### Task 1: Per-class attendance migration

**Files:**
- Create: `supabase/add_attendance_per_class_section.sql`
- Create: `supabase/test_attendance_and_weekly_sms.sql` (section A)

**Interfaces:**
- Produces: column `public.attendance_records.class_section_id uuid null`; unique key `(student_id, section_id, class_section_id, session_date)` NULLS NOT DISTINCT.

- [ ] **Step 1: Write the failing test** — create `supabase/test_attendance_and_weekly_sms.sql` with section A (everything runs inside `begin; … rollback;`):

```sql
-- Run AFTER add_attendance_per_class_section.sql and add_weekly_absence_sms.sql.
-- Rollback-only: leaves no data behind. Every `do` block raises on failure.
begin;

-- A. attendance_records has class_section_id and the new unique key.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'attendance_records'
       and column_name = 'class_section_id'
  ) then
    raise exception 'FAIL A1: attendance_records.class_section_id missing';
  end if;

  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (student_id, section_id, session_date)'
  ) then
    raise exception 'FAIL A2: old unique (student_id, section_id, session_date) still present';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) like '%class_section_id%session_date%'
  ) then
    raise exception 'FAIL A3: new unique key missing';
  end if;
end $$;

rollback;
```

- [ ] **Step 2: Run it to verify it fails** — paste into the SQL Editor. Expected: `FAIL A1: attendance_records.class_section_id missing`.

- [ ] **Step 3: Write the migration** `supabase/add_attendance_per_class_section.sql`:

```sql
-- Attendance per class (subject), not just per section.
--
-- attendance_records was unique on (student_id, section_id, session_date), so a
-- section with several subjects could hold only one status per day. This adds
-- class_section_id (class_sections already carries subject + professor), so
-- "absent in which subject" and "earlier classes today" are answerable.
--
-- Legacy rows: backfilled where the section has exactly ONE class_sections
-- row. Rows in sections with several classes keep class_section_id = null;
-- they stay in the table (and in term archives) but per-class views ignore
-- them and the weekly SMS reports them as "a class".
--
-- Run in Supabase SQL Editor after add_professor_module_schema.sql and
-- add_subjects_enrollments_schema.sql. Idempotent.

alter table public.attendance_records
  add column if not exists class_section_id uuid
    references public.class_sections(id) on delete cascade;

-- Backfill: sections with exactly one class_sections row.
update public.attendance_records ar
   set class_section_id = one.id
  from (
    select section_id, (array_agg(id))[1] as id
      from public.class_sections
     group by section_id
    having count(*) = 1
  ) one
 where ar.class_section_id is null
   and ar.section_id = one.section_id;

-- Drop the old (student_id, section_id, session_date) unique constraint
-- whatever its auto-generated name is.
do $$
declare
  c record;
begin
  for c in
    select conname
      from pg_constraint
     where conrelid = 'public.attendance_records'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (student_id, section_id, session_date)'
  loop
    execute format('alter table public.attendance_records drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.attendance_records
  drop constraint if exists attendance_records_student_class_date_key;
alter table public.attendance_records
  add constraint attendance_records_student_class_date_key
  unique nulls not distinct (student_id, section_id, class_section_id, session_date);

create index if not exists attendance_records_class_date_idx
  on public.attendance_records (class_section_id, session_date);
```

- [ ] **Step 4: Run migration, then re-run the test** — Expected: no exception (the block completes, then rollback).

- [ ] **Step 5: Commit**

```bash
git add supabase/add_attendance_per_class_section.sql supabase/test_attendance_and_weekly_sms.sql
git commit -m "feat: add per-class attendance records migration"
```

---

### Task 2: Weekly absence SMS

**Files:**
- Create: `supabase/add_weekly_absence_sms.sql`
- Modify: `supabase/test_attendance_and_weekly_sms.sql` (append section B before the final `rollback;` — move the `rollback;` to the end)

**Interfaces:**
- Consumes: `public.queue_sms(p_kind text, p_student_id uuid, p_related_id uuid, p_message text)`, `public.sms_student_name(uuid)`, `public.sms_settings`, `attendance_records.class_section_id`.
- Produces: `public.queue_weekly_absence_sms(p_week_start date default null) returns int` (number of SMS queued); `sms_settings.weekly_absence_enabled boolean`.

- [ ] **Step 1: Write the failing test** — append to the test file, before `rollback;`:

```sql
-- B. Weekly absence SMS: grouping, idempotency, no-absence week, settings gate.
do $$
declare
  v_student uuid;
  v_cs1 uuid;
  v_cs2 uuid;
  v_section uuid;
  v_week date := date '2030-01-07'; -- a Monday far from real data
  v_n int;
  v_msg text;
begin
  select s.id, s.section_id into v_student, v_section
    from public.students s
   where s.section_id is not null
   limit 1;
  if v_student is null then raise exception 'FAIL B0: no student with a section to test with'; end if;

  select id into v_cs1 from public.class_sections where section_id = v_section limit 1;
  select id into v_cs2 from public.class_sections
   where section_id = v_section and id <> v_cs1 limit 1;
  if v_cs1 is null then raise exception 'FAIL B0: section has no class_sections'; end if;

  -- 2 absences in cs1, 1 in cs2 (or a 3rd date in cs1 if the section has one class)
  insert into public.attendance_records (student_id, section_id, class_section_id, session_date, status)
  values (v_student, v_section, v_cs1, v_week,     'Absent'),
         (v_student, v_section, v_cs1, v_week + 1, 'Absent'),
         (v_student, v_section, coalesce(v_cs2, v_cs1), v_week + 2, 'Absent'),
         (v_student, v_section, v_cs1, v_week + 3, 'Late');

  v_n := public.queue_weekly_absence_sms(v_week);
  if v_n < 1 then raise exception 'FAIL B1: expected >= 1 SMS queued, got %', v_n; end if;

  select message into v_msg from public.sms_outbox
   where kind = 'weekly_absence' and student_id = v_student
   order by created_at desc limit 1;
  if v_msg is null then raise exception 'FAIL B2: no weekly_absence row'; end if;
  if v_msg not like '%×%' then raise exception 'FAIL B3: message lacks counts: %', v_msg; end if;
  if v_msg like '%Late%' then raise exception 'FAIL B4: Late must not be reported: %', v_msg; end if;

  -- Idempotent re-run.
  if public.queue_weekly_absence_sms(v_week) <> 0 then
    raise exception 'FAIL B5: second run queued duplicates';
  end if;

  -- A week with no absences queues nothing.
  if public.queue_weekly_absence_sms(date '2030-03-04') <> 0 then
    raise exception 'FAIL B6: empty week queued SMS';
  end if;

  -- Disabled setting queues nothing.
  update public.sms_settings set weekly_absence_enabled = false where id;
  delete from public.sms_outbox where kind = 'weekly_absence' and student_id = v_student;
  if public.queue_weekly_absence_sms(v_week) <> 0 then
    raise exception 'FAIL B7: disabled setting still queued SMS';
  end if;
end $$;
```

- [ ] **Step 2: Run to verify it fails** — Expected: `function public.queue_weekly_absence_sms(date) does not exist`.

- [ ] **Step 3: Write the migration** `supabase/add_weekly_absence_sms.sql`:

```sql
-- Weekly parent SMS: which subjects the student was marked ABSENT in this week.
--
-- Runs Fridays 5:00 PM Asia/Manila (pg_cron, UTC: 09:00). Covers Mon-Sat of the
-- current week. One SMS per student per week through the existing sms_outbox /
-- send-sms pipeline (see add_sms_alerts_schema.sql); queue_sms resolves and
-- validates the guardian number. Students with no absences get nothing.
--
-- Run in Supabase SQL Editor after add_sms_alerts_schema.sql and
-- add_attendance_per_class_section.sql. Idempotent.

alter table public.sms_settings
  add column if not exists weekly_absence_enabled boolean not null default true;

create or replace function public.queue_weekly_absence_sms(
  p_week_start date default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.sms_settings;
  v_week date;
  v_label text;
  v_before int;
  v_after int;
  r record;
  v_items text[];
  v_msg text;
  v_listed text;
  v_i int;
  v_prefix text;
  v_max_len constant int := 300;
begin
  select * into s from public.sms_settings where id;
  if not coalesce(s.weekly_absence_enabled, true) then
    return 0;
  end if;

  -- Monday of the given (or current Manila) week.
  v_week := date_trunc(
    'week',
    coalesce(p_week_start, (now() at time zone 'Asia/Manila')::date)
  )::date;
  v_label := to_char(v_week, 'FMMon FMDD') || '–' || to_char(v_week + 5, 'FMMon FMDD');

  select count(*) into v_before
    from public.sms_outbox where kind = 'weekly_absence';

  for r in
    select t.student_id,
           array_agg(t.subject || ' ×' || t.n order by t.subject) as items
      from (
        select ar.student_id,
               coalesce(nullif(btrim(sub.title), ''), 'a class') as subject,
               count(*) as n
          from public.attendance_records ar
          left join public.class_sections cs on cs.id = ar.class_section_id
          left join public.subjects sub on sub.id = cs.subject_id
         where ar.status::text = 'Absent'
           and ar.session_date between v_week and v_week + 5
         group by ar.student_id, coalesce(nullif(btrim(sub.title), ''), 'a class')
      ) t
     group by t.student_id
  loop
    v_prefix := coalesce(s.school_name, 'STI Baliuag') || ': Weekly absences for '
      || public.sms_student_name(r.student_id) || ' (' || v_label || '): ';

    v_items := r.items;
    v_listed := '';
    for v_i in 1 .. array_length(v_items, 1) loop
      if length(v_prefix || v_listed || v_items[v_i]) > v_max_len and v_i > 1 then
        v_listed := v_listed || ' …and ' || (array_length(v_items, 1) - v_i + 1) || ' more';
        exit;
      end if;
      v_listed := v_listed || case when v_i > 1 then ', ' else '' end || v_items[v_i];
    end loop;

    v_msg := v_prefix || v_listed || '.';

    perform public.queue_sms(
      'weekly_absence',
      r.student_id,
      md5(r.student_id::text || '|weekly_absence|' || v_week::text)::uuid,
      v_msg
    );

  end loop;

  -- queue_sms is `on conflict do nothing`, so the number of NEW rows is the
  -- difference in total weekly_absence rows across the run.
  select count(*) into v_after
    from public.sms_outbox where kind = 'weekly_absence';

  return v_after - v_before;
exception when others then
  raise warning 'queue_weekly_absence_sms failed: %', sqlerrm;
  return 0;
end;
$$;

revoke all on function public.queue_weekly_absence_sms(date)
  from public, anon, authenticated;
grant execute on function public.queue_weekly_absence_sms(date) to service_role;

-- Fridays 5:00 PM Manila = 09:00 UTC.
select cron.schedule(
  'weekly-absence-sms',
  '0 9 * * 5',
  $$select public.queue_weekly_absence_sms();$$
);
```

- [ ] **Step 4: Run migration and test** — Expected: no exception. If B5 fails, the delta logic is wrong.

- [ ] **Step 5: Commit**

```bash
git add supabase/add_weekly_absence_sms.sql supabase/test_attendance_and_weekly_sms.sql
git commit -m "feat: add weekly absence SMS job"
```

---

### Task 3: Class-section aware attendance reads and writes

**Files:**
- Modify: `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart:31-59` (`ProfessorSectionModel`)
- Modify: `lib/data/professor_repository.dart:48-113, 176-390`
- Modify: `lib/ui/professor_connected_page.dart:137-241`

**Interfaces:**
- Produces:
  - `ProfessorSectionModel.classSectionId` (`final String? classSectionId`, constructor param, `fromJson` key `class_section_id`, `toJson` key `class_section_id`).
  - `ProfessorRepository.fetchAttendanceSummary(String sectionId, {DateTime? date, String? classSectionId})`
  - `ProfessorRepository.fetchStudentAttendance(String sectionId, {String? classSectionId})`
  - `ProfessorRepository.fetchAttendanceCells(String sectionId, {String? classSectionId})`
  - `ProfessorRepository.submitAttendance(String sectionId, Map<String,String> statusByStudentId, {required String recordedBy, DateTime? date, String? classSectionId})`
  - Semantics: when `classSectionId != null`, reads add `.eq('class_section_id', classSectionId)` and writes include `'class_section_id'` and `onConflict: 'student_id,section_id,class_section_id,session_date'`. When null, behavior is unchanged (mock/legacy).

- [ ] **Step 1: Write the failing test** — create `test/professor_earlier_classes_test.dart` with a model test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

void main() {
  test('ProfessorSectionModel round-trips classSectionId', () {
    const model = ProfessorSectionModel(
      id: 's1',
      name: 'BSIT 3A',
      studentCount: 30,
      classSectionId: 'c1',
    );
    final back = ProfessorSectionModel.fromJson(model.toJson());
    expect(back.classSectionId, 'c1');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/professor_earlier_classes_test.dart`
Expected: FAIL — `classSectionId` isn't a parameter.

- [ ] **Step 3: Implement**
  1. In `ProfessorSectionModel` add `this.classSectionId` to the constructor, `final String? classSectionId;`, `class_section_id` in `fromJson` and `toJson`.
  2. In `fetchAssignedSections`, change the select to `'id, subjects ( id, title ), sections ( id, name )'`, carry `row['id'] as String` into the record as `classSectionId`, and pass `classSectionId:` to `ProfessorSectionModel`.
  3. In the four repo methods above add the optional `classSectionId` parameter. Reads: `query = classSectionId == null ? query : query.eq('class_section_id', classSectionId)`. In `submitAttendance`, add `if (classSectionId != null) 'class_section_id': classSectionId` to each row map and switch `onConflict` per the Interfaces block.
  4. In `fetchStudentAttendance`, when `classSectionId != null`, limit `_fetchEnrolledStudentIds` to that single class (`.eq('id', classSectionId)` on `class_sections`) while keeping regular `students.section_id` members.
  5. In `professor_connected_page.dart` pass `classSectionId: shown.classSectionId` in `_load`, `section.classSectionId` in `_onSectionSelected` and `_submitAttendance`.
  6. Selection identity: `_selectedSectionId` and `_subjectContaining` currently match on `section.id`, which collides when one section appears under several subjects. Where those compare `s.id == …`, compare `(s.classSectionId ?? s.id)` instead, and store `section.classSectionId ?? section.id` in `_selectedSectionId`.

- [ ] **Step 4: Run tests and analyzer**

Run: `flutter test test/professor_earlier_classes_test.dart; flutter analyze lib/data/professor_repository.dart lib/ui/professor_connected_page.dart packages/professor_module`
Expected: PASS, no new analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add packages/professor_module lib/data/professor_repository.dart lib/ui/professor_connected_page.dart test/professor_earlier_classes_test.dart
git commit -m "feat: make attendance reads and writes class-section aware"
```

---

### Task 4: Earlier classes today query

**Files:**
- Modify: `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart` (add `EarlierClassStatus` next to `AttendanceCellModel`, ~line 294)
- Modify: `lib/data/professor_repository.dart` (add method + top-level helper after `fetchAttendanceCells`)
- Test: `test/professor_earlier_classes_test.dart`

**Interfaces:**
- Produces:
  - `class EarlierClassStatus { const EarlierClassStatus({required this.subjectName, required this.professorName, required this.startTime, required this.status}); final String subjectName; final String professorName; final String startTime; /* 'HH:MM' */ final AttendanceStatus status; }` — `status == AttendanceStatus.none` means "not recorded".
  - `Map<String, List<EarlierClassStatus>> groupEarlierClasses({required List<Map<String, dynamic>> classes, required List<Map<String, dynamic>> records, required List<String> studentIds})` — top-level, pure. `classes` rows: `{id, subject_title, professor_name, start_time}`; `records` rows: `{student_id, class_section_id, status}`. Returns per student the classes ordered by `start_time` then `subject_title`, with `none` where the student has no record for that class.
  - `ProfessorRepository.fetchEarlierClassesToday({required List<String> studentIds, required DateTime date, required String classSectionId}) -> Future<Map<String, List<EarlierClassStatus>>>`; returns `const {}` on any failure.

- [ ] **Step 1: Write the failing tests** (append to the test file; `groupEarlierClasses` is exported from `lib/data/professor_repository.dart`, import it with the repo's package name — check `pubspec.yaml` `name:` and use `package:<name>/data/professor_repository.dart`):

```dart
  group('groupEarlierClasses', () {
    final classes = [
      {'id': 'b', 'subject_title': 'PE', 'professor_name': 'Reyes', 'start_time': '10:00'},
      {'id': 'a', 'subject_title': 'Math', 'professor_name': 'Cruz', 'start_time': '08:00'},
    ];

    test('orders by start time and maps status', () {
      final result = groupEarlierClasses(
        classes: classes,
        records: [
          {'student_id': 's1', 'class_section_id': 'a', 'status': 'Present'},
          {'student_id': 's1', 'class_section_id': 'b', 'status': 'Absent'},
        ],
        studentIds: ['s1'],
      );
      expect(result['s1']!.map((e) => e.subjectName), ['Math', 'PE']);
      expect(result['s1']![0].status, AttendanceStatus.present);
      expect(result['s1']![1].status, AttendanceStatus.absent);
    });

    test('unrecorded class is none, not absent', () {
      final result = groupEarlierClasses(
        classes: classes,
        records: const [],
        studentIds: ['s1'],
      );
      expect(result['s1']!.every((e) => e.status == AttendanceStatus.none), isTrue);
    });

    test('same start time is ordered by subject title deterministically', () {
      final tie = [
        {'id': 'x', 'subject_title': 'Zed', 'professor_name': 'P', 'start_time': '08:00'},
        {'id': 'y', 'subject_title': 'Alpha', 'professor_name': 'Q', 'start_time': '08:00'},
      ];
      final result = groupEarlierClasses(
        classes: tie, records: const [], studentIds: ['s1']);
      expect(result['s1']!.map((e) => e.subjectName), ['Alpha', 'Zed']);
    });

    test('no earlier classes yields empty map entries', () {
      final result = groupEarlierClasses(
        classes: const [], records: const [], studentIds: ['s1']);
      expect(result['s1'] ?? const [], isEmpty);
    });
  });
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/professor_earlier_classes_test.dart`. Expected: FAIL, `groupEarlierClasses` undefined.

- [ ] **Step 3: Implement**

```dart
/// Pure grouping used by [ProfessorRepository.fetchEarlierClassesToday].
Map<String, List<EarlierClassStatus>> groupEarlierClasses({
  required List<Map<String, dynamic>> classes,
  required List<Map<String, dynamic>> records,
  required List<String> studentIds,
}) {
  final ordered = [...classes]..sort((a, b) {
      final byTime =
          (a['start_time'] as String).compareTo(b['start_time'] as String);
      return byTime != 0
          ? byTime
          : (a['subject_title'] as String).compareTo(b['subject_title'] as String);
    });
  final statusByKey = <String, String?>{
    for (final r in records)
      '${r['student_id']}|${r['class_section_id']}': r['status'] as String?,
  };
  return {
    for (final studentId in studentIds)
      studentId: [
        for (final c in ordered)
          EarlierClassStatus(
            subjectName: c['subject_title'] as String,
            professorName: c['professor_name'] as String,
            startTime: c['start_time'] as String,
            status: AttendanceStatus.fromValue(
                statusByKey['$studentId|${c['id']}']),
          ),
      ],
  };
}
```

Repository method (add inside `ProfessorRepository`):

```dart
  static const _dayCodes = ['M', 'T', 'W', 'TH', 'F', 'S'];

  /// For each student in [studentIds]: every class that meets on [date]'s
  /// weekday, starts BEFORE [classSectionId]'s meeting, and that the student
  /// is enrolled in or belongs to by home section — with the status recorded
  /// that day (`none` when not recorded). Empty on any failure.
  Future<Map<String, List<EarlierClassStatus>>> fetchEarlierClassesToday({
    required List<String> studentIds,
    required DateTime date,
    required String classSectionId,
  }) async {
    if (studentIds.isEmpty || date.weekday > 6) return const {};
    try {
      final day = _dayCodes[date.weekday - 1];
      final current = await _client
          .from('class_section_meetings')
          .select('start_time')
          .eq('class_section_id', classSectionId)
          .eq('day', day)
          .order('start_time')
          .limit(1);
      final currentRows = current as List<dynamic>;
      if (currentRows.isEmpty) return const {};
      final currentStart =
          (currentRows.first as Map<String, dynamic>)['start_time'] as String;

      final earlier = await _client
          .from('class_section_meetings')
          .select(
              'start_time, class_section_id, class_sections ( id, subjects ( title ), profiles ( first_name, last_name ) )')
          .eq('day', day)
          .lt('start_time', currentStart)
          .neq('class_section_id', classSectionId);

      final classes = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final raw in earlier as List<dynamic>) {
        final row = raw as Map<String, dynamic>;
        final cs = row['class_sections'] as Map<String, dynamic>?;
        if (cs == null) continue;
        final id = cs['id'] as String;
        if (!seen.add(id)) continue;
        classes.add({
          'id': id,
          'subject_title':
              ((cs['subjects'] as Map<String, dynamic>?)?['title'] as String?) ??
                  'Class',
          'professor_name': _fullName(cs['profiles'] as Map<String, dynamic>?),
          'start_time': (row['start_time'] as String).substring(0, 5),
        });
      }
      if (classes.isEmpty) return const {};

      final records = await _client
          .from('attendance_records')
          .select('student_id, class_section_id, status')
          .inFilter('student_id', studentIds)
          .inFilter('class_section_id', [for (final c in classes) c['id']])
          .eq('session_date', _dateOnly(date));

      return groupEarlierClasses(
        classes: classes,
        records: [
          for (final r in records as List<dynamic>) r as Map<String, dynamic>,
        ],
        studentIds: studentIds,
      );
    } catch (_) {
      return const {};
    }
  }
```

> Verify while implementing: the `class_sections → profiles` embed name. `class_sections.professor_id` references `profiles(id)`, so the embed may need the FK hint `profiles!class_sections_professor_id_fkey ( first_name, last_name )` — check how `registrar_repository.dart:621-630` embeds the professor and copy that exact syntax. Also restrict to classes the student actually attends: after fetching, keep only classes where the student appears in `enrollments` (Active) for that class or whose `sections.id` equals the student's `section_id`; the helper's pure signature stays unchanged — filter `classes` per student before calling it if a class doesn't apply, and add a test case for it.

- [ ] **Step 4: Run tests** — `flutter test test/professor_earlier_classes_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/professor_module lib/data/professor_repository.dart test/professor_earlier_classes_test.dart
git commit -m "feat: add earlier-classes-today attendance query"
```

---

### Task 5: Tap-in pill and earlier-class chips UI

**Files:**
- Modify: `packages/professor_module/lib/pages/dashboard/professor_dashboard_page.dart` — `_KioskTapIndicator` (~2887), `_AttendanceMatrix` name cell (~2692-2729), dashboard state (~618-660), `ProfessorDashboardPage` fields (~556).
- Modify: `lib/ui/professor_connected_page.dart` (~453, near `onSubmitAttendance:`).
- Test: `test/professor_earlier_classes_test.dart`

**Interfaces:**
- Consumes: `EarlierClassStatus`, `ProfessorRepository.fetchEarlierClassesToday`.
- Produces:
  - `ProfessorDashboardPage.onFetchEarlierClasses`: `Future<Map<String, List<EarlierClassStatus>>> Function(ProfessorSectionModel section, DateTime date, List<String> studentIds)?`
  - `_AttendanceMatrix` new params: `Map<String, List<EarlierClassStatus>> earlierByStudent` (default `const {}`), `bool showEarlier`.
  - Public-for-test widget `@visibleForTesting class TapInPill extends StatelessWidget { const TapInPill({super.key, required this.tapInAt}); final DateTime? tapInAt; }` replacing `_KioskTapIndicator`; and `@visibleForTesting class EarlierClassChips extends StatelessWidget { const EarlierClassChips({super.key, required this.items}); final List<EarlierClassStatus> items; }`.

- [ ] **Step 1: Write the failing widget tests** (append):

```dart
  testWidgets('TapInPill shows time when tapped, otherwise "No tap yet"',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TapInPill(tapInAt: DateTime(2030, 1, 7, 8, 2)),
          const TapInPill(tapInAt: null),
        ]),
      ),
    ));
    expect(find.text('Tapped in 8:02 AM'), findsOneWidget);
    expect(find.text('No tap yet'), findsOneWidget);
  });

  testWidgets('EarlierClassChips renders one chip per class and Not recorded',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EarlierClassChips(items: const [
          EarlierClassStatus(
              subjectName: 'Math',
              professorName: 'Cruz',
              startTime: '08:00',
              status: AttendanceStatus.present),
          EarlierClassStatus(
              subjectName: 'PE',
              professorName: 'Reyes',
              startTime: '10:00',
              status: AttendanceStatus.none),
        ]),
      ),
    ));
    expect(find.textContaining('Math'), findsOneWidget);
    expect(find.textContaining('Present'), findsOneWidget);
    expect(find.textContaining('Not recorded'), findsOneWidget);
  });

  testWidgets('EarlierClassChips renders nothing for an empty list',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EarlierClassChips(items: [])),
    ));
    expect(find.byType(Chip), findsNothing);
    expect(tester.getSize(find.byType(EarlierClassChips)).height, 0);
  });
```

- [ ] **Step 2: Run to verify they fail** — `flutter test test/professor_earlier_classes_test.dart`. Expected: FAIL, `TapInPill`/`EarlierClassChips` undefined.

- [ ] **Step 3: Implement**
  1. Rename `_KioskTapIndicator` → `TapInPill` (annotate `@visibleForTesting`, export from `professor_module.dart` if the test import needs it). Restyle: a rounded pill (`Container`, radius 999, 8h/2v padding, background `color.withOpacity(0.12)`), icon 12px, label `Tapped in ${_time(t)}` or `No tap yet`, font 10.5/w600. Keep `_time` formatting (`8:02 AM`).
  2. Add `EarlierClassChips`: `if (items.isEmpty) return const SizedBox.shrink();` else a `Wrap(spacing: 4, runSpacing: 4)` of small chips (height ≈ 18, font 10) each labelled `'${startTime} ${subjectName} · ${status label}'` where label is `Not recorded` for `none`, else `status.value` (map `Excuse` → `Excused`); chip color from `status.color` at 0.12 opacity with text in `status.color`; wrap each in `Tooltip(message: '$professorName · $subjectName · $startTime')`.
  3. In the name cell, render `TapInPill` then, if `showEarlier`, `EarlierClassChips(items: earlierByStudent[record.id] ?? const [])`. Row height: make `_rowHeight` a per-row value — `_rowHeight` normally, and `_rowHeight + 22` for a row when `showEarlier` and that student has chips (apply identically in the name column and the date-cells column so rows stay aligned).
  4. State: in `_ProfessorDashboardPageState` add `DateTime? _focusedDate;` and `Map<String, List<EarlierClassStatus>> _earlierByStudent = const {};`. Set `_focusedDate` in `_handleCellTap`/mark-all handlers to the tapped date, and when edit mode starts default it to today if today is in `_datesInWeek`, else null. Whenever edit mode is on and `_focusedDate`/`activeSection` changes, call `widget.onFetchEarlierClasses?.call(activeSection!, _focusedDate!, [for (final r in studentAttendance) r.id])` and store the result (ignore a stale result if the focused date changed meanwhile). On discard/save (edit mode off) reset `_earlierByStudent = const {}` and `_focusedDate = null`. Pass `showEarlier: _editMode && _focusedDate != null` to `_AttendanceMatrix`.
  5. In `professor_connected_page.dart` supply `onFetchEarlierClasses: repo == null ? null : (section, date, ids) async => section.classSectionId == null ? const {} : repo.fetchEarlierClassesToday(studentIds: ids, date: date, classSectionId: section.classSectionId!)`.

- [ ] **Step 4: Run tests, analyzer, and a manual check**

Run: `flutter test test/professor_earlier_classes_test.dart; flutter analyze packages/professor_module lib`
Expected: PASS, no new analyzer errors.
Manual: `flutter run`, sign in as a professor with two classes on the same day, open Attendance, enter edit mode, tap a cell in today's column → chips appear under students; leave edit mode → chips disappear; confirm rows stay aligned between the name column and date columns and the tap pill reads correctly in light and dark themes.

- [ ] **Step 5: Commit**

```bash
git add packages/professor_module lib/ui/professor_connected_page.dart test/professor_earlier_classes_test.dart
git commit -m "feat: show earlier classes today and refined tap-in pill in attendance"
```

---

## Self-Review

- **Spec coverage:** §1 data → Task 1; §2 earlier classes → Tasks 3–5; §3 tap-in row → Task 5; §4 weekly SMS → Task 2. Testing section → SQL test file (Tasks 1–2) and Dart tests (Tasks 3–5).
- **Deviation from spec, deliberate:** "earlier" ordering uses `class_section_meetings` for the date's weekday (the schedule source of truth) rather than `class_sections.start_time`, because meetings are per-day.
- **Open decision made in this plan:** the "selected day" in a weekly matrix is the date column the professor last tapped in edit mode (default: today if visible). Confirm or change before Task 5.
- **Known limitation:** legacy multi-class-section rows with `class_section_id = null` are hidden from per-class views (still in DB and still counted in the SMS as "a class").
