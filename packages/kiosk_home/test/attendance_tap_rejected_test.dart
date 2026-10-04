import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk/kiosk_module.dart';

void main() {
  testWidgets(
    'a rejected attendance tap shows the rule message, not the generic '
    'network-failure fallback',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: VirtualAdmissionKioskScreen(
            identifyStudent: (_) async => null,
            onStudentIdentified: (_, __) {},
            recordAttendanceTap: (_) async {
              throw AttendanceTapRejected(
                'Please wait at least 1 hour after tapping in before '
                'tapping out.',
              );
            },
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, 'some-uid');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Please wait at least 1 hour after tapping in before '
          'tapping out.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Could not verify RFID'),
        findsNothing,
      );
    },
  );
}
