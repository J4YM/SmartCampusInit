import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/pages/dashboard/professor_dashboard_page.dart';

void main() {
  test('the label says the student did not tap out', () {
    final tapIn = DateTime(2026, 10, 1, 8, 5);
    expect(TapInPill.labelFor(tapIn, null, didNotTapOut: true),
        'In 8:05 AM · Did not tap out');
    // A real tap-out always wins over the flag.
    expect(
        TapInPill.labelFor(tapIn, DateTime(2026, 10, 1, 15, 10),
            didNotTapOut: true),
        'In 8:05 AM · Out 3:10 PM');
    // Without a tap-in there is nothing to say.
    expect(TapInPill.labelFor(null, null, didNotTapOut: true), 'No tap yet');
    expect(TapInPill.labelFor(tapIn, null), 'Tapped in 8:05 AM');
  });

  testWidgets('the pill shows it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TapInPill(
          tapInAt: DateTime(2026, 10, 1, 8, 5),
          didNotTapOut: true,
        ),
      ),
    ));
    expect(find.text('In 8:05 AM · Did not tap out'), findsOneWidget);
  });

  test('a record knows it did not tap out, false by default', () {
    const record = StudentAttendanceRecordModel(
      id: 's1',
      studentName: 'Ana Lim',
      studentId: '2024-001',
      presentCount: 0,
      totalSessions: 0,
      absentCount: 0,
    );
    expect(record.kioskDidNotTapOut, isFalse);
    const missed = StudentAttendanceRecordModel(
      id: 's2',
      studentName: 'Ben Ong',
      studentId: '2024-002',
      presentCount: 0,
      totalSessions: 0,
      absentCount: 0,
      kioskDidNotTapOut: true,
    );
    expect(missed.kioskDidNotTapOut, isTrue);
  });
}
