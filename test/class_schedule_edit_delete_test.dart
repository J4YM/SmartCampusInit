import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

const _manual = ScheduleEntryModel(
  id: 'cs-1',
  subject: 'Computer Programming 1',
  gradeSection: 'BSIT-1A',
  teacher: 'Ana Cruz',
  room: 'Room 2',
  days: ['Mon', 'Thu'],
  timeRange: '8:00 AM - 9:30 AM',
  subjectId: 'sub-1',
  sectionId: 'sec-1',
  professorId: 'prof-1',
  schoolYear: '2026-2027',
  term: '2nd Semester',
  startTime: '08:00',
  endTime: '09:30',
);

Future<void> _setUpView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('each row has Edit and Delete buttons that report the entry',
      (tester) async {
    await _setUpView(tester);
    final edited = <String>[];
    final deleted = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClassScheduleView(
            entries: const [_manual],
            onEdit: (e) => edited.add(e.id),
            onDelete: (e) => deleted.add(e.id),
          ),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.tap(find.byTooltip('Delete schedule'));
    expect(edited, ['cs-1']);
    expect(deleted, ['cs-1']);
  });

  testWidgets('without callbacks (demo data) the buttons are not shown',
      (tester) async {
    await _setUpView(tester);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClassScheduleView(entries: [_manual]),
        ),
      ),
    ));
    expect(find.byTooltip('Edit schedule'), findsNothing);
    expect(find.byTooltip('Delete schedule'), findsNothing);
  });

  testWidgets('the edit form is prefilled and saves the changed values',
      (tester) async {
    await _setUpView(tester);
    Map<String, Object?>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAddClassScheduleDialog(
            context,
            subjectOptions: const [
              SubjectOption(id: 'sub-1', code: 'CITE1003', title: 'Computer Programming 1'),
            ],
            teacherOptions: const [
              TeacherOption(id: 'prof-1', fullName: 'Ana Cruz'),
            ],
            sectionOptions: const [
              SectionOption(id: 'sec-1', name: 'BSIT-1A', yearLevel: 1),
            ],
            roomOptions: const ['Room 1', 'Room 2'],
            editing: _manual,
            onSaveChanges: ({
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
                saved = {
              'subjectId': subjectId,
              'professorId': professorId,
              'sectionId': sectionId,
              'schoolYear': schoolYear,
              'term': term,
              'room': room,
              'days': (days..sort()),
              'start': startTime,
              'end': endTime,
            },
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Class Schedule'), findsOneWidget);
    expect(find.text('Add Class Schedule'), findsNothing);
    expect(find.text('CITE1003 — Computer Programming 1'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('2026-2027'), findsOneWidget);
    // Saturday classes are possible, so Sat is offered alongside Mon-Fri.
    for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) {
      expect(find.text(d), findsOneWidget, reason: d);
    }

    // Untouched save round-trips the existing values.
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(saved, {
      'subjectId': 'sub-1',
      'professorId': 'prof-1',
      'sectionId': 'sec-1',
      'schoolYear': '2026-2027',
      'term': '2nd Semester',
      'room': 'Room 2',
      'days': ['Mon', 'Thu'],
      'start': '08:00',
      'end': '09:30',
    });
  });
}
