import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:capstone_dashboard/ui/dashboard_page.dart';

void main() {
  testWidgets('Dashboard shows header', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DashboardPage()),
    );
    await tester.pump();

    expect(find.text('RFID Management Dashboard'), findsOneWidget);
  });

  testWidgets('Admin dashboard shows the System Overview screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AdminDashboardPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('System Overview'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
