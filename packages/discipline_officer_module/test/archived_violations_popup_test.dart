import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:dashboard_layout/dashboard_layout.dart' show BentoCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _archived(String id, String name, String type, Duration ago) =>
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
      archivedAt: DateTime.now().subtract(ago),
    );

void main() {
  Future<void> openArchive(
    WidgetTester tester,
    Future<List<DisciplineCaseModel>> Function() loader, {
    Size size = const Size(1400, 1000),
    Brightness brightness = Brightness.light,
    Future<void> Function(String id)? onRestore,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: DisciplineOfficerDashboardPage(
        initialPendingQueue: [
          _archived('p1', 'Pending Student', 'Minor – Uniform Violation', Duration.zero),
        ],
        onLoadArchivedViolations: loader,
        onRestoreArchived: onRestore,
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.byKey(const Key('view-archived')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists archived reports as cards with their purge countdown',
      (tester) async {
    await openArchive(
      tester,
      () async => [
        _archived('01', 'Nyco Geronimo', 'Disruptive classroom behavior',
            const Duration(days: 2)),
        _archived('02', 'Ana Cruz', 'Tardiness (habitual) without valid excuse',
            const Duration(days: 6)),
      ],
    );

    expect(find.text('Archived Violation Reports'), findsOneWidget);
    expect(find.textContaining('left open for over 72 hours'), findsOneWidget);
    for (final id in ['01', '02']) {
      expect(find.byKey(ValueKey('archived-$id')), findsOneWidget);
    }
    expect(find.text('Nyco Geronimo'), findsOneWidget);
    expect(find.text('24-01'), findsOneWidget);
    expect(find.text('Disruptive classroom behavior'), findsOneWidget);
    // Why each is archived, as a labelled pill (deleted by hand here).
    expect(find.text('Deleted'), findsNWidgets(2));
    expect(find.textContaining('Archived 20'), findsNWidgets(2));
    // No stray fixed-height blank area: the sheet hugs its two cards.
    final list = tester.getSize(find.descendant(
        of: find.byType(Dialog), matching: find.byType(ListView)));
    expect(list.height, lessThan(320));

    await tester.tap(find.byKey(const Key('popup-close')));
    await tester.pumpAndSettle();
    expect(find.text('Archived Violation Reports'), findsNothing);
  });

  testWidgets('says so when nothing is archived', (tester) async {
    await openArchive(tester, () async => const []);
    expect(find.text('No archived reports'), findsOneWidget);
    expect(find.textContaining('appear here'), findsOneWidget);
  });

  testWidgets('shows a message instead of crashing when loading fails',
      (tester) async {
    await openArchive(tester, () async => throw 'network down');
    expect(find.text('Could not load archived reports'), findsOneWidget);
    expect(find.textContaining('network down'), findsOneWidget);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final never = Future<List<DisciplineCaseModel>>.delayed(
        const Duration(days: 1), () => const []);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DisciplineOfficerDashboardPage(
        initialPendingQueue: [
          _archived('p1', 'Pending Student', 'Minor – Uniform Violation', Duration.zero),
        ],
        onLoadArchivedViolations: () => never,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('view-archived')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Let the pending timer finish so the test ends cleanly.
    await tester.pump(const Duration(days: 2));
  });

  testWidgets('on a phone it is a bottom sheet', (tester) async {
    await openArchive(
      tester,
      () async => [
        _archived('01', 'Nyco Geronimo', 'Disruptive classroom behavior',
            const Duration(days: 2)),
      ],
      size: const Size(390, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Nyco Geronimo'), findsOneWidget);
  });

  // The popup follows the DASHBOARD's own light/dark toggle (see
  // archive_dark_mode_test.dart for the dark case), not the app theme: the
  // dashboard starts light whatever the app theme is, so a popup that went
  // dark on its own would sit dark over a light page.
  testWidgets('follows the dashboard, not the app theme', (tester) async {
    await openArchive(
      tester,
      () async => [
        _archived('01', 'Nyco Geronimo', 'Disruptive classroom behavior',
            const Duration(days: 2)),
      ],
      brightness: Brightness.dark,
    );
    final card = tester.widget<BentoCard>(find
        .descendant(of: find.byType(Dialog), matching: find.byType(BentoCard))
        .first);
    expect(card.backgroundColor, const Color(0xFFFFFFFF));
    expect(find.text('Nyco Geronimo'), findsOneWidget);
  });
  group('pagination', () {
    // The dashboard behind the popup has its own Previous/Next footer.
    Finder inPopup(String label) => find.descendant(
        of: find.byType(Dialog), matching: find.text(label));

    List<DisciplineCaseModel> many(int n) => [
          for (var i = 1; i <= n; i++)
            _archived(i.toString().padLeft(2, '0'), 'Student $i',
                'Violation $i', Duration(days: i)),
        ];

    int cards(WidgetTester tester) => find
        .byWidgetPredicate((w) =>
            w.key is ValueKey &&
            (w.key as ValueKey).value.toString().startsWith('archived-0') ||
            (w.key is ValueKey &&
                (w.key as ValueKey).value.toString().startsWith('archived-1')))
        .evaluate()
        .length;

    testWidgets('lists five reports a page and pages through the rest',
        (tester) async {
      await openArchive(tester, () async => many(12));

      expect(find.text('Page 1 of 3 · 12 total'), findsOneWidget);
      expect(cards(tester), 5);
      expect(find.text('Student 1'), findsOneWidget);
      expect(find.text('Student 5'), findsOneWidget);
      expect(find.text('Student 6'), findsNothing);

      await tester.tap(inPopup('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3 · 12 total'), findsOneWidget);
      expect(find.text('Student 6'), findsOneWidget);
      expect(find.text('Student 10'), findsOneWidget);
      expect(find.text('Student 1'), findsNothing);

      await tester.tap(inPopup('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3 · 12 total'), findsOneWidget);
      expect(cards(tester), 2);
      expect(find.text('Student 12'), findsOneWidget);

      await tester.tap(inPopup('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3 · 12 total'), findsOneWidget);
    });

    testWidgets('a short list is one page', (tester) async {
      await openArchive(tester, () async => many(2));
      expect(find.text('Page 1 of 1 · 2 total'), findsOneWidget);
      expect(cards(tester), 2);
    });

    testWidgets('restoring the only report on the last page steps back a page',
        (tester) async {
      final restored = <String>[];
      await openArchive(
        tester,
        () async => many(6),
        onRestore: (id) async => restored.add(id),
      );
      await tester.tap(inPopup('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2 · 6 total'), findsOneWidget);
      expect(find.text('Student 6'), findsOneWidget);

      await tester.tap(find.byKey(const Key('archived-restore')));
      await tester.pumpAndSettle();

      expect(restored, ['06']);
      // Page 2 no longer exists: the popup lands on the new last page.
      expect(find.text('Page 1 of 1 · 5 total'), findsOneWidget);
      expect(find.text('Student 1'), findsOneWidget);
    });

    testWidgets('the footer is inside the popup and follows the dark theme',
        (tester) async {
      await openArchive(tester, () async => many(7),
          brightness: Brightness.dark);
      final footer = find.text('Page 1 of 2 · 7 total');
      expect(footer, findsOneWidget);
      expect(
        find.ancestor(of: footer, matching: find.byType(Dialog)),
        findsOneWidget,
      );
    });
  });

}
