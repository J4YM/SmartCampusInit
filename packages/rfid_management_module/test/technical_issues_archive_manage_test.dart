import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// The archive popup can be searched, and archived issues deleted for good —
/// a ticked selection ("Delete selected"; "Select all" ticks everything listed),
/// behind a confirmation.
void main() {
  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  TechnicalIssueRowModel resolved(int i, {String category = 'Classroom PC'}) =>
      TechnicalIssueRowModel(
        id: 'r$i',
        categoryLabel: category,
        description: 'Issue number $i',
        location: 'Room $i',
        reportedByLabel: 'Teacher',
        status: 'resolved',
        statusLabel: 'Resolved',
        createdAtLabel: '3d ago',
        resolvedAtLabel: 'Oct $i, 2026 9:00 AM',
      );

  Widget buildTab({
    required Future<List<TechnicalIssueRowModel>> Function() onLoadArchived,
    Future<void> Function(List<String>)? onDeleteArchived,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TechnicalIssuesTab(
            reports: const [],
            isLoading: false,
            statusFilter: 'All',
            onStatusFilterChanged: (_) {},
            onLoadComments: (_) async => const [],
            onAddComment: (_, __) async {},
            onChangeStatus: (_, __) async {},
            onLoadArchived: onLoadArchived,
            onDeleteArchived: onDeleteArchived,
          ),
        ),
      ),
    );
  }

  Future<void> openArchive(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('view-archived')));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('archive-delete-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('the search bar narrows the archive and says when nothing '
      'matches', (tester) async {
    setSize(tester, const Size(1000, 1100));
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [
        resolved(1),
        resolved(2, category: 'Kiosk offline'),
        resolved(3),
      ],
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    expect(find.text('Issue number 1'), findsOneWidget);
    expect(find.text('Issue number 2'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('archive-search')), 'kiosk');
    await tester.pumpAndSettle();
    expect(find.text('Issue number 2'), findsOneWidget);
    expect(find.text('Issue number 1'), findsNothing);

    await tester.enterText(find.byKey(const Key('archive-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching issues'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Delete selected removes only the ticked issues, after a '
      'confirmation', (tester) async {
    setSize(tester, const Size(1000, 1100));
    final deleted = <String>[];
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [resolved(1), resolved(2), resolved(3)],
      onDeleteArchived: (ids) async => deleted.addAll(ids),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    // Nothing ticked: the action is inert.
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archived-select-r1')));
    await tester.tap(find.byKey(const Key('archived-select-r3')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected issues?'), findsOneWidget);
    expect(deleted, isEmpty); // nothing happens until it is confirmed

    await confirm(tester);

    expect(deleted, ['r1', 'r3']);
    expect(find.text('Issue number 1'), findsNothing);
    expect(find.text('Issue number 3'), findsNothing);
    expect(find.text('Issue number 2'), findsOneWidget);
    expect(find.text('2 issues deleted.'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    setSize(tester, const Size(1000, 1100));
    final deleted = <String>[];
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [resolved(1), resolved(2)],
      onDeleteArchived: (ids) async => deleted.addAll(ids),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-cancel')));
    await tester.pumpAndSettle();

    expect(deleted, isEmpty);
    expect(find.text('Issue number 1'), findsOneWidget);
    expect(find.text('Issue number 2'), findsOneWidget);
  });

  testWidgets('Select all then Delete selected removes everything listed; while '
      'searching only the matches', (tester) async {
    setSize(tester, const Size(1000, 1100));
    final deleted = <String>[];
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [
        resolved(1),
        resolved(2, category: 'Kiosk offline'),
        resolved(3, category: 'Kiosk offline'),
      ],
      onDeleteArchived: (ids) async => deleted.addAll(ids),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    await tester.enterText(find.byKey(const Key('archive-search')), 'kiosk');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);

    // Only the two matches went; the unmatched issue is still archived.
    expect(deleted, ['r2', 'r3']);
    await tester.enterText(find.byKey(const Key('archive-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('Issue number 1'), findsOneWidget);
    expect(find.text('Issue number 2'), findsNothing);
  });

  testWidgets('select-all ticks every listed issue', (tester) async {
    setSize(tester, const Size(1000, 1100));
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [resolved(1), resolved(2), resolved(3)],
      onDeleteArchived: (_) async {},
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('a failed delete says so and re-reads the archive',
      (tester) async {
    setSize(tester, const Size(1000, 1100));
    var loads = 0;
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async {
        loads++;
        return [resolved(1), resolved(2)];
      },
      onDeleteArchived: (_) async => throw Exception('not allowed'),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);
    expect(loads, 1);

    await tester.tap(find.byKey(const Key('archive-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-delete-selected')));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(find.textContaining('Could not delete'), findsOneWidget);
    expect(loads, 2);
    expect(find.text('Issue number 1'), findsOneWidget);
  });

  testWidgets('without a delete handler the archive is search-only',
      (tester) async {
    setSize(tester, const Size(1000, 1100));
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [resolved(1)],
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    expect(find.byKey(const Key('archive-search')), findsOneWidget);
    expect(find.byKey(const Key('archive-select-all')), findsNothing);
    expect(find.byKey(const Key('archive-delete-selected')), findsNothing);
    expect(find.byKey(const Key('archived-select-r1')), findsNothing);
  });
}
