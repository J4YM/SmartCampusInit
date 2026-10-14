import 'package:capstone_dashboard/kiosk/security_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_kiosk_module/student_kiosk.dart';

void main() {
  testWidgets(
      'tapping the student search shows the on-screen keyboard and typing '
      'with it searches', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final queries = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SecurityReportScreen(
        officerName: 'Officer',
        offenseOptions: const [],
        onSearchStudents: (q) async {
          queries.add(q);
          return const [];
        },
        onSubmit: (_) {},
      ),
    ));

    expect(find.byType(KioskOnScreenKeyboard), findsNothing);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(find.byType(KioskOnScreenKeyboard), findsOneWidget);

    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pump();

    expect(queries, ['2', '20']);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '20');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KioskOnScreenKeyboard), findsNothing);
  });
}
