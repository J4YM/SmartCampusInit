import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/attendance_models.dart';
import 'package:student_portal_module/widgets/day_detail_sheet.dart';

Future<void> _open(WidgetTester tester, {required bool didNotTapOut}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDayDetailSheet(
            context,
            DateTime(2026, 10, 20),
            const <AttendanceEntry>[],
            isDarkMode: false,
            didNotTapOut: didNotTapOut,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a day the student did not tap out says so', (tester) async {
    await _open(tester, didNotTapOut: true);
    expect(find.byKey(const Key('day-did-not-tap-out')), findsOneWidget);
    expect(find.text('Did not tap out'), findsOneWidget);
  });

  testWidgets('an ordinary day does not', (tester) async {
    await _open(tester, didNotTapOut: false);
    expect(find.byKey(const Key('day-did-not-tap-out')), findsNothing);
  });
}
