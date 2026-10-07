import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/data/registrar_mock_data.dart';
import 'package:registrar_module/pages/dashboard/registrar_dashboard_page.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: const RegistrarDashboardPage(),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  double size(WidgetTester tester, Finder f) =>
      tester.widget<Text>(f.first).style!.fontSize!;

  // The Student Need RFID card's text scales down in mobile view like the
  // rest of the system: title 16/18, summary 11/13. (Its "View All" is the
  // shared secondary pill button now, which has one size everywhere.)
  for (final (width, title, summary) in [
    (390.0, 16.0, 11.0),
    (1400.0, 18.0, 13.0),
  ]) {
    testWidgets('Student Need RFID text sizes at ${width.toInt()}px',
        (tester) async {
      await pumpAt(tester, width);
      expect(size(tester, find.text('Student Need RFID')), title);
      expect(size(tester, find.textContaining('Total students:')), summary);
    });
  }

  testWidgets('its student rows scale down on a phone too', (tester) async {
    await pumpAt(tester, 390);
    final needsRfid = RegistrarMockData.getStudents().firstWhere((s) => !s.hasRfid);
    // Inside that card only (the same student can also be in New Students).
    final card = find
        .ancestor(of: find.text('Student Need RFID'), matching: find.byType(BentoCard))
        .first;
    Finder inCard(String text) =>
        find.descendant(of: card, matching: find.text(text));
    final name = inCard(needsRfid.name);
    expect(name, findsWidgets, reason: 'a student needing an RFID card is listed');
    expect(size(tester, name), 12);
    expect(size(tester, inCard(needsRfid.studentId)), 10);
  });
}
