import 'package:capstone_dashboard/data/discipline_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

Map<String, dynamic> _row({
  String? offenseId,
  String status = 'Pending',
  String? incidentAt = '2026-10-01T06:00:00Z',
}) =>
    {
      'id': 'v1',
      'student_id': 's1',
      'offense_id': offenseId,
      'is_escalated': false,
      'status': status,
      'created_at': '2026-10-01T08:00:00Z',
      'incident_at': incidentAt,
      'suggested_escalation': true,
      'incident_notes': 'Seen smoking',
      'students': {
        'student_number': '2024-0001',
        'profiles': {'first_name': 'Jane', 'last_name': 'Doe'},
        'sections': {'name': 'BSIT 3-A'},
      },
      'handbook_offenses': offenseId == null
          ? null
          : {'description': 'Smoking', 'category': 'Major_A'},
      'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
      'violation_evidence': [
        {'storage_path': 'p1/a.jpg'},
      ],
    };

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

  test('an unclassified report maps incident time, flag and evidence', () async {
    server.respond = (r) => r.uri.queryParameters['select'] == 'student_id'
        ? (200, [{'student_id': 's1'}])
        : (200, [_row()]);

    final c = (await DisciplineRepository(client).fetchActiveViolations()).single;

    expect(c.isClassified, isFalse);
    expect(c.incidentDateTime, DateTime.parse('2026-10-01T06:00:00Z').toLocal());
    expect(c.filedAt, DateTime.parse('2026-10-01T08:00:00Z').toLocal());
    expect(c.suggestedEscalation, isTrue);
    expect(c.evidencePaths, ['p1/a.jpg']);
    expect(c.description, 'Seen smoking');
  });

  test('legacy rows without incident_at fall back to the filing time', () async {
    server.respond = (r) => r.uri.queryParameters['select'] == 'student_id'
        ? (200, [{'student_id': 's1'}])
        : (200, [_row(offenseId: 'o1', incidentAt: null)]);

    final c = (await DisciplineRepository(client).fetchActiveViolations()).single;

    expect(c.isClassified, isTrue);
    expect(c.incidentDateTime, DateTime.parse('2026-10-01T08:00:00Z').toLocal());
  });

  test('the active queue includes cases awaiting a sanction', () async {
    await DisciplineRepository(client).fetchActiveViolations();
    final statusFilter = server.requests
        .map((r) => r.uri.queryParameters['status'])
        .whereType<String>()
        .first;
    expect(statusFilter, contains('Investigation_Complete'));
  });

  test('a database without the new columns still loads the list', () async {
    server.respond = (r) {
      final select = r.uri.queryParameters['select'] ?? '';
      if (select == 'student_id') return (200, [{'student_id': 's1'}]);
      if (select.contains('incident_at')) {
        return (
          400,
          {'code': '42703', 'message': 'column student_violations.incident_at does not exist'}
        );
      }
      return (200, [_row(offenseId: 'o1', incidentAt: null)..remove('violation_evidence')]);
    };

    final cases = await DisciplineRepository(client).fetchActiveViolations();
    expect(cases.single.studentName, 'Jane Doe');
  });

  test('classify, autoRecordMinor and escalateToGuidance call their RPCs', () async {
    final repo = DisciplineRepository(client);
    await repo.classify('v1', ['o1', 'o2']);
    await repo.autoRecordMinor('v1');
    await repo.escalateToGuidance('v1');

    expect(server.requestTo('/rpc/classify_violation').json,
        {'p_violation_id': 'v1', 'p_offense_ids': ['o1', 'o2']});
    expect(server.requestTo('/rpc/auto_record_minor').json, {'p_violation_id': 'v1'});
    expect(server.requestTo('/rpc/escalate_to_guidance').json, {'p_violation_id': 'v1'});
  });

  test('a rejected RPC surfaces the database message', () async {
    server.respond = (r) => (
          400,
          {'code': 'P0001', 'message': 'Classify the report before escalating it.'}
        );
    expect(
      () => DisciplineRepository(client).escalateToGuidance('v1'),
      throwsA(isA<DisciplineRepositoryException>().having(
          (e) => e.message, 'message', 'Classify the report before escalating it.')),
    );
  });
}
