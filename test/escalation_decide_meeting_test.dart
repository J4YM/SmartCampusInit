import 'package:capstone_dashboard/data/escalation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

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

  test('approving with a meeting sends the time and place', () async {
    await EscalationRepository(client).decide(
      'r1',
      approve: true,
      message: 'Please visit',
      actorName: 'Ms. Cruz',
      meetingAt: DateTime.utc(2026, 11, 3, 1, 30),
      meetingLocation: 'Guidance Office',
    );

    expect(server.requestTo('/rpc/decide_escalation_report').json, {
      'p_id': 'r1',
      'p_approve': true,
      'p_note': null,
      'p_message': 'Please visit',
      'p_actor_name': 'Ms. Cruz',
      'p_meeting_at': '2026-11-03T01:30:00.000Z',
      'p_meeting_location': 'Guidance Office',
    });
  });

  test('approving without a meeting, and rejecting, send no meeting fields',
      () async {
    final repo = EscalationRepository(client);
    await repo.decide('r1', approve: true);
    await repo.decide(
      'r2',
      approve: false,
      note: 'No',
      meetingAt: DateTime.utc(2026, 11, 3),
    );

    final bodies = server.requests
        .where((r) => r.path.endsWith('/rpc/decide_escalation_report'))
        .map((r) => r.json as Map)
        .toList();
    expect(bodies, hasLength(2));
    for (final b in bodies) {
      expect(b.containsKey('p_meeting_at'), isFalse);
      expect(b.containsKey('p_meeting_location'), isFalse);
    }
  });
}
