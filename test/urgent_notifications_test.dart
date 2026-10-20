import 'package:capstone_dashboard/app/notification_alert.dart';
import 'package:capstone_dashboard/auth/app_role.dart';
import 'package:capstone_dashboard/data/notifications_repository.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show NotificationItemModel;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

NotificationItemModel _n(String id, {bool urgent = false, bool read = false}) =>
    NotificationItemModel(
      id: id,
      title: 'Title $id',
      message: 'Message $id',
      timestamp: DateTime(2026, 10, 20, 9),
      isRead: read,
      isUrgent: urgent,
    );

// No TestWidgetsFlutterBinding in this file: the repository tests below talk
// to a real local socket, which a test binding would answer with 400.
void main() {
  group('model', () {
    test('is not urgent by default', () {
      expect(_n('1').isUrgent, isFalse);
    });

    test('keeps the urgent flag through json and copyWith', () {
      final n = _n('1', urgent: true);
      expect(NotificationItemModel.fromJson(n.toJson()).isUrgent, isTrue);
      expect(n.copyWith(isRead: true).isUrgent, isTrue);
    });
  });

  group('NotificationAlert.onUrgent', () {
    var urgentSeen = <String>[];
    var rings = 0;

    setUp(() {
      urgentSeen = [];
      rings = 0;
      NotificationAlert.reset();
      NotificationAlert.onNew = () => rings++;
      NotificationAlert.onUrgent = (n) => urgentSeen.add(n.id);
    });
    tearDown(() {
      NotificationAlert.reset();
      NotificationAlert.onNew = null;
      NotificationAlert.onUrgent = null;
    });

    test('a new unread urgent notification fires once, and still rings', () {
      NotificationAlert.observe('DO|u1', [_n('1')]);
      NotificationAlert.observe('DO|u1', [_n('2', urgent: true), _n('1')]);
      NotificationAlert.observe('DO|u1', [_n('2', urgent: true), _n('1')]);

      expect(urgentSeen, ['2']);
      expect(rings, 1);
    });

    test('the first read after sign-in stays quiet', () {
      NotificationAlert.observe('DO|u1', [_n('1', urgent: true)]);
      expect(urgentSeen, isEmpty);
      expect(rings, 0);
    });

    test('urgent but already read, or new but not urgent, does not fire', () {
      NotificationAlert.observe('DO|u1', [_n('1')]);
      NotificationAlert.observe(
          'DO|u1', [_n('3', urgent: true, read: true), _n('2'), _n('1')]);
      expect(urgentSeen, isEmpty);
    });

    test('several urgent arrivals each fire', () {
      NotificationAlert.observe('DO|u1', [_n('1')]);
      NotificationAlert.observe(
          'DO|u1', [_n('3', urgent: true), _n('2', urgent: true), _n('1')]);
      expect(urgentSeen, unorderedEquals(['2', '3']));
      expect(rings, 1);
    });
  });

  group('NotificationsRepository', () {
    late RecordingServer server;
    late SupabaseClient client;

    setUp(() async {
      NotificationAlert.reset();
      server = RecordingServer();
      await server.start();
      client = SupabaseClient(server.url, 'anon-key');
    });
    tearDown(() async {
      await client.dispose();
      await server.stop();
    });

    Map<String, dynamic> row({bool? urgent}) => {
          'id': 'n1',
          'title': 'URGENT: violation report expired',
          'message': 'Review it now.',
          'created_at': '2026-10-20T01:00:00Z',
          'read_at': null,
          if (urgent != null) 'urgent': urgent,
        };

    test('reads the urgent flag', () async {
      server.respond = (r) => (200, [row(urgent: true)]);
      final items = await NotificationsRepository(client)
          .fetchForRole(AppRole.disciplineOfficer);
      expect(items.single.isUrgent, isTrue);
    });

    test('a database without the urgent column still lists notifications',
        () async {
      server.respond = (r) {
        final select = r.uri.queryParameters['select'] ?? '';
        if (select.contains('urgent')) {
          return (
            400,
            {'code': '42703', 'message': 'column notifications.urgent does not exist'}
          );
        }
        return (200, [row()]);
      };
      final items = await NotificationsRepository(client)
          .fetchForRole(AppRole.disciplineOfficer);
      expect(items.single.title, 'URGENT: violation report expired');
      expect(items.single.isUrgent, isFalse);
    });
  });
}
