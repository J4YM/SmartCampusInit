import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared "View all notifications" list is fed by the host's background
/// refresh: a notification that arrives while the list is open has to show up
/// (and drop in at the top), without undoing what was already done to the
/// rows in the open list.
void main() {
  NotificationItemModel note(String id, {bool isRead = false}) =>
      NotificationItemModel(
        id: id,
        title: 'Title $id',
        message: 'Message $id',
        timestamp: DateTime(2026, 10, 11, 9, int.parse(id)),
        isRead: isRead,
      );

  Widget host(List<NotificationItemModel> items) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationsListView(notifications: items),
          ),
        ),
      );

  Future<void> useDesktopView(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a notification that arrives while open appears and animates in',
      (tester) async {
    await useDesktopView(tester);
    await tester.pumpWidget(host([note('1'), note('2')]));
    await tester.pumpAndSettle();
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 3'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(host([note('3'), note('1'), note('2')]));
    expect(find.text('Title 3'), findsOneWidget);
    // It is dropping in, not just popped into place.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();

    // And it sits above the ones that were already there.
    expect(tester.getTopLeft(find.text('Title 3')).dy,
        lessThan(tester.getTopLeft(find.text('Title 1')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('what the user already marked or deleted survives a refresh',
      (tester) async {
    await useDesktopView(tester);
    await tester.pumpWidget(host([note('1'), note('2')]));
    await tester.pumpAndSettle();

    // Select row 2 and delete it.
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Title 2'), findsNothing);

    // The host reloads with the same two plus a new one.
    await tester.pumpWidget(host([note('3'), note('1'), note('2')]));
    await tester.pumpAndSettle();

    expect(find.text('Title 3'), findsOneWidget);
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('Title 2'), findsNothing, reason: 'stays deleted');
  });

  testWidgets('rows use the shared animated-rows widget', (tester) async {
    await useDesktopView(tester);
    await tester.pumpWidget(host([note('1')]));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardTableRows), findsOneWidget);
  });
}
