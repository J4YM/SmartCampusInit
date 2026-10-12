import 'package:capstone_dashboard/data/academic_term_repository.dart';
import 'package:capstone_dashboard/ui/admin/academic_term_connected_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin > Academic Term > Archived Terms: a search bar over the closed terms,
/// and permanent deletion of ticked terms or of everything listed, each behind
/// a confirmation. The current term never appears in the list.
void main() {
  AcademicTerm term(String id, String year, String name,
          {bool current = false, int records = 10}) =>
      AcademicTerm(
        id: id,
        schoolYear: year,
        term: name,
        isCurrent: current,
        startedAt: DateTime(2025, 6, 1),
        closedAt: current ? null : DateTime(2025, 10, 30),
        archivedCounts: current ? const {} : {'attendance_records': records},
      );

  final terms = [
    term('t0', '2026-2027', '1st Semester', current: true),
    term('t1', '2025-2026', '2nd Semester'),
    term('t2', '2025-2026', '1st Semester'),
    term('t3', '2024-2025', 'Summer'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<String>? deleted,
  }) async {
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AcademicTermConnectedPage(
          debugTerms: terms,
          debugDeleteTerms: (ids) async {
            deleted?.addAll(ids);
            return ids.length;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('archive-delete-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the closed terms (not the current one) with a search '
      'bar', (tester) async {
    await pump(tester);

    expect(find.text('3 closed terms'), findsOneWidget);
    expect(find.text('2025-2026 · 2nd Semester'), findsOneWidget);
    expect(find.text('2024-2025 · Summer'), findsOneWidget);
    expect(find.byKey(const Key('archive-search')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('archive-search')), 'summer');
    await tester.pumpAndSettle();
    expect(find.text('2024-2025 · Summer'), findsOneWidget);
    expect(find.text('2025-2026 · 2nd Semester'), findsNothing);
    expect(find.text('1 of 3 closed terms'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('archive-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No archived terms match your search'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete selected deletes only the ticked terms, after a '
      'confirmation that says what goes with them', (tester) async {
    final deleted = <String>[];
    await pump(tester, deleted: deleted);

    await tester.tap(find.byKey(const ValueKey('term-select-t1')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected terms?'), findsOneWidget);
    expect(find.textContaining('10 records'), findsOneWidget);
    expect(deleted, isEmpty);

    await confirm(tester);

    expect(deleted, ['t1']);
    expect(find.text('2025-2026 · 2nd Semester'), findsNothing);
    expect(find.text('2 closed terms'), findsOneWidget);
  });

  testWidgets('Select all then Delete selected covers every closed term',
      (tester) async {
    final deleted = <String>[];
    await pump(tester, deleted: deleted);

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-cancel')));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);

    // The current term (t0) is never part of it.
    expect(deleted, ['t1', 't2', 't3']);
    expect(find.text('No closed terms yet'), findsOneWidget);
  });

  testWidgets('searching, Select all and Delete selected removes only the results',
      (tester) async {
    final deleted = <String>[];
    await pump(tester, deleted: deleted);

    await tester.enterText(find.byKey(const Key('archive-search')), '2025-2026');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(deleted, ['t1', 't2']);
  });
}
