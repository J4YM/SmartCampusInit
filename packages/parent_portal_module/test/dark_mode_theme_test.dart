import 'package:dashboard_layout/dashboard_layout.dart' show ThemeModeStore;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart';

/// The page's theme must be a REAL dark theme in dark mode, not the app's light
/// one with only `brightness` flipped — otherwise any text without a color of
/// its own keeps the light theme's dark default and is invisible on dark cards.
void main() {
  testWidgets('dark mode gives uncolored text a light default', (tester) async {
    final previous = ThemeModeStore.current;
    ThemeModeStore.current = ThemeMode.dark;
    addTearDown(() => ThemeModeStore.current = previous);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ParentPortalHomePage()));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium!.color!.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('light mode keeps a dark default text color', (tester) async {
    final previous = ThemeModeStore.current;
    ThemeModeStore.current = ThemeMode.light;
    addTearDown(() => ThemeModeStore.current = previous);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ParentPortalHomePage()));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.light);
    expect(theme.textTheme.bodyMedium!.color!.computeLuminance(), lessThan(0.5));
  });
}
