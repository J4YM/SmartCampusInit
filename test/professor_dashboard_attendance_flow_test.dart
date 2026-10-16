import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/pages/dashboard/professor_dashboard_page.dart';
import 'package:professor_module/professor_module.dart';

void main() {
  const switchBlocked =
      'Save or discard your attendance changes before switching class.';

  final monday = dateOnly(mondayOf(DateTime.now()));
  final tuesday = monday.add(const Duration(days: 1));

  const sections = [
    ProfessorSectionModel(
      id: 'sec1',
      name: 'BSIT 3A',
      studentCount: 2,
      subjectId: 'sub-math',
      subjectName: 'Mathematics',
      classSectionId: 'cs-math',
    ),
    ProfessorSectionModel(
      id: 'sec1',
      name: 'BSIT 3A',
      studentCount: 2,
      subjectId: 'sub-sci',
      subjectName: 'Science',
      classSectionId: 'cs-sci',
    ),
  ];

  const students = [
    StudentAttendanceRecordModel(
      id: 'st1',
      studentName: 'Alice Cruz',
      studentId: '2024-001',
      presentCount: 0,
      totalSessions: 0,
      absentCount: 0,
    ),
    StudentAttendanceRecordModel(
      id: 'st2',
      studentName: 'Bob Reyes',
      studentId: '2024-002',
      presentCount: 0,
      totalSessions: 0,
      absentCount: 0,
    ),
  ];

  final cells = [
    for (final s in students)
      for (final d in [monday, tuesday])
        AttendanceCellModel(studentRecordId: s.id, date: d),
  ];

  String cellKey(String studentId, DateTime d) =>
      'attendance-cell-$studentId-${d.year}-${d.month}-${d.day}';

  // The cell widget is a full-width Align; tap its InkResponse so the hit
  // lands on the icon rather than empty space.
  Finder cellTap(String studentId, DateTime d) => find.descendant(
        of: find.byKey(ValueKey(cellKey(studentId, d))),
        matching: find.byType(InkResponse),
      );

  final calls = <({String classSectionId, DateTime date, List<String> ids})>[];
  final selected = <String?>[];

  Future<Map<String, List<EarlierClassStatus>>> fetchEarlier(
    ProfessorSectionModel section,
    DateTime date,
    List<String> ids,
  ) async {
    calls.add((
      classSectionId: section.classSectionId!,
      date: dateOnly(date),
      ids: ids,
    ));
    return {
      for (final id in ids)
        id: const [
          EarlierClassStatus(
            subjectName: 'Physics',
            professorName: 'Reyes',
            startTime: '08:00',
            status: AttendanceStatus.absent,
          ),
        ],
    };
  }

  Future<void> pumpPage(WidgetTester tester) async {
    // The test font (Ahem) is taller than the production one, so the
    // student name cell reports cosmetic RenderFlex overflows; ignore only
    // those, every other framework error still fails the test.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('RenderFlex') && text.contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    calls.clear();
    selected.clear();
    await tester.pumpWidget(MaterialApp(
      home: ProfessorDashboardPage(
        initialSections: sections,
        initialStudentAttendance: students,
        initialAttendanceCells: cells,
        onFetchEarlierClasses: fetchEarlier,
        onSectionSelected: (s) async => selected.add(s.classSectionId),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance').first);
    await tester.pumpAndSettle();
  }

  Future<void> selectScience(WidgetTester tester) async {
    // The Science group is collapsed until its header is opened.
    if (find.byKey(const ValueKey('section-row-cs-sci')).evaluate().isEmpty) {
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('section-row-cs-sci')));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a date cell in edit mode fetches earlier classes, shown '
      "in a popup when a student's name is clicked", (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(cellTap('st1', tuesday));
    await tester.pumpAndSettle();

    expect(calls, isNotEmpty);
    expect(calls.last.classSectionId, 'cs-math');
    expect(calls.last.date, tuesday);
    expect(calls.last.ids, unorderedEquals(['st1', 'st2']));
    // The other classes are no longer listed in the student's row...
    expect(find.textContaining('Physics'), findsNothing);
    // ...they open in a popup from the student's name.
    await tester.tap(find.byKey(const ValueKey('student-info-st1')));
    await tester.pumpAndSettle();
    expect(find.text('8:00 AM Physics'), findsOneWidget);
    expect(find.text('Absent'), findsWidgets);
  });

  testWidgets('switching class while editing is blocked with a snackbar',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await selectScience(tester);

    expect(find.text(switchBlocked), findsOneWidget);
    expect(selected, isEmpty, reason: 'onSectionSelected must not fire');
    // Still editing, still on the original class.
    expect(find.text('Discard'), findsOneWidget);
    await tester.tap(cellTap('st1', tuesday));
    await tester.pumpAndSettle();
    expect(calls.last.classSectionId, 'cs-math');
  });

  testWidgets('discarding leaves edit mode and then class switch works',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(cellTap('st1', tuesday));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('student-info-st1')));
    await tester.pumpAndSettle();
    expect(find.text('8:00 AM Physics'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    // Back to view mode.
    expect(find.text('Edit'), findsOneWidget);

    await selectScience(tester);
    expect(find.text(switchBlocked), findsNothing);
    expect(selected, ['cs-sci']);
  });
}
