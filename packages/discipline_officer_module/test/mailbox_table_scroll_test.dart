import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mailbox list (the shared Inbox/Sent list in every dashboard) scrolls
/// sideways once its card is too narrow for its columns.
void main() {
  Widget mailbox() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MailboxListCard(
              title: 'Inbox',
              isDarkMode: false,
              searchController: TextEditingController(),
              onSearchChanged: (_) {},
              hasSelection: false,
              onMarkRead: () {},
              onMarkUnread: () {},
              onDelete: () {},
              headerColumns: const ['From', 'Subject', 'Time'],
              allSelected: false,
              onSelectAll: (_) {},
              currentPage: 1,
              totalPages: 1,
              totalCount: 0,
              onPreviousPage: () {},
              onNextPage: () {},
              emptyLabel: 'Nothing here',
              rows: const [],
            ),
          ),
        ),
      );

  bool headerScrolls(WidgetTester tester) => find
      .ancestor(
          of: find.byType(DashboardTableHeader),
          matching: find.byWidgetPredicate((w) =>
              w is Scrollable && w.axisDirection == AxisDirection.right))
      .evaluate()
      .isNotEmpty;

  testWidgets('scrolls sideways on a phone, not on a wide screen',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(mailbox());
    await tester.pumpAndSettle();
    expect(find.byType(DashboardTableHeader), findsOneWidget);
    expect(headerScrolls(tester), isFalse);

    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpWidget(KeyedSubtree(key: const ValueKey('phone'), child: mailbox()));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(headerScrolls(tester), isTrue);
    final header =
        tester.widget<DashboardTableHeader>(find.byType(DashboardTableHeader));
    expect(
        tester.getSize(find.byType(DashboardTableHeader)).width,
        greaterThanOrEqualTo(
            dashboardTableMinWidth(header.columns, leadingWidth: 40)));
  });
}
