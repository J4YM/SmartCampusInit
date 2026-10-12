import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Notifications tab holds only the Automated Trigger Rules card — the
/// under-development SMS Gateway (PhilSMS) and Email (SMTP) cards are gone.
void main() {
  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationsPage.empty()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the SMS Gateway and Email (SMTP) cards are not shown',
      (tester) async {
    await pump(tester, width: 1500);

    expect(find.text('SMS Gateway (PhilSMS)'), findsNothing);
    expect(find.text('Email (SMTP)'), findsNothing);
    expect(find.text('Under Development'), findsNothing);
    expect(find.text('API Key'), findsNothing);
    expect(find.text('SMTP Host'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the trigger rules card remains, full width', (tester) async {
    await pump(tester, width: 1500);

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Automated Trigger Rules'), findsOneWidget);
    // Not squeezed into half the page now that it is the only card: it is
    // wider than half of the page's content width.
    final card = tester.getSize(find.ancestor(
      of: find.text('Automated Trigger Rules'),
      matching: find.byType(SizedBox),
    ).first);
    expect(card.width, greaterThan(750));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone: it renders without overflow', (tester) async {
    await pump(tester, width: 380);

    expect(find.text('Automated Trigger Rules'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
