import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Unclaimed Profiles table's Actions column sits at the table's far
/// right edge — header label and every Assign button.
void main() {
  Future<void> show(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RfidMappingPage(unclaimedProfiles: [
        for (var i = 0; i < 3; i++)
          UnclaimedProfileModel(
            id: "p$i",
            fullName: "Parent Name $i / Guardian Surname",
            email: "parent$i@gmail.com",
            roleLabel: "Parent",
            isPending: i == 1,
            requestedAt: DateTime(2026, 10, 5, 6, 59),
          ),
      ]))),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  for (final size in const [Size(1600, 1200), Size(1200, 1200)]) {
    testWidgets('Assign buttons and the header sit on the far right '
        '(${size.width.toInt()}px)', (tester) async {
      await show(tester, size);

      final header = find.byType(DashboardTableHeader).first;
      final tableRight = tester.getRect(header).right;
      const edge = DashboardTableMetrics.horizontalPadding;

      final label = tester.getRect(find
          .descendant(of: header, matching: find.text('ACTIONS')));
      expect(label.right, closeTo(tableRight - edge, 1),
          reason: 'ACTIONS label is right-aligned');

      final buttons = find.descendant(
          of: find.byType(DashboardTableRow),
          matching: find.byType(SecondaryPillButton));
      expect(buttons, findsWidgets);
      for (var i = 0; i < buttons.evaluate().length; i++) {
        expect(tester.getRect(buttons.at(i)).right,
            closeTo(tableRight - edge, 1),
            reason: 'Assign button $i is at the far right');
      }
    });
  }
}
