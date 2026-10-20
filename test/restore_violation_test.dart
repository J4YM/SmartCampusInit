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

  test('restoring clears the archive and expiry state and restarts the clock',
      () async {
    await DisciplineRepository(client).restoreViolation('v1');
    final patch = server.requests.lastWhere((r) => r.method == 'PATCH').json;
    expect(patch['archived_at'], isNull);
    expect(patch['expired_at'], isNull);
    expect(patch['restored_at'], isNotNull);
    // The 12-hour warning and the expiry alert may fire again.
    expect(patch.containsKey('expiry_warned_at'), isTrue);
    expect(patch['expiry_warned_at'], isNull);
    expect(patch.containsKey('expiry_notified_at'), isTrue);
    expect(patch['expiry_notified_at'], isNull);
  });

  test('a database without the warning columns still restores the case',
      () async {
    server.respond = (r) {
      if (r.method == 'PATCH' && r.body.contains('expiry_warned_at')) {
        return (
          400,
          {
            'code': '42703',
            'message': 'column "expiry_warned_at" of relation "student_violations" does not exist'
          }
        );
      }
      return (200, []);
    };
    await DisciplineRepository(client).restoreViolation('v1');
    final patches = server.requests.where((r) => r.method == 'PATCH').toList();
    expect(patches, hasLength(2));
    expect(patches.last.json.containsKey('expiry_warned_at'), isFalse);
    expect(patches.last.json['restored_at'], isNotNull);
  });
}
