import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_models.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_view.dart';

/// The Student Archive can be searched at two levels (students, then the logs
/// of an open student) and deleted from at two levels: some or all of one
/// student's logs, or every log of the ticked / listed students — each behind
/// a confirmation.
void main() {
  const maria = ArchiveStudentModel(
      id: 's1', name: 'Maria Santos', studentNumber: '2024-0001');
  const jose = ArchiveStudentModel(
      id: 's2', name: 'Jose Cruz', studentNumber: '2024-0002');

  ArchiveLogModel log(String id, String title, {String notes = ''}) =>
      ArchiveLogModel(
        id: id,
        type: ArchiveLogType.counseling,
        occurredOn: DateTime(2026, 9, 12),
        title: title,
        notes: notes,
      );

  Future<void> pumpView(WidgetTester tester, Widget view) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: view)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('archive-delete-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('an open student\'s logs can be searched', (tester) async {
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria],
        onLoadLogs: (_) async => [
          log('l1', 'Attendance talk', notes: 'Skipping Mondays'),
          log('l2', 'Parent conference'),
        ],
      ),
    );
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    expect(find.text('Attendance talk'), findsOneWidget);
    expect(find.text('Parent conference'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('archive-logs-search')), 'mondays');
    await tester.pumpAndSettle();
    expect(find.text('Attendance talk'), findsOneWidget);
    expect(find.text('Parent conference'), findsNothing);

    await tester.enterText(
        find.byKey(const Key('archive-logs-search')), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('No logs match your search.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete selected removes only the ticked logs of a student',
      (tester) async {
    ArchiveStudentModel? forStudent;
    List<ArchiveLogModel>? deleted;
    final logs = [log('l1', 'First'), log('l2', 'Second'), log('l3', 'Third')];
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria],
        onLoadLogs: (_) async => List.of(logs),
        onDeleteLogs: (student, picked) async {
          forStudent = student;
          deleted = picked;
          logs.removeWhere((l) => picked.any((p) => p.id == l.id));
        },
      ),
    );
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-log-select-l1')));
    await tester.tap(find.byKey(const ValueKey('archive-log-select-l3')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected logs?'), findsOneWidget);
    expect(deleted, isNull);
    await confirm(tester);

    expect(forStudent?.id, 's1');
    expect([for (final l in deleted!) l.id], ['l1', 'l3']);
    expect(find.text('First'), findsNothing);
    expect(find.text('Third'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('Select all inside a student deletes every log it lists',
      (tester) async {
    List<ArchiveLogModel>? deleted;
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria],
        onLoadLogs: (_) async => [log('l1', 'First'), log('l2', 'Second')],
        onDeleteLogs: (_, picked) async => deleted = picked,
      ),
    );
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect([for (final l in deleted!) l.id], ['l1', 'l2']);
  });

  testWidgets('Delete selected on the table removes every log of the ticked '
      'students', (tester) async {
    List<ArchiveStudentModel>? deleted;
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria, jose],
        onDeleteStudentLogs: (students) async => deleted = students,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('archive-select-s2')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected archives?'), findsOneWidget);
    expect(find.textContaining('every archival log of Jose Cruz'),
        findsOneWidget);
    await confirm(tester);

    expect([for (final s in deleted!) s.id], ['s2']);
  });

  testWidgets('Select all on the table covers every listed student, and '
      'Cancel does nothing', (tester) async {
    List<ArchiveStudentModel>? deleted;
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria, jose],
        onDeleteStudentLogs: (students) async => deleted = students,
      ),
    );

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-cancel')));
    await tester.pumpAndSettle();
    expect(deleted, isNull);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect([for (final s in deleted!) s.id], ['s1', 's2']);
  });

  testWidgets('without delete handlers there are no tick-boxes or delete '
      'actions', (tester) async {
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria],
        onLoadLogs: (_) async => [log('l1', 'First')],
      ),
    );
    expect(find.byKey(const Key('archive-delete-selected')), findsNothing);
    expect(find.byKey(const ValueKey('archive-select-s1')), findsNothing);

    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    // The log search is still there; nothing can be ticked or deleted.
    expect(find.byKey(const Key('archive-logs-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-log-select-l1')), findsNothing);
  });
}
