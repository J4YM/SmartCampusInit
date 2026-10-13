import 'package:capstone_dashboard/app/notification_alert.dart';
import 'package:capstone_dashboard/app/notification_sound.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter_test/flutter_test.dart';

/// A newly sent notification makes its sound: once per arrival, never for the
/// ones already waiting when someone signs in, never for one already read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NotificationItemModel n(String id, {bool read = false}) =>
      NotificationItemModel(
        id: id,
        title: 'Title $id',
        message: 'Message $id',
        timestamp: DateTime(2026, 10, 12, 10),
        isRead: read,
      );

  var rings = 0;

  setUp(() {
    rings = 0;
    NotificationAlert.reset();
    NotificationAlert.onNew = () => rings++;
  });
  tearDown(() {
    NotificationAlert.reset();
    NotificationAlert.onNew = null;
  });

  test('the first read only remembers what is already there', () {
    final rang = NotificationAlert.observe('Teacher|u1', [n('1'), n('2'), n('3')]);

    expect(rang, isFalse);
    expect(rings, 0);
  });

  test('a notification that arrives afterwards rings once', () {
    NotificationAlert.observe('Teacher|u1', [n('1')]);

    final rang = NotificationAlert.observe('Teacher|u1', [n('2'), n('1')]);

    expect(rang, isTrue);
    expect(rings, 1);
  });

  test('several arriving together ring once, not once each', () {
    NotificationAlert.observe('Teacher|u1', [n('1')]);

    NotificationAlert.observe('Teacher|u1', [n('4'), n('3'), n('2'), n('1')]);

    expect(rings, 1);
  });

  test('the same list read again (a poll with nothing new) is silent', () {
    NotificationAlert.observe('Teacher|u1', [n('1')]);
    NotificationAlert.observe('Teacher|u1', [n('2'), n('1')]);
    NotificationAlert.observe('Teacher|u1', [n('2'), n('1')]);
    NotificationAlert.observe('Teacher|u1', [n('2'), n('1')]);

    expect(rings, 1);
  });

  test('a new notification that is already read does not ring', () {
    NotificationAlert.observe('Teacher|u1', [n('1')]);

    NotificationAlert.observe('Teacher|u1', [n('2', read: true), n('1')]);

    expect(rings, 0);
  });

  test('one that was deleted and shows up again does not ring again', () {
    NotificationAlert.observe('Teacher|u1', [n('1'), n('2')]);
    NotificationAlert.observe('Teacher|u1', [n('1')]); // 2 gone for a moment
    NotificationAlert.observe('Teacher|u1', [n('1'), n('2')]);

    expect(rings, 0);
  });

  test('each person is tracked on their own', () {
    NotificationAlert.observe('Teacher|u1', [n('1')]);
    // A different person's first read is quiet even though ids differ.
    NotificationAlert.observe('Registrar|u2', [n('9')]);
    expect(rings, 0);

    NotificationAlert.observe('Registrar|u2', [n('10'), n('9')]);
    expect(rings, 1);
  });

  test('after a reset (sign-out) the next first read is quiet again', () {
    NotificationAlert.observe('Teacher|u1', [n('1')]);
    NotificationAlert.reset();

    NotificationAlert.observe('Teacher|u1', [n('2'), n('1')]);

    expect(rings, 0);
  });

  test('nothing wired (onNew null) is harmless', () {
    NotificationAlert.onNew = null;
    NotificationAlert.observe('Teacher|u1', [n('1')]);

    expect(NotificationAlert.observe('Teacher|u1', [n('2'), n('1')]), isTrue);
  });

  test('playing the sound never throws, even with no audio backend',
      () async {
    await expectLater(playNotificationSound(), completes);
  });
}
