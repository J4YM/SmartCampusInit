import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capstone_dashboard/main_it_technician.dart';

Future<void> _signIn(
  WidgetTester tester,
  String username,
  String password,
) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), username);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.text('Login'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the login screen, not the dashboard, before signing in',
      (tester) async {
    await tester.pumpWidget(const ItTechnicianStandaloneApp());
    await tester.pump();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('IT Technician Dashboard'), findsNothing);
  });

  testWidgets(
      'rejects a non-IT_Technician demo account and stays on the login screen',
      (tester) async {
    await tester.pumpWidget(const ItTechnicianStandaloneApp());
    await tester.pump();

    await _signIn(tester, 'admin', 'Capstone2026!');

    expect(find.text('IT Technician Dashboard'), findsNothing);
    expect(
      find.text('This device is for IT Technician accounts only.'),
      findsOneWidget,
    );
  });

  testWidgets('signs an IT_Technician demo account into the dashboard',
      (tester) async {
    await tester.pumpWidget(const ItTechnicianStandaloneApp());
    await tester.pump();

    await _signIn(tester, 'ittech.demo', 'ITTech2026!');

    expect(find.text('IT Technician Dashboard'), findsOneWidget);
  });
}
