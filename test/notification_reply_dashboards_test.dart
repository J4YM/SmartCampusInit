import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        DisciplineOfficerDashboardPage,
        NotificationItemModel,
        NotificationReplyHandler;
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// Every dashboard that can receive a message about a technical issue offers
/// a Reply in that notification's popup: Admin, Registrar and Professor (the
/// reporters) and the IT Technician (who receives new reports and replies).
void main() {
  final issueNote = NotificationItemModel(
    id: 'n1',
    title: 'Update on your technical issue report',
    message: 'The reader was replaced. Please test it.',
    timestamp: DateTime(2026, 10, 12, 9, 30),
    reportId: 'rep-1',
  );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Opens the bell, the notification, types [text] and sends it.
  Future<void> replyFromBell(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('Notifications').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update on your technical issue report').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mailbox-reply-field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mailbox-reply-field')), text);
    await tester.pump();
    await tester.tap(find.byKey(const Key('mailbox-reply-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('Professor', (tester) async {
    desktop(tester);
    NotificationItemModel? to;
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: ProfessorDashboardPage(
        initialNotifications: [issueNote],
        onReplyToNotification: (n, m) async {
          to = n;
          sent = m;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await replyFromBell(tester, 'Works now - professor');

    expect(to?.reportId, 'rep-1');
    expect(sent, 'Works now - professor');
  });

  testWidgets('Registrar', (tester) async {
    desktop(tester);
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: RegistrarDashboardPage(
        initialNotifications: [issueNote],
        onReplyToNotification: (n, m) async => sent = m,
      ),
    ));
    await tester.pumpAndSettle();

    await replyFromBell(tester, 'Works now - registrar');

    expect(sent, 'Works now - registrar');
  });

  testWidgets('Admin', (tester) async {
    desktop(tester);
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: AdminDashboardPage(
        initialNotifications: [issueNote],
        onReplyToNotification: (n, m) async => sent = m,
      ),
    ));
    await tester.pumpAndSettle();

    await replyFromBell(tester, 'Works now - admin');

    expect(sent, 'Works now - admin');
  });

  testWidgets('IT Technician', (tester) async {
    desktop(tester);
    String? sent;
    Widget blank(BuildContext _) => const SizedBox.shrink();
    await tester.pumpWidget(MaterialApp(
      home: ItTechnicianDashboardPage(
        initialNotifications: [issueNote],
        onReplyToNotification: (n, m) async => sent = m,
        studentRecordsTabBuilder: blank,
        readerDevicesTabBuilder: blank,
        technicalIssuesTabBuilder: blank,
        rfidRequestsTabBuilder: blank,
        idTemplatesTabBuilder: blank,
      ),
    ));
    await tester.pumpAndSettle();

    await replyFromBell(tester, 'On it - IT');

    expect(sent, 'On it - IT');
  });

  group('every other dashboard, through the app-wide handler', () {
    tearDown(() => NotificationReplyHandler.current = null);

    testWidgets('Guidance Counselor', (tester) async {
      desktop(tester);
      String? sent;
      NotificationReplyHandler.current = (n, m) async => sent = m;
      await tester.pumpWidget(MaterialApp(
        home: GuidanceCounselorDashboard(
          initialNotifications: [issueNote],
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ));
      await tester.pumpAndSettle();

      await replyFromBell(tester, 'Works now - guidance');

      expect(sent, 'Works now - guidance');
    });

    testWidgets('Discipline Officer', (tester) async {
      desktop(tester);
      String? sent;
      NotificationReplyHandler.current = (n, m) async => sent = m;
      await tester.pumpWidget(MaterialApp(
        home: DisciplineOfficerDashboardPage(
          initialNotifications: [issueNote],
        ),
      ));
      await tester.pumpAndSettle();

      await replyFromBell(tester, 'Works now - discipline');

      expect(sent, 'Works now - discipline');
    });
  });

  testWidgets('without a reply handler there is no reply box (demo mode)',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(MaterialApp(
      home: ProfessorDashboardPage(initialNotifications: [issueNote]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update on your technical issue report').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mailbox-reply-field')), findsNothing);
    expect(find.text('The reader was replaced. Please test it.'),
        findsWidgets);
  });
}
