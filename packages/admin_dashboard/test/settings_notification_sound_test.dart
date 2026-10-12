import 'package:admin_dashboard/pages/settings/settings_page.dart';
import 'package:dashboard_layout/dashboard_layout.dart'
    show NotificationSoundSettings;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Admin has no avatar dropdown, so its notification-sound switch lives in
/// Settings > Display Preferences, next to Theme Mode.
void main() {
  tearDown(() => NotificationSoundSettings.enabled.value = true);

  testWidgets('Display Preferences has a Notification Sound On/Off',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SettingsPage.empty())),
    );
    await tester.pump();
    await tester.tap(find.text('Display Preferences'));
    await tester.pumpAndSettle();

    expect(find.text('Notification Sound'), findsOneWidget);
    expect(NotificationSoundSettings.enabled.value, isTrue);

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(NotificationSoundSettings.enabled.value, isFalse);

    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    expect(NotificationSoundSettings.enabled.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
