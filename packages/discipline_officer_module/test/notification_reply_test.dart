import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A notification about a technical issue can be answered from its details
/// popup — from the bell dropdown and from the "View all" list alike. Any
/// other notification has no reply box.
void main() {
  NotificationItemModel note(String id, {String? reportId}) =>
      NotificationItemModel(
        id: id,
        title: 'Update on your technical issue report',
        message: 'We replaced the reader, please test it. ($id)',
        timestamp: DateTime(2026, 10, 12, 9, 30),
        reportId: reportId,
      );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // The app-wide handler is process-wide state: never let it leak across tests.
  tearDown(() => NotificationReplyHandler.current = null);

  Widget popover(
    List<NotificationItemModel> items, {
    Future<void> Function(NotificationItemModel, String)? onReply,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: NotificationsPopover(
              notifications: items,
              onViewAll: () {},
              onMarkAllRead: () {},
              onReplyToNotification: onReply,
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, String title) async {
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
  }

  FilledButton sendButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('mailbox-reply-send')),
          matching: find.byType(FilledButton),
        ),
      );

  testWidgets('a technical-issue notification offers a reply that is sent '
      'with the notification', (tester) async {
    desktop(tester);
    NotificationItemModel? to;
    String? sent;
    await tester.pumpWidget(popover(
      [note('1', reportId: 'rep-1')],
      onReply: (n, m) async {
        to = n;
        sent = m;
      },
    ));
    await open(tester, 'Update on your technical issue report');

    expect(find.byKey(const Key('mailbox-reply-field')), findsOneWidget);
    // Nothing to send yet.
    expect(sendButton(tester).onPressed, isNull);

    await tester.enterText(
        find.byKey(const Key('mailbox-reply-field')), 'It works now, thanks!');
    await tester.pump();
    expect(sendButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('mailbox-reply-send')));
    await tester.pumpAndSettle();

    expect(to?.id, '1');
    expect(to?.reportId, 'rep-1');
    expect(sent, 'It works now, thanks!');
    // Confirmed, and the box is clear for another.
    expect(find.byKey(const Key('mailbox-reply-sent')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mailbox-reply-field')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a failed reply keeps what was typed and says why',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(popover(
      [note('1', reportId: 'rep-1')],
      onReply: (_, __) async => throw Exception('write rejected'),
    ));
    await open(tester, 'Update on your technical issue report');

    await tester.enterText(
        find.byKey(const Key('mailbox-reply-field')), 'Still broken');
    await tester.pump();
    await tester.tap(find.byKey(const Key('mailbox-reply-send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not send the reply'), findsOneWidget);
    expect(find.byKey(const Key('mailbox-reply-sent')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mailbox-reply-field')))
          .controller!
          .text,
      'Still broken',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a notification that is not about a technical issue, or a dashboard with no reply handler: no reply box',
      (tester) async {
    desktop(tester);
    NotificationReplyHandler.current = (_, __) async {};
    // Some other kind of notification.
    await tester.pumpWidget(popover([
      NotificationItemModel(
        id: '9',
        title: 'Violation Count Exceeded',
        message: 'A student passed the violation limit.',
        timestamp: DateTime(2026, 10, 12),
      ),
    ]));
    await open(tester, 'Violation Count Exceeded');
    expect(find.byKey(const Key('mailbox-reply-field')), findsNothing);
    expect(find.text('Send reply'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // About a technical issue, but nobody can answer it (no handler anywhere).
    NotificationReplyHandler.current = null;
    await tester.pumpWidget(popover([note('2', reportId: 'rep-2')]));
    await open(tester, 'Update on your technical issue report');
    expect(find.byKey(const Key('mailbox-reply-field')), findsNothing);
  });

  testWidgets('a message from before the report link existed (no report id) '
      'is still answerable, through the app-wide handler', (tester) async {
    desktop(tester);
    NotificationItemModel? to;
    String? sent;
    NotificationReplyHandler.current = (n, m) async {
      to = n;
      sent = m;
    };
    // The popup in the user's screenshot: IT's "okay na?", no report id.
    await tester.pumpWidget(popover([
      NotificationItemModel(
        id: '7',
        title: 'Update on your technical issue report',
        message: 'okay na?',
        timestamp: DateTime(2026, 10, 12, 10, 7),
      ),
    ]));
    await open(tester, 'Update on your technical issue report');

    expect(find.byKey(const Key('mailbox-reply-field')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('mailbox-reply-field')), 'Opo, okay na po');
    await tester.pump();
    await tester.tap(find.byKey(const Key('mailbox-reply-send')));
    await tester.pumpAndSettle();

    expect(to?.id, '7');
    expect(to?.reportId, isNull);
    expect(sent, 'Opo, okay na po');
  });

  testWidgets('a dashboard\'s own handler wins over the app-wide one',
      (tester) async {
    desktop(tester);
    var appWide = 0;
    var own = 0;
    NotificationReplyHandler.current = (_, __) async => appWide++;
    await tester.pumpWidget(popover(
      [note('1', reportId: 'rep-1')],
      onReply: (_, __) async => own++,
    ));
    await open(tester, 'Update on your technical issue report');
    await tester.enterText(find.byKey(const Key('mailbox-reply-field')), 'Hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('mailbox-reply-send')));
    await tester.pumpAndSettle();

    expect(own, 1);
    expect(appWide, 0);
  });

  test('which titles count as technical-issue messages', () {
    NotificationItemModel titled(String t) => NotificationItemModel(
          id: 'x',
          title: t,
          message: 'm',
          timestamp: DateTime(2026, 10, 12),
        );
    expect(titled('Update on your technical issue report').isTechnicalIssue,
        isTrue);
    expect(titled('New reply on a technical issue report').isTechnicalIssue,
        isTrue);
    expect(titled('New technical issue reported').isTechnicalIssue, isTrue);
    expect(titled('Violation Count Exceeded').isTechnicalIssue, isFalse);
    expect(note('1', reportId: 'rep').isTechnicalIssue, isTrue);
  });

  testWidgets('the "View all" list offers the same reply', (tester) async {
    desktop(tester);
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NotificationsListView(
            notifications: [note('1', reportId: 'rep-1')],
            onReplyToNotification: (n, m) async => sent = m,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await open(tester, 'Update on your technical issue report');
    await tester.enterText(
        find.byKey(const Key('mailbox-reply-field')), 'Thank you');
    await tester.pump();
    await tester.tap(find.byKey(const Key('mailbox-reply-send')));
    await tester.pumpAndSettle();

    expect(sent, 'Thank you');
  });

  test('the report id survives a copy and a JSON round trip', () {
    final n = note('1', reportId: 'rep-1');
    expect(n.copyWith(isRead: true).reportId, 'rep-1');
    expect(NotificationItemModel.fromJson(n.toJson()).reportId, 'rep-1');
    expect(NotificationItemModel.fromJson(note('2').toJson()).reportId, isNull);
  });
}
