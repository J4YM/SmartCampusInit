import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

void main() {
  void setLogicalSurfaceSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  const report = TechnicalIssueRowModel(
    id: 't1',
    categoryLabel: 'Offline device/reader',
    description: 'Floor 2 reader stopped responding',
    location: 'Floor 2',
    reportedByLabel: 'Teacher',
    status: 'open',
    statusLabel: 'Open',
    createdAtLabel: '2h ago',
  );

  Widget buildTab({
    required Future<List<TechnicalIssueCommentRowModel>> Function(String) onLoadComments,
    Future<void> Function(String, String)? onAddComment,
    Future<void> Function(String, String)? onChangeStatus,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TechnicalIssuesTab(
          reports: const [report],
          isLoading: false,
          statusFilter: 'All',
          onStatusFilterChanged: (_) {},
          onLoadComments: onLoadComments,
          onAddComment: onAddComment ?? (_, __) async {},
          onChangeStatus: onChangeStatus ?? (_, __) async {},
        ),
      ),
    );
  }

  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.text('Offline device/reader').first);
    await tester.pumpAndSettle();
  }

  testWidgets('a failed comment load shows the error plus a working Retry', (tester) async {
    setLogicalSurfaceSize(tester, const Size(900, 900));
    var attempts = 0;
    await tester.pumpWidget(buildTab(onLoadComments: (_) async {
      attempts++;
      if (attempts == 1) throw Exception('network down');
      return const [];
    }));
    await openDetail(tester);

    // No permanent spinner, no unhandled exception — an error + Retry instead.
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Could not load replies'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('No replies yet.'), findsOneWidget);
  });

  testWidgets('a failed reply keeps the typed text instead of clearing it', (tester) async {
    setLogicalSurfaceSize(tester, const Size(900, 900));
    await tester.pumpWidget(buildTab(
      onLoadComments: (_) async => const [],
      onAddComment: (_, __) async => throw Exception('write rejected'),
    ));
    await openDetail(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Reply...'), 'Please check floor 2');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Please check floor 2'), findsOneWidget);
    expect(find.textContaining('Could not send reply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed status change reverts the dropdown selection', (tester) async {
    setLogicalSurfaceSize(tester, const Size(900, 900));
    await tester.pumpWidget(buildTab(
      onLoadComments: (_) async => const [],
      onChangeStatus: (_, __) async => throw Exception('update rejected'),
    ));
    await openDetail(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved').last);
    await tester.pumpAndSettle();

    // The optimistic selection was rolled back to the persisted value.
    expect(
      find.descendant(
        of: find.byType(DropdownButtonFormField<String>),
        matching: find.text('Open'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Could not update status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
