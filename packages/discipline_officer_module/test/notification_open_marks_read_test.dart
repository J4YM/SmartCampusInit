import 'package:dashboard_layout/dashboard_layout.dart' show HeaderIconButton;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opening a notification's details marks it read — from the bell dropdown and
/// from the "View all notifications" list, on every dashboard that shares them.
void main() {
  _sizeTests();

  NotificationItemModel note(String id, {bool isRead = false}) =>
      NotificationItemModel(
        id: id,
        title: 'Title $id',
        message: 'Message body $id',
        timestamp: DateTime(2026, 10, 11, 9, int.parse(id)),
        isRead: isRead,
      );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> closeDetails(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  group('bell dropdown', () {
    testWidgets('tapping an unread notification reports it opened',
        (tester) async {
      desktop(tester);
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: NotificationsPopover(
              notifications: [note('1'), note('2', isRead: true)],
              onViewAll: () {},
              onMarkAllRead: () {},
              onOpenNotification: (n) => opened.add(n.id),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Title 1'));
      await tester.pumpAndSettle();
      // The details are showing…
      expect(find.text('Message body 1'), findsWidgets);
      // …and it was reported as opened.
      expect(opened, ['1']);
      await closeDetails(tester);

      // An already-read one is not reported again.
      await tester.tap(find.text('Title 2'));
      await tester.pumpAndSettle();
      expect(opened, ['1']);
    });
  });

  group('View all notifications list', () {
    testWidgets('opening an unread one marks it Read at once',
        (tester) async {
      desktop(tester);
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationsListView(
              notifications: [note('1'), note('2')],
              onOpenNotification: (n) => opened.add(n.id),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Unread'), findsNWidgets(2));
      expect(find.text('Read'), findsNothing);

      await tester.tap(find.text('Title 1'));
      await tester.pumpAndSettle();
      expect(find.text('Message body 1'), findsWidgets);
      expect(opened, ['1']);
      await closeDetails(tester);

      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets('it stays read when the host refreshes with the old list',
        (tester) async {
      desktop(tester);
      Widget host() => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NotificationsListView(
                  // A fresh list each time, still unread: the background
                  // refresh has not seen the save yet.
                  notifications: [note('1'), note('2')],
                ),
              ),
            ),
          );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Title 1'));
      await tester.pumpAndSettle();
      await closeDetails(tester);
      expect(find.text('Read'), findsOneWidget);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Read'), findsOneWidget);
    });
  });

  group('whole dashboard', () {
    testWidgets('the bell badge drops and the host is told', (tester) async {
      desktop(tester);
      final saved = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: DisciplineOfficerDashboardPage(
          initialNotifications: [note('1'), note('2')],
          onMarkNotificationRead: (id) async => saved.add(id),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();

      int badge() => tester
          .widget<HeaderIconButton>(find.byWidgetPredicate((w) =>
              w is HeaderIconButton && w.tooltip == 'Notifications'))
          .badgeCount;
      expect(badge(), 2);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title 1'));
      await tester.pumpAndSettle();
      await closeDetails(tester);

      expect(saved, ['1']);
      expect(badge(), 1);
    });
  });
}

/// The dropdown is 400 wide and 420 tall, shrinking only when the window is
/// too short to show that.
void _sizeTests() {
  Widget popover() => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: NotificationsPopover(
              notifications: [
                for (var i = 1; i <= 12; i++)
                  NotificationItemModel(
                    id: '$i',
                    title: 'Title $i',
                    message: 'Message $i',
                    timestamp: DateTime(2026, 10, 11, 9, i),
                  ),
              ],
              onViewAll: () {},
              onMarkAllRead: () {},
            ),
          ),
        ),
      );

  testWidgets('is 400 x 420', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(popover());
    final size = tester.getSize(find.byType(NotificationsPopover));
    expect(size.width, 400);
    expect(size.height, 420);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is capped to a short window instead of overflowing',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(popover());
    expect(tester.getSize(find.byType(NotificationsPopover)).height,
        lessThanOrEqualTo(400 - 96));
    expect(tester.takeException(), isNull);
  });
}
