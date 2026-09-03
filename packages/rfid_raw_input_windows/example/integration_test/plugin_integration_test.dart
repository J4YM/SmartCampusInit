// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:rfid_raw_input_windows/rfid_raw_input_windows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('deviceFound answers without throwing', (WidgetTester tester) async {
    // No real reader is guaranteed to be attached in CI, so this just
    // exercises the method channel round trip end-to-end; the actual
    // hardware-matching behavior can only be confirmed manually against a
    // real device (see the rfid_raw_input_windows package README / the
    // attendance-tap-monitor plan's Task 7 Step 8).
    final found = await RfidRawInputReader.deviceFound(0x0000, 0x0000);
    expect(found, isFalse);
  });
}
