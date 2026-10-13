import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// Resolved technical issues live in an archive, opened from a "View
/// Archived" button (the same pattern as Student Affairs' violation queue):
/// they are not in the active list, and Restore brings one back.
void main() {
  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  const open = TechnicalIssueRowModel(
    id: 'a1',
    categoryLabel: 'Offline kiosk',
    description: 'Lobby kiosk will not wake',
    location: 'Lobby',
    reportedByLabel: 'Teacher',
    status: 'open',
    statusLabel: 'Open',
    createdAtLabel: '2h ago',
  );

  TechnicalIssueRowModel resolved(int i) => TechnicalIssueRowModel(
        id: 'r$i',
        categoryLabel: 'Classroom PC problem',
        description: 'PC $i would not boot',
        location: 'Room $i',
        reportedByLabel: 'Teacher',
        status: 'resolved',
        statusLabel: 'Resolved',
        createdAtLabel: '3d ago',
        resolvedAtLabel: 'Oct $i, 2026 9:00 AM',
      );

  Widget buildTab({
    Future<List<TechnicalIssueRowModel>> Function()? onLoadArchived,
    Future<void> Function(String)? onRestore,
    Future<void> Function(String, String)? onChangeStatus,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TechnicalIssuesTab(
            reports: const [open],
            isLoading: false,
            statusFilter: 'All',
            onStatusFilterChanged: (_) {},
            onLoadComments: (_) async => const [],
            onAddComment: (_, __) async {},
            onChangeStatus: onChangeStatus ?? (_, __) async {},
            onLoadArchived: onLoadArchived,
            onRestore: onRestore,
          ),
        ),
      ),
    );
  }

  Future<void> openArchive(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('view-archived')));
    await tester.pumpAndSettle();
  }

  testWidgets('the card has a View Archived button and no Resolved filter',
      (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(buildTab(onLoadArchived: () async => const []));
    await tester.pumpAndSettle();

    expect(find.text('View Archived'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);
    expect(find.text('In Progress'), findsOneWidget);
    // Resolved issues are archived, not a filter of the active list.
    expect(find.text('Resolved'), findsNothing);
  });

  testWidgets('View Archived is on the filters row, at the far right of the '
      'card', (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(buildTab(onLoadArchived: () async => const []));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byKey(const Key('view-archived')));
    final inProgress = tester.getRect(find.text('In Progress'));
    final card = tester.getRect(find.ancestor(
      of: find.text('Technical Issues'),
      matching: find.byType(SizedBox),
    ).first);

    // Same row as the filter pills...
    expect((button.center.dy - inProgress.center.dy).abs(), lessThan(12));
    // ...to the right of them...
    expect(button.left, greaterThan(inProgress.right));
    // ...and flush with the card's right edge (its 20px padding).
    expect(card.right - button.right, closeTo(20, 1));
    // The pills are not stretched across the card.
    expect(button.width, lessThan(240));
  });

  testWidgets('phone: the row fits without overflow', (tester) async {
    setSize(tester, const Size(360, 800));
    await tester.pumpWidget(buildTab(onLoadArchived: () async => const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('view-archived')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no archive loader: no View Archived button', (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(buildTab());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('view-archived')), findsNothing);
  });

  testWidgets('the archive lists resolved issues with when they were '
      'resolved', (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(
        buildTab(onLoadArchived: () async => [resolved(1), resolved(2)]));
    await tester.pumpAndSettle();
    await openArchive(tester);

    expect(find.text('Archived Technical Issues'), findsOneWidget);
    expect(find.text('PC 1 would not boot'), findsOneWidget);
    expect(find.text('PC 2 would not boot'), findsOneWidget);
    expect(find.text('Resolved'), findsNWidgets(2)); // one badge per card
    expect(find.text('Resolved Oct 1, 2026 9:00 AM'), findsOneWidget);
    expect(find.text('Reported by Teacher · Room 1'), findsOneWidget);
  });

  testWidgets('Restore re-opens the issue and drops it from the archive',
      (tester) async {
    setSize(tester, const Size(1000, 900));
    final restored = <String>[];
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [resolved(1)],
      onRestore: (id) async => restored.add(id),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    await tester.tap(find.byKey(const Key('archived-restore')));
    await tester.pumpAndSettle();

    expect(restored, ['r1']);
    expect(find.text('PC 1 would not boot'), findsNothing);
    expect(find.text('No archived issues'), findsOneWidget);
    expect(find.text('Issue restored to the active list.'), findsOneWidget);
  });

  testWidgets('a failed restore keeps the issue and says so', (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [resolved(1)],
      onRestore: (_) async => throw Exception('write rejected'),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    await tester.tap(find.byKey(const Key('archived-restore')));
    await tester.pumpAndSettle();

    expect(find.text('PC 1 would not boot'), findsOneWidget);
    expect(find.textContaining('Could not restore the issue'), findsOneWidget);
  });

  testWidgets('five per page, paged with the shared footer', (tester) async {
    setSize(tester, const Size(1000, 1100));
    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => [for (var i = 1; i <= 7; i++) resolved(i)],
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);

    expect(find.text('PC 1 would not boot'), findsOneWidget);
    expect(find.text('PC 5 would not boot'), findsOneWidget);
    expect(find.text('PC 6 would not boot'), findsNothing);
    expect(find.textContaining('Page 1 of 2'), findsOneWidget);

    // `.last`: the page behind the popup has its own pager.
    await tester.tap(find.text('Next').last);
    await tester.pumpAndSettle();

    expect(find.text('PC 6 would not boot'), findsOneWidget);
    expect(find.text('PC 1 would not boot'), findsNothing);
  });

  testWidgets('empty and error states', (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(buildTab(onLoadArchived: () async => const []));
    await tester.pumpAndSettle();
    await openArchive(tester);
    expect(find.text('No archived issues'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(buildTab(
      onLoadArchived: () async => throw Exception('network down'),
    ));
    await tester.pumpAndSettle();
    await openArchive(tester);
    expect(find.text('Could not load archived issues'), findsOneWidget);
  });

  testWidgets('resolving an issue says it moved to the archive',
      (tester) async {
    setSize(tester, const Size(1000, 900));
    await tester.pumpWidget(buildTab(onLoadArchived: () async => const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Offline kiosk').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved').last);
    await tester.pumpAndSettle();

    expect(find.text('Issue resolved and moved to the archive.'),
        findsOneWidget);
  });
}
