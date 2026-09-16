import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiosk/main.dart';

void main() {
  testWidgets('KioskApp builds', (WidgetTester tester) async {
    // Default test surface is too short and overflows; use a landscape
    // kiosk-monitor-sized surface (Figma node 617:1445 is landscape).
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const KioskApp());
    expect(find.textContaining('COLLEGE'), findsWidgets);
    expect(find.text('Scan your RFID'), findsOneWidget);
  });
}
