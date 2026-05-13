import 'package:flutter_test/flutter_test.dart';

import 'package:student_kiosk_module/main.dart';

void main() {
  testWidgets('Kiosk screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const StudentKioskApp());

    expect(find.text('STI College Baliuag'), findsOneWidget);
    expect(find.text('Virtual Admission Kiosk'), findsOneWidget);
    expect(find.text('0 violation(s) selected'), findsOneWidget);
  });
}
