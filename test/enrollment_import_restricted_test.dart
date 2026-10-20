import 'package:capstone_dashboard/data/enrollment_import_repository.dart';
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

  test('a student in good standing is confirmed for the term', () async {
    server.respond = (r) =>
        r.path.endsWith('/rpc/enrollment_restriction') ? (200, null) : (200, 1);
    final repo = EnrollmentImportRepository(client);

    expect(await repo.confirmImported('s1', '2024-1 Jane Doe'), isTrue);
    expect(repo.restrictedSkipped, isEmpty);
    expect(server.requestTo('/rpc/confirm_student_enrollment').json,
        {'p_student_ids': ['s1'], 'p_source': 'import'});
  });

  test('a restricted student is not confirmed and is reported with the reason',
      () async {
    const reason = 'Jane Doe is marked Not for Readmission by Student Affairs '
        'and cannot be enrolled.';
    server.respond = (r) =>
        r.path.endsWith('/rpc/enrollment_restriction') ? (200, reason) : (200, 1);
    final repo = EnrollmentImportRepository(client);

    expect(await repo.confirmImported('s1', '2024-1 Jane Doe'), isFalse);
    expect(repo.restrictedSkipped, ['2024-1 Jane Doe: $reason']);
    expect(
        server.requests.where((r) => r.path.endsWith('/rpc/confirm_student_enrollment')),
        isEmpty);
  });

  test('a database without the guard still confirms the student', () async {
    server.respond = (r) => r.path.endsWith('/rpc/enrollment_restriction')
        ? (404, {'code': 'PGRST202', 'message': 'function not found'})
        : (200, 1);
    final repo = EnrollmentImportRepository(client);

    expect(await repo.confirmImported('s1', 'x'), isTrue);
    expect(repo.restrictedSkipped, isEmpty);
  });
}
