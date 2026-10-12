import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _archived(String id, String name, String type) =>
    DisciplineCaseModel(
      id: id,
      studentName: name,
      studentNumber: '24-$id',
      programGradeSection: 'BSIT-3A',
      violationType: type,
      submittedBy: 'Guard',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 1, 1),
      description: '',
      archivedAt: DateTime(2026, 2, 1),
    );

/// The Violation Queue's archive can be searched, and archived reports deleted
/// for good — ticked ones ("Delete selected") or everything listed ("Delete
/// all"), each behind a confirmation.
void main() {
  Future<void> openArchive(
    WidgetTester tester, {
    required Future<List<DisciplineCaseModel>> Function() loader,
    Future<void> Function(List<String> ids)? onDelete,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DisciplineOfficerDashboardPage(
        initialPendingQueue: [
          _archived('p1', 'Pending Student', 'Minor – Uniform Violation'),
        ],
        onLoadArchivedViolations: loader,
        onDeleteArchivedViolations: onDelete,
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.byKey(const Key('view-archived')));
    await tester.pumpAndSettle();
  }

  Future<List<DisciplineCaseModel>> three() async => [
        _archived('01', 'Nyco Geronimo', 'Disruptive behavior'),
        _archived('02', 'Ana Cruz', 'Tardiness'),
        _archived('03', 'Ben Reyes', 'Disruptive behavior'),
      ];

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('archive-delete-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('the search bar filters by name, number or violation',
      (tester) async {
    await openArchive(tester, loader: three);

    await tester.enterText(find.byKey(const Key('archive-search')), 'ana');
    await tester.pumpAndSettle();
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Nyco Geronimo'), findsNothing);

    await tester.enterText(
        find.byKey(const Key('archive-search')), 'disruptive');
    await tester.pumpAndSettle();
    expect(find.text('Nyco Geronimo'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsNothing);

    await tester.enterText(find.byKey(const Key('archive-search')), '24-03');
    await tester.pumpAndSettle();
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Nyco Geronimo'), findsNothing);

    await tester.enterText(find.byKey(const Key('archive-search')), 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No matching reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete selected permanently deletes only the ticked reports',
      (tester) async {
    final deleted = <String>[];
    await openArchive(
      tester,
      loader: three,
      onDelete: (ids) async => deleted.addAll(ids),
    );

    await tester.tap(find.byKey(const Key('archived-select-01')));
    await tester.tap(find.byKey(const Key('archived-select-03')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected reports?'), findsOneWidget);
    expect(find.textContaining('2 archived reports'), findsOneWidget);
    expect(deleted, isEmpty);

    await confirm(tester);

    expect(deleted, ['01', '03']);
    expect(find.text('Nyco Geronimo'), findsNothing);
    expect(find.text('Ben Reyes'), findsNothing);
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('2 reports deleted.'), findsOneWidget);
  });

  testWidgets('Select all asks first, and Cancel keeps every report',
      (tester) async {
    final deleted = <String>[];
    await openArchive(
      tester,
      loader: three,
      onDelete: (ids) async => deleted.addAll(ids),
    );

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected reports?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('archive-delete-cancel')));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('Ana Cruz'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(deleted, ['01', '02', '03']);
    expect(find.text('No archived reports'), findsOneWidget);
  });

  testWidgets('searching, Select all and Delete selected only removes the results',
      (tester) async {
    final deleted = <String>[];
    await openArchive(
      tester,
      loader: three,
      onDelete: (ids) async => deleted.addAll(ids),
    );

    await tester.enterText(
        find.byKey(const Key('archive-search')), 'disruptive');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(deleted, ['01', '03']);
    expect(find.text('No matching reports'), findsOneWidget);
  });

  testWidgets('with no delete handler the archive is search-only',
      (tester) async {
    await openArchive(tester, loader: three);

    expect(find.byKey(const Key('archive-search')), findsOneWidget);
    expect(find.byKey(const Key('archive-delete-selected')), findsNothing);
    expect(find.byKey(const Key('archived-select-01')), findsNothing);
  });
}
