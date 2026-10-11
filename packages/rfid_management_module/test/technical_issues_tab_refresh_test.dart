import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// The Technical Issues tab is fed by the host's background refresh: a ticket
/// that is filed while the tab is open has to show up on its own, without the
/// technician pressing a filter button.
void main() {
  TechnicalIssueRowModel ticket(String id, String description) =>
      TechnicalIssueRowModel(
        id: id,
        categoryLabel: 'Classroom PC problem',
        description: description,
        location: null,
        reportedByLabel: 'Teacher',
        status: 'open',
        statusLabel: 'Open',
        createdAtLabel: 'just now',
      );

  Widget host(List<TechnicalIssueRowModel> reports) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TechnicalIssuesTab(
              reports: reports,
              isLoading: false,
              statusFilter: 'All',
              onStatusFilterChanged: (_) {},
              onLoadComments: (_) async => const [],
              onAddComment: (_, __) async {},
              onChangeStatus: (_, __) async {},
            ),
          ),
        ),
      );

  testWidgets('a ticket filed while the tab is open appears on its own',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host([ticket('a', 'Projector is broken')]));
    await tester.pumpAndSettle();
    expect(find.text('Projector is broken'), findsOneWidget);
    expect(find.text('No power in room 203'), findsNothing);

    // The host's refresh hands down the same list plus the new ticket.
    await tester.pumpWidget(host([
      ticket('b', 'No power in room 203'),
      ticket('a', 'Projector is broken'),
    ]));
    expect(find.text('No power in room 203'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Projector is broken'), findsOneWidget);
    expect(tester.getTopLeft(find.text('No power in room 203')).dy,
        lessThan(tester.getTopLeft(find.text('Projector is broken')).dy));
    expect(tester.takeException(), isNull);
  });
}
