import 'package:dashboard_layout/dashboard_layout.dart'
    show BentoCard, BentoFormDialog, ProfileAvatarButton;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard owns its own light/dark toggle (its profile menu), separate
/// from the app theme — so the real "dark mode" case is an app theme that is
/// still LIGHT while the dashboard is switched to dark. Dialogs opened from
/// the dashboard land on the root overlay, outside the dashboard's own Theme,
/// and must carry the dashboard's mode with them.
void main() {
  const darkCard = Color(0xFF191A1F);

  DisciplineCaseModel archived(String id, String name) => DisciplineCaseModel(
        id: id,
        studentName: name,
        studentNumber: '24-$id',
        programGradeSection: 'BSIT-3A',
        violationType: 'Minor – Uniform Violation',
        submittedBy: 'Guard',
        submitterRole: '',
        incidentDateTime: DateTime(2026, 1, 1),
        description: '',
        archivedAt: DateTime.now().subtract(const Duration(days: 2)),
      );

  final restored = <String>[];

  /// Pumps the dashboard under a LIGHT app theme, then switches the dashboard
  /// to dark with its own profile-menu toggle.
  Future<void> pumpDashboardInDarkMode(WidgetTester tester) async {
    restored.clear();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: DisciplineOfficerDashboardPage(
        initialPendingQueue: [
          DisciplineCaseModel(
            id: 'p1',
            studentName: 'Pending Student',
            studentNumber: '24-99',
            programGradeSection: 'BSIT-3A',
            violationType: 'Minor – Uniform Violation',
            submittedBy: 'Guard',
            submitterRole: '',
            incidentDateTime: DateTime(2026, 1, 1),
            description: '',
          ),
        ],
        availableOffenses: const [
          OffenseOption(id: 'o1', label: 'Minor – Uniform Violation'),
          OffenseOption(id: 'o2', label: 'Major – Vandalism'),
        ],
        onLoadArchivedViolations: () async =>
            [archived('01', 'Nyco Geronimo'), archived('02', 'Ana Cruz')],
        onRestoreArchived: (id) async => restored.add(id),
        onModifyCase: (id, {offenseId, isEscalated, penaltyImposed}) async {},
        onArchiveCase: (_) async {},
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    // The dashboard's own dark toggle: profile avatar -> "Dark Mode".
    await tester.tap(find.byType(ProfileAvatarButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await tester.pumpAndSettle();

    // Guard against a vacuous test: the dashboard itself really is dark now.
    expect(
      Theme.of(tester.element(find.byKey(const Key('view-archived'))))
          .brightness,
      Brightness.dark,
    );
  }

  Color? cardColorOf(WidgetTester tester, Finder within) {
    final cards = find.descendant(of: within, matching: find.byType(BentoCard));
    return cards.evaluate().isEmpty
        ? null
        : tester.widget<BentoCard>(cards.first).backgroundColor;
  }

  Future<void> openArchive(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('view-archived')));
    await tester.pumpAndSettle();
  }

  group('Archived Violation Reports', () {
    testWidgets('is dark when the dashboard is dark', (tester) async {
      await pumpDashboardInDarkMode(tester);
      await openArchive(tester);

      expect(find.text('Archived Violation Reports'), findsOneWidget);
      expect(cardColorOf(tester, find.byType(Dialog)), darkCard);
    });

    testWidgets('each report offers Restore and nothing else', (tester) async {
      await pumpDashboardInDarkMode(tester);
      await openArchive(tester);

      expect(find.byKey(const Key('archived-restore')), findsNWidgets(2));
      final dialog = find.byType(Dialog);
      for (final gone in ['Validate', 'Modify', 'Delete']) {
        expect(find.descendant(of: dialog, matching: find.text(gone)),
            findsNothing,
            reason: '$gone is no longer an archive action');
      }
      // `TextButton.icon` is a private subclass, so match by `is`.
      expect(
        find.descendant(
            of: dialog,
            matching: find.byWidgetPredicate((w) => w is TextButton)),
        findsNWidgets(2),
        reason: 'only the two Restore buttons',
      );
      expect(find.textContaining('Restore them to the queue'), findsOneWidget);
    });

    testWidgets('Restore returns the report and drops it from the list',
        (tester) async {
      await pumpDashboardInDarkMode(tester);
      await openArchive(tester);

      await tester.tap(find.byKey(const Key('archived-restore')).first);
      await tester.pumpAndSettle();

      expect(restored, ['01']);
      expect(find.text('Nyco Geronimo'), findsNothing);
      expect(find.text('Ana Cruz'), findsOneWidget);
    });
  });

  group('queue dialogs share the dashboard dark mode', () {
    Future<void> selectPendingCase(WidgetTester tester) async {
      await tester.tap(find.text('Pending Student').first);
      await tester.pumpAndSettle();
    }

    testWidgets('Modify Violation is dark', (tester) async {
      await pumpDashboardInDarkMode(tester);
      await selectPendingCase(tester);
      await tester.tap(find.text('Modify'));
      await tester.pumpAndSettle();

      expect(find.text('Modify Violation'), findsOneWidget);
      final dialog =
          tester.widget<BentoFormDialog>(find.byType(BentoFormDialog));
      expect(dialog.backgroundColor, darkCard);
      expect(
        Theme.of(tester.element(find.text('Modify Violation'))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('the Delete confirmation is dark', (tester) async {
      await pumpDashboardInDarkMode(tester);
      await selectPendingCase(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Violation Report?'), findsOneWidget);
      final dialog =
          tester.widget<BentoFormDialog>(find.byType(BentoFormDialog));
      expect(dialog.backgroundColor, darkCard);
    });
  });
}
