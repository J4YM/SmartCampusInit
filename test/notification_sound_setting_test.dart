import 'package:capstone_dashboard/app/app_state_persistence.dart';
import 'package:capstone_dashboard/app/notification_alert.dart';
import 'package:capstone_dashboard/app/notification_sound_persistence.dart';
import 'package:dashboard_layout/dashboard_layout.dart'
    show NotificationSoundSettings;
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show AccountProfileMenu, NotificationItemModel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The notification sound has an on/off switch in every dashboard's profile
/// menu; it is remembered across sign-out and restart, and when it is off a
/// new notification stays silent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStatePersistence.resetForTesting();
    NotificationAlert.reset();
    NotificationSoundSettings.enabled.value = true;
    NotificationSoundSettings.persist = null;
  });
  tearDown(() {
    NotificationAlert.reset();
    NotificationAlert.onNew = null;
    NotificationSoundSettings.enabled.value = true;
    NotificationSoundSettings.persist = null;
  });

  Widget menu({bool dark = false}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: AccountProfileMenu(
              userName: 'Ana Reyes',
              onViewProfile: () {},
              isDarkMode: dark,
              onToggleDarkMode: () {},
              onLogout: () {},
            ),
          ),
        ),
      );

  group('the profile menu', () {
    testWidgets('has a Notification Sound row that flips the setting',
        (tester) async {
      await tester.pumpWidget(menu());

      expect(find.text('Notification Sound'), findsOneWidget);
      expect(find.byKey(const Key('sound-switch-on')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notification-sound-toggle')));
      await tester.pump();

      expect(NotificationSoundSettings.enabled.value, isFalse);
      expect(find.byKey(const Key('sound-switch-off')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notification-sound-toggle')));
      await tester.pump();

      expect(NotificationSoundSettings.enabled.value, isTrue);
      expect(find.byKey(const Key('sound-switch-on')), findsOneWidget);
    });

    testWidgets('reflects a setting already off, in the dark theme too',
        (tester) async {
      NotificationSoundSettings.enabled.value = false;
      await tester.pumpWidget(menu(dark: true));

      expect(find.byKey(const Key('sound-switch-off')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps its other rows', (tester) async {
      await tester.pumpWidget(menu());

      expect(find.text('Profile Settings'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });
  });

  group('the setting', () {
    NotificationItemModel note(String id) => NotificationItemModel(
          id: id,
          title: 'T$id',
          message: 'M$id',
          timestamp: DateTime(2026, 10, 12),
        );

    test('on: a new notification rings; off: it is silent', () async {
      var rings = 0;
      await setUpNotificationSound();
      // Count calls to the sound itself by wrapping what setUp installed.
      final installed = NotificationAlert.onNew!;
      NotificationAlert.onNew = () {
        if (NotificationSoundSettings.enabled.value) rings++;
        installed();
      };

      NotificationAlert.observe('Teacher|u1', [note('1')]);
      NotificationAlert.observe('Teacher|u1', [note('2'), note('1')]);
      expect(rings, 1);

      NotificationSoundSettings.set(false);
      NotificationAlert.observe('Teacher|u1', [note('3'), note('2'), note('1')]);
      expect(rings, 1, reason: 'off: silent');

      NotificationSoundSettings.set(true);
      NotificationAlert.observe(
          'Teacher|u1', [note('4'), note('3'), note('2'), note('1')]);
      expect(rings, 2);
    });

    test('is saved, and restored on the next start', () async {
      await setUpNotificationSound();
      NotificationSoundSettings.set(false);
      await Future<void>.delayed(Duration.zero);

      final persistence = await AppStatePersistence.instance();
      expect(persistence.notificationSoundEnabled, isFalse);

      // "Restart": fresh state, same storage.
      NotificationSoundSettings.enabled.value = true;
      NotificationSoundSettings.persist = null;
      AppStatePersistence.resetForTesting();
      await setUpNotificationSound();

      expect(NotificationSoundSettings.enabled.value, isFalse);
    });

    test('starts on when nothing was ever saved', () async {
      await setUpNotificationSound();

      expect(NotificationSoundSettings.enabled.value, isTrue);
    });

    test('signing out (clearing nav state) does not reset it', () async {
      await setUpNotificationSound();
      NotificationSoundSettings.set(false);
      await Future<void>.delayed(Duration.zero);

      final persistence = await AppStatePersistence.instance();
      await persistence.clearAllNavState();

      expect(persistence.notificationSoundEnabled, isFalse);
    });
  });
}
