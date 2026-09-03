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
}
