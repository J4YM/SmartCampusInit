import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiosk/main.dart';

void main() {
  testWidgets('KioskApp builds', (WidgetTester tester) async {
    // Kiosk layout targets a tall display; default test surface is too short and overflows.
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const KioskApp());
    expect(find.textContaining('Virtual Admission'), findsWidgets);
  });
}
