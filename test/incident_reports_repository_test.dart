import 'package:capstone_dashboard/data/incident_reports_repository.dart';
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

  test('report sends exactly the p_* params and omits p_concern_id when null',
      () async {
    server.respond = (r) => (200, 'v1');
    final id = await IncidentReportsRepository(client).report(
      studentId: 's1',
      offenseId: 'o1',
      description: 'Vaping',
      occurredAt: DateTime.utc(2026, 11, 19, 1, 30),
    );
    expect(id, 'v1');
    expect(server.requestTo('/rpc/report_incident').json, {
      'p_student_id': 's1',
      'p_offense_id': 'o1',
      'p_description': 'Vaping',
      'p_occurred_at': '2026-11-19T01:30:00.000Z',
      'p_location': null,
      'p_notify_parent': false,
    });
  });

  test('report passes notify, location and the concern link through',
      () async {
    server.respond = (r) => (200, 'v2');
    await IncidentReportsRepository(client).report(
      studentId: 's1',
      offenseId: 'o1',
      description: 'Bullying',
      occurredAt: DateTime.utc(2026, 11, 19),
      location: 'Canteen',
      notifyParent: true,
      concernId: 'c1',
    );
    final body = server.requestTo('/rpc/report_incident').json;
    expect(body['p_notify_parent'], true);
    expect(body['p_location'], 'Canteen');
    expect(body['p_concern_id'], 'c1');
  });

  test('notifyParent calls its RPC', () async {
    await IncidentReportsRepository(client).notifyParent('v1');
    expect(server.requestTo('/rpc/notify_parent_of_incident').json,
        {'p_violation_id': 'v1'});
  });

  test('a database error reads as an IncidentReportsException', () async {
    server.respond = (r) => (400, {'message': 'Describe the incident.'});
    expect(
      () => IncidentReportsRepository(client).report(
        studentId: 's1',
        offenseId: 'o1',
        description: ' ',
        occurredAt: DateTime.utc(2026, 11, 19),
      ),
      throwsA(isA<IncidentReportsException>()
          .having((e) => e.message, 'message', 'Describe the incident.')),
    );
  });

  test('searchStudents filters by name or number and shapes the hits',
      () async {
    server.respond = (r) => (200, [
          {
            'id': 's1',
            'student_number': '2026-0001',
            'profiles': {'first_name': 'Maria', 'last_name': 'Santos'},
            'sections': {'name': 'BSIT-3A'},
          },
          {
            'id': 's2',
            'student_number': '2026-0002',
            'profiles': {'first_name': 'Jose', 'last_name': 'Cruz'},
            'sections': null,
          },
        ]);
    final hits = await IncidentReportsRepository(client).searchStudents('mar');
    expect(hits.map((h) => h.id), ['s1']);
    expect(hits.single.name, 'Maria Santos');
    expect(hits.single.section, 'BSIT-3A');
  });
}
