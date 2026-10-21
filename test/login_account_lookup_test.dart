import 'package:capstone_dashboard/auth/account_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

// Plain tests only: the database group talks to a real local socket.
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

  test('a built-in demo username exists without asking the database', () async {
    expect(await loginAccountExists(client, 'do.demo'), isTrue);
    expect(await loginAccountExists(client, '  DO.Demo '), isTrue);
    expect(server.requests, isEmpty);
  });

  test('an email known to the database exists', () async {
    server.respond = (r) => (200, true);
    expect(await loginAccountExists(client, 'Demo.Discipline@baliuag.sti.edu.ph'),
        isTrue);
    final req = server.requestTo('/rpc/login_account_exists');
    expect(req.json, {'p_username': 'demo.discipline@baliuag.sti.edu.ph'});
  });

  test('a name the database does not know does not exist', () async {
    server.respond = (r) => (200, false);
    expect(await loginAccountExists(client, 'nobody@example.com'), isFalse);
  });

  test('if the check cannot be made, assume it exists (keep counting)',
      () async {
    server.respond = (r) => (
          404,
          {'code': 'PGRST202', 'message': 'function not found'}
        );
    expect(await loginAccountExists(client, 'x@y.z'), isTrue);
  });

  test('with no database, only the demo usernames exist', () async {
    expect(await loginAccountExists(null, 'guidance.demo'), isTrue);
    expect(await loginAccountExists(null, 'who.is.this'), isFalse);
  });
}
