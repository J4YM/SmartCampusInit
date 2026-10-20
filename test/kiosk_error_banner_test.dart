import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk/kiosk_module.dart';

Future<void> _scan(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1366, 768));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: VirtualAdmissionKioskScreen(
      identifyStudent: (_) async => null,
      onStudentIdentified: (_, __) {},
    ),
  ));
  await tester.enterText(find.byType(TextField), 'unknown-card');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('an unknown card raises a large, unmistakable error',
      (tester) async {
    await _scan(tester);

    final banner = find.byKey(const Key('kiosk-error-banner'));
    expect(banner, findsOneWidget);
    expect(find.text('Invalid RFID'), findsOneWidget);

    final text = tester.widget<Text>(find.text('Invalid RFID'));
    expect(text.style!.fontSize, greaterThanOrEqualTo(28));
    // Solid red with white text, not a pale pill.
    final box = tester.widget<Container>(banner);
    final color = (box.decoration as BoxDecoration).color!;
    expect(color.red, greaterThan(150));
    expect(color.green, lessThan(90));
    expect(text.style!.color, Colors.white);
    // Tall enough to be seen from a distance.
    expect(tester.getSize(banner).height, greaterThanOrEqualTo(80));
  });

  testWidgets('the error stays long enough to be read, then clears',
      (tester) async {
    await _scan(tester);

    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const Key('kiosk-error-banner')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('kiosk-error-banner')), findsNothing);
  });
}
