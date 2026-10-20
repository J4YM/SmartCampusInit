import 'dart:async';

import 'package:attendance_display/tap_display_data.dart';
import 'package:attendance_display/tap_display_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows idle state, then a welcome card on a tap, then reverts',
      (tester) async {
    final controller = StreamController<TapDisplayData>();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: TapDisplayScreen(tapStream: controller.stream),
    ));

    expect(find.text('Tap your ID to check in'), findsOneWidget);

    controller.add(const TapDisplayData(
      name: 'Juan Dela Cruz',
      section: 'BSIT - 3B',
      photoSignedUrl: null,
      direction: 'in',
    ));
    await tester.pump();

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('BSIT - 3B'), findsOneWidget);
    expect(find.textContaining('Welcome'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Tap your ID to check in'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsNothing);
  });

  testWidgets('the welcome card shows the date and time of the tap',
      (tester) async {
    final controller = StreamController<TapDisplayData>();
    addTearDown(controller.close);
    await tester.pumpWidget(MaterialApp(
      home: TapDisplayScreen(tapStream: controller.stream),
    ));

    controller.add(TapDisplayData(
      name: 'Juan Dela Cruz',
      section: 'BSIT - 3B',
      photoSignedUrl: null,
      direction: 'in',
      tappedAt: DateTime(2026, 10, 20, 7, 45),
    ));
    await tester.pump();

    expect(find.text('Tue, Oct 20, 2026 · 7:45 AM'), findsOneWidget);
  });

  testWidgets('an unknown card is an obvious error, not a welcome',
      (tester) async {
    final controller = StreamController<TapDisplayData>();
    addTearDown(controller.close);
    await tester.pumpWidget(MaterialApp(
      home: TapDisplayScreen(tapStream: controller.stream),
    ));

    controller.add(formatTapDisplayData(
      firstName: '',
      lastName: '',
      sectionName: '',
      photoSignedUrl: null,
      direction: 'in',
      tappedAt: DateTime(2026, 10, 20, 7, 45),
    ));
    await tester.pump();

    expect(find.byKey(const Key('card-not-recognized')), findsOneWidget);
    expect(find.text('Card not recognized'), findsOneWidget);
    expect(find.textContaining('Welcome'), findsNothing);
    expect(find.text('Unregistered card'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Tap your ID to check in'), findsOneWidget);
  });

  test('formatTapDateTime reads like a clock, in 12-hour time', () {
    expect(formatTapDateTime(DateTime(2026, 10, 20, 0, 5)),
        'Tue, Oct 20, 2026 · 12:05 AM');
    expect(formatTapDateTime(DateTime(2026, 1, 3, 13, 30)),
        'Sat, Jan 3, 2026 · 1:30 PM');
    expect(formatTapDateTime(DateTime(2026, 12, 31, 12, 0)),
        'Thu, Dec 31, 2026 · 12:00 PM');
  });
}
