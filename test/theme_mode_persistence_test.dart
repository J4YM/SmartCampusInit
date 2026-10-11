import 'package:capstone_dashboard/app/app_state_persistence.dart';
import 'package:capstone_dashboard/app/theme_mode_persistence.dart';
import 'package:dashboard_layout/dashboard_layout.dart'
    show PersistedThemeModeNotifier, ThemeModeStore;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The light/dark choice survives sign-out: every dashboard is torn down when
/// its user signs out, so the choice has to live outside it — and a different
/// (or the same) user signing in next starts in it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void resetStore() {
    ThemeModeStore.current = ThemeMode.light;
    ThemeModeStore.persist = null;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStatePersistence.resetForTesting();
    resetStore();
  });
  tearDown(resetStore);

  test('nothing saved: dashboards start light', () async {
    await restoreThemeMode();
    expect(PersistedThemeModeNotifier().value, ThemeMode.light);
  });

  test('a toggle is saved, and a dashboard built later starts in it',
      () async {
    await restoreThemeMode();

    final first = PersistedThemeModeNotifier();
    first.value = ThemeMode.dark;
    await Future<void>.delayed(Duration.zero);

    final persistence = await AppStatePersistence.instance();
    expect(persistence.themeMode, ThemeMode.dark);

    // "Sign out" disposes the dashboard; the next one starts dark.
    first.dispose();
    expect(PersistedThemeModeNotifier().value, ThemeMode.dark);
  });

  test('the choice is restored after an app restart', () async {
    SharedPreferences.setMockInitialValues({'app.themeMode': 'dark'});
    AppStatePersistence.resetForTesting();
    resetStore();

    await restoreThemeMode();

    expect(ThemeModeStore.current, ThemeMode.dark);
    expect(PersistedThemeModeNotifier().value, ThemeMode.dark);
  });

  test('signing out clears breadcrumbs but keeps the theme', () async {
    final persistence = await AppStatePersistence.instance();
    await persistence.setThemeMode(ThemeMode.dark);
    await persistence.setNavState('registrarTab', 'grades');

    await persistence.clearAllNavState();

    expect(persistence.navState('registrarTab'), isNull);
    expect(persistence.themeMode, ThemeMode.dark);
  });

  test('the store is inert until the app opts in (no leak between tests)',
      () async {
    final notifier = PersistedThemeModeNotifier();
    notifier.value = ThemeMode.dark;

    expect(notifier.value, ThemeMode.dark);
    expect(ThemeModeStore.current, ThemeMode.light);
    expect(PersistedThemeModeNotifier().value, ThemeMode.light);
  });

  test('a failing save never breaks toggling', () async {
    ThemeModeStore.persist = (_) async => throw StateError('disk full');
    final notifier = PersistedThemeModeNotifier();

    notifier.value = ThemeMode.dark;
    await Future<void>.delayed(Duration.zero);

    expect(notifier.value, ThemeMode.dark);
    expect(ThemeModeStore.current, ThemeMode.dark);
  });

  testWidgets('a real dashboard opens in the saved theme', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<Brightness> openDashboard() async {
      await tester.pumpWidget(MaterialApp(
        home: GuidanceCounselorDashboard(
          systemOverviewTabBuilder: (_) => const SizedBox.shrink(),
        ),
      ));
      await tester.pumpAndSettle();
      // The sub-nav sits inside the dashboard's own Theme.
      return Theme.of(tester.element(find.text('Overview').first)).brightness;
    }

    expect(await openDashboard(), Brightness.light);

    // Sign out (tear the dashboard down), then sign in again after the user
    // had chosen dark.
    await tester.pumpWidget(const SizedBox.shrink());
    ThemeModeStore.current = ThemeMode.dark;

    expect(await openDashboard(), Brightness.dark);
  });
}
