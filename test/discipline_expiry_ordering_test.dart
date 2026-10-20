import 'package:capstone_dashboard/data/discipline_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

Map<String, dynamic> _row(
  String id, {
  required String createdAt,
  String? expiredAt,
}) =>
    {
      'id': id,
      'student_id': 's-$id',
      'offense_id': 'o1',
      'is_escalated': false,
      'status': 'Pending',
      'created_at': createdAt,
      'incident_at': createdAt,
      'expired_at': expiredAt,
      'archived_at': null,
      'students': {
        'student_number': '2024-$id',
        'profiles': {'first_name': 'Student', 'last_name': id},
        'sections': {'name': 'BSIT 1A'},
      },
      'handbook_offenses': {'description': 'Smoking', 'category': 'Major_A'},
      'profiles': {'first_name': 'Prof', 'last_name': 'Cruz'},
    };

// Plain tests only (no TestWidgetsFlutterBinding): this talks to a real
// local socket.
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

  test('expired cases stay in the active queue, first, and are marked',
      () async {
    server.respond = (r) {
      if (r.uri.queryParameters['select'] == 'student_id') {
        return (200, [
          {'student_id': 's-a'},
          {'student_id': 's-b'},
          {'student_id': 's-c'},
        ]);
      }
      // Newest first, the way the database returns them.
      return (200, [
        _row('a', createdAt: '2026-10-20T08:00:00Z'),
        _row('b', createdAt: '2026-10-15T08:00:00Z',
            expiredAt: '2026-10-20T07:00:00Z'),
        _row('c', createdAt: '2026-10-10T08:00:00Z',
            expiredAt: '2026-10-18T07:00:00Z'),
      ]);
    };

    final cases = await DisciplineRepository(client).fetchActiveViolations();

    expect(cases.map((c) => c.id), ['c', 'b', 'a']); // oldest-expired first
    expect(cases.map((c) => c.isExpired), [true, true, false]);
  });

  test('the active-queue request does not filter expired cases out', () async {
    await DisciplineRepository(client).fetchActiveViolations();
    final queries = server.requests
        .map((r) => r.uri.queryParameters)
        .where((q) => (q['select'] ?? '').contains('status'));
    expect(queries.every((q) => !q.containsKey('expired_at')), isTrue);
  });
}
