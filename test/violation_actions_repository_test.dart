import 'package:capstone_dashboard/data/discipline_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

// Plain tests only: this talks to a real local socket.
void main() {
  late RecordingServer server;
  late SupabaseClient client;

  setUp(() async {
    server = RecordingServer();
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });
  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  test('lists a case\'s actions oldest first with who did them', () async {
    server.respond = (r) => (200, [
          {
            'id': 'a1',
            'action': 'Report filed',
            'detail': 'Awaiting classification',
            'actor_name': 'Ana Cruz',
            'actor_role': 'Teacher',
            'created_at': '2026-10-19T01:00:00Z',
          },
          {
            'id': 'a2',
            'action': 'Expired',
            'detail': null,
            'actor_name': 'System',
            'actor_role': null,
            'created_at': '2026-10-22T01:00:00Z',
          },
        ]);

    final actions =
        await DisciplineRepository(client).fetchViolationActions('v1');

    final req = server.requestTo('/violation_actions');
    expect(req.uri.queryParameters['violation_id'], 'eq.v1');
    expect(req.uri.queryParameters['order'], startsWith('created_at.asc'));
    expect(actions.map((a) => a.action), ['Report filed', 'Expired']);
    expect(actions.first.actorName, 'Ana Cruz');
    expect(actions.first.actorRole, 'Teacher');
    expect(actions.first.detail, 'Awaiting classification');
    expect(actions.last.actorName, 'System');
    expect(actions.last.at, DateTime.parse('2026-10-22T01:00:00Z').toLocal());
  });

  test('a database without the log table gives an empty history', () async {
    server.respond = (r) => (404, {
          'code': '42P01',
          'message': 'relation "public.violation_actions" does not exist'
        });
    expect(await DisciplineRepository(client).fetchViolationActions('v1'),
        isEmpty);
  });
}
