import 'package:dashboard_layout/dashboard_layout.dart' show UploadSpreadsheetButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:scheduling_officer_module/scheduling_officer_module.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _entry = ScheduleEntryModel(
  id: 'cs-1',
  subject: 'Computer Programming 1',
  gradeSection: 'BSIT-1A',
  teacher: 'Ana Cruz',
  room: 'Room 2',
  days: ['Sat'],
  timeRange: '8:00 AM - 9:30 AM',
  subjectId: 'sub-1',
  sectionId: 'sec-1',
  professorId: 'prof-1',
  schoolYear: '2026-2027',
  term: '1st Semester',
  startTime: '08:00',
  endTime: '09:30',
);

Widget _page({
  bool manage = true,
  List<String>? created,
  List<String>? updated,
  List<String>? deleted,
}) {
  return MaterialApp(
    home: SchedulingOfficerDashboardPage(
      officerName: 'Officer',
      existingOfferingsCount: 5,
      scheduleEntries: const [_entry],
      subjectOptions: const [
        SubjectOption(id: 'sub-1', code: 'CITE1003', title: 'Computer Programming 1'),
      ],
      teacherOptions: const [TeacherOption(id: 'prof-1', fullName: 'Ana Cruz')],
      sectionOptions: const [
        SectionOption(id: 'sec-1', name: 'BSIT-1A', yearLevel: 1),
      ],
      roomOptions: const ['Room 1', 'Room 2'],
      onCreateClassSchedule: manage
          ? ({
              required subjectId,
              required professorId,
              required sectionId,
              required schoolYear,
              required term,
              required room,
              required days,
              required startTime,
              required endTime,
            }) =>
              created?.add(subjectId)
          : null,
      onUpdateClassSchedule: manage
          ? ({
              required id,
              required subjectId,
              required professorId,
              required sectionId,
              required schoolYear,
              required term,
              required room,
              required days,
              required startTime,
              required endTime,
            }) =>
              updated?.add('$id|$room|${days.join(",")}')
          : null,
      onDeleteClassSchedule: manage ? (id) => deleted?.add(id) : null,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the Scheduling Officer sees the schedule table with Edit/Delete',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final updated = <String>[];
    final deleted = <String>[];
    await tester.pumpWidget(_page(updated: updated, deleted: deleted));
    await tester.pumpAndSettle();

    expect(find.text('Class Schedules'), findsOneWidget);
    expect(find.text('Computer Programming 1'), findsWidgets);
    // No Registrar-only "enroll students" action here.
    expect(find.byTooltip('Enroll this section\'s students'), findsNothing);

    // Edit: opens the prefilled form (Saturday kept), saves via the callback.
    await tester.ensureVisible(find.byTooltip('Edit schedule'));
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Class Schedule'), findsOneWidget);
    // The Scheduling Officer has its own Faculty Loading upload, so the form
    // offers no spreadsheet import.
    expect(find.byType(UploadSpreadsheetButton), findsNothing);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(updated, ['cs-1|Room 2|Sat']);

    // Delete: asks first, then reports the id.
    await tester.ensureVisible(find.byTooltip('Delete schedule'));
    await tester.tap(find.byTooltip('Delete schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Delete class schedule?'), findsOneWidget);
    expect(deleted, isEmpty);
    await tester.tap(find.byKey(const Key('archive-delete-confirm')));
    await tester.pumpAndSettle();
    expect(deleted, ['cs-1']);
  });

  testWidgets('without manage callbacks there is no Edit/Delete', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page(manage: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit schedule'), findsNothing);
    expect(find.byTooltip('Delete schedule'), findsNothing);
  });
}
