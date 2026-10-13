import 'package:dashboard_layout/dashboard_layout.dart' show HeaderIconButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

/// The portal's bell shows the notifications its host hands it — fresh lists
/// land as they arrive, reads are reported back and survive a refresh.
void main() {
  StudentNotificationModel note(String id, {bool read = false}) =>
      StudentNotificationModel(
        id: id,
        senderName: 'STI Baliuag',
        senderRole: NotificationSenderRole.system,
        title: 'Notice $id',
        message: 'Body of notice $id',
        timestamp: DateTime(2026, 10, 12, 9, int.parse(id)),
        isRead: read,
      );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget page(
    List<StudentNotificationModel> notifications, {
    Future<void> Function(String)? onRead,
    Future<void> Function()? onReadAll,
  }) =>
      MaterialApp(
        home: StudentPortalHomePage(
          initialNotifications: notifications,
          onMarkNotificationRead: onRead,
          onMarkAllNotificationsRead: onReadAll,
        ),
      );

  Future<void> openBell(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Notifications').first);
    await tester.pumpAndSettle();
  }

  testWidgets('a notification that arrives later is shown', (tester) async {
    desktop(tester);
    await tester.pumpWidget(page([note('1')]));
    await tester.pumpAndSettle();

    // The host (a poll or a realtime push) hands down a longer list.
    await tester.pumpWidget(page([note('2'), note('1')]));
    await tester.pumpAndSettle();

    await openBell(tester);
    expect(find.text('Notice 2'), findsOneWidget);
    expect(find.text('Notice 1'), findsOneWidget);
  });

  testWidgets('opening one reports it read to the host', (tester) async {
    desktop(tester);
    final read = <String>[];
    await tester.pumpWidget(page(
      [note('1'), note('2')],
      onRead: (id) async => read.add(id),
    ));
    await tester.pumpAndSettle();

    await openBell(tester);
    await tester.tap(find.text('Notice 2'));
    await tester.pumpAndSettle();

    expect(read, ['2']);
  });

  testWidgets('"mark all read" is reported to the host', (tester) async {
    desktop(tester);
    var markedAll = 0;
    await tester.pumpWidget(page(
      [note('1'), note('2')],
      onReadAll: () async => markedAll++,
    ));
    await tester.pumpAndSettle();

    await openBell(tester);
    await tester.tap(find.textContaining('Mark all'));
    await tester.pumpAndSettle();

    expect(markedAll, 1);
  });

  testWidgets('one opened here stays read when a refresh still says unread',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(page([note('1')], onRead: (_) async {}));
    await tester.pumpAndSettle();

    String badge() => find
        .descendant(
          of: find
              .ancestor(
                of: find.byIcon(Icons.notifications_none_rounded),
                matching: find.byType(HeaderIconButton),
              )
              .first,
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .join();

    expect(badge(), '1');
    await openBell(tester);
    await tester.tap(find.text('Notice 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // The poll lands before the host's write did: notice 1 is still unread
    // over there, and notice 2 is new.
    await tester.pumpWidget(page([note('2'), note('1')], onRead: (_) async {}));
    await tester.pumpAndSettle();

    // Only the genuinely new one counts.
    expect(badge(), '1');
    expect(tester.takeException(), isNull);
  });
}
