import 'package:capstone_dashboard/data/sanctions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

const _rows = [
  {
    'id': 'x1',
    'sanction_type': 'suspension',
    'description': '3-day suspension',
    'effective_on': '2026-11-18',
    'ends_on': null,
    'affects_enrollment': false,
    'decided_at': '2026-11-18T01:00:00Z',
  },
];

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

  test('myHistory sends only p_student_id for a student', () async {
    server.respond = (r) => (200, _rows);
    await SanctionsRepository(client).myHistory('s1');
    expect(server.requestTo('/rpc/my_sanction_history').json,
        {'p_student_id': 's1'});
  });

  test('myHistory includes p_parent_id for a credential parent', () async {
    server.respond = (r) => (200, _rows);
    await SanctionsRepository(client).myHistory('s1', parentId: 'p1');
    expect(server.requestTo('/rpc/my_sanction_history').json,
        {'p_student_id': 's1', 'p_parent_id': 'p1'});
  });

  test('myHistory parses rows, including an open-ended sanction', () async {
    server.respond = (r) => (200, _rows);
    final entries = await SanctionsRepository(client).myHistory('s1');
    final e = entries.single;
    expect(e.id, 'x1');
    expect(e.type, SanctionType.suspension);
    expect(e.description, '3-day suspension');
    expect(e.effectiveOn, DateTime(2026, 11, 18));
    expect(e.endsOn, isNull);
    expect(e.affectsEnrollment, isFalse);
  });

  test('a database error reads as a SanctionsRepositoryException', () async {
    server.respond = (r) => (403, {'message': 'You cannot view this sanction history.'});
    expect(
      () => SanctionsRepository(client).myHistory('s1'),
      throwsA(isA<SanctionsRepositoryException>()),
    );
  });
}
