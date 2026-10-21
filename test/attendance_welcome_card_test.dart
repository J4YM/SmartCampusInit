import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk/kiosk_module.dart';

Future<void> _pump(WidgetTester tester, {DateTime? tappedAt}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AttendanceWelcomeCard(
        name: 'Juan Dela Cruz',
        courseSection: 'BSIT - 3B',
        tappedAt: tappedAt,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the welcome card shows when the attendance was recorded',
      (tester) async {
    await _pump(tester, tappedAt: DateTime(2026, 10, 20, 15, 5));
    expect(find.byKey(const Key('tap-datetime')), findsOneWidget);
    expect(find.text('Tue, Oct 20, 2026 · 3:05 PM'), findsOneWidget);
  });

  testWidgets('with no known time the line is simply absent', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('tap-datetime')), findsNothing);
  });

  test('formatTapDateTime pads minutes and uses 12-hour time', () {
    expect(formatTapDateTime(DateTime(2026, 2, 9, 0, 7)),
        'Mon, Feb 9, 2026 · 12:07 AM');
    expect(formatTapDateTime(DateTime(2026, 2, 9, 23, 59)),
        'Mon, Feb 9, 2026 · 11:59 PM');
  });
}
