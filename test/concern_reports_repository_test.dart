import 'package:capstone_dashboard/data/concern_reports_repository.dart';
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

  test('fetchAll maps a concern row for the Discipline Officer', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/concern_reports')
        ? (200, [
            {
              'id': 'r1',
              'student_id': 's1',
              'concern': 'bullying',
              'details': 'He keeps being picked on.',
              'urgency': 'Urgent',
              'status': 'Pending',
              'handler_note': null,
              'created_at': '2026-10-01T00:00:00Z',
              'students': {
                'student_number': '24-0001',
                'profiles': {'first_name': 'Ben', 'last_name': 'Reyes'},
              },
              'about': {
                'student_number': '24-0009',
                'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
              },
            }
          ])
        : null;

    final list = await ConcernReportsRepository(client).fetchAll();

    expect(list.single.studentName, 'Ben Reyes');
    expect(list.single.aboutStudentName, 'Ana Cruz');
    expect(list.single.aboutStudentNumber, '24-0009');
    expect(list.single.isUrgent, isTrue);
    expect(list.single.concernLabel, 'Bullying');
  });

  test('update sends the status and the note the student reads', () async {
    await ConcernReportsRepository(client)
        .update('r1', status: 'Closed', note: '  We spoke with them.  ', actorId: 'do1');

    final req = server.requests.lastWhere(
        (r) => r.method == 'PATCH' && r.path.endsWith('/rest/v1/concern_reports'));
    expect(req.json['status'], 'Closed');
    expect(req.json['handler_note'], 'We spoke with them.');
    expect(req.json['handled_by'], 'do1');
    expect(req.uri.queryParameters['id'], 'eq.r1');
  });

  test('fetchAll reads the incident a concern became', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/concern_reports')
        ? (200, [
            {
              'id': 'r1',
              'student_id': 's1',
              'concern': 'bullying',
              'details': 'x',
              'urgency': 'Normal',
              'status': 'In_Progress',
              'violation_id': 'v1',
              'created_at': '2026-10-01T00:00:00Z',
              'students': {
                'student_number': '24-0001',
                'profiles': {'first_name': 'Ben', 'last_name': 'Reyes'},
              },
            }
          ])
        : null;
    final list = await ConcernReportsRepository(client).fetchAll();
    expect(list.single.violationId, 'v1');
    expect(list.single.underInvestigation, isTrue);
    expect(server.requests.last.uri.queryParameters['select'],
        contains('violation_id'));
  });

  test('sendToInvestigation passes the named student and incident details',
      () async {
    server.respond = (r) => (200, 'inv1');
    final id = await ConcernReportsRepository(client).sendToInvestigation(
      concernId: 'c1',
      studentId: 's2',
      offenseId: 'o1',
      description: 'Took lunch money',
      occurredAt: DateTime.utc(2026, 11, 19),
      location: 'Canteen',
    );
    expect(id, 'inv1');
    expect(server.requestTo('/rpc/send_concern_to_investigation').json, {
      'p_concern_id': 'c1',
      'p_student_id': 's2',
      'p_offense_id': 'o1',
      'p_description': 'Took lunch money',
      'p_occurred_at': '2026-11-19T00:00:00.000Z',
      'p_location': 'Canteen',
      'p_notify_parent': false,
    });
  });

  test('fetchCaseFile parses the concern case file', () async {
    server.respond = (r) => (200, {
          'endorsements': [],
          'investigation': {
            'id': 'i1',
            'status': 'Complete',
            'findings': 'Admitted',
            'recommendation': 'Apologise',
            'completed_at': '2026-10-08T00:00:00Z',
            'sanction': null,
          },
        });
    final file = await ConcernReportsRepository(client).fetchCaseFile('c1');
    expect(server.requestTo('/rpc/concern_case_file').json, {'p_concern_id': 'c1'});
    expect(file.investigation!.findings, 'Admitted');
  });

  test('a database error on send reads as a readable exception', () async {
    server.respond = (r) =>
        (400, {'message': 'This concern is already under investigation.'});
    expect(
      () => ConcernReportsRepository(client).sendToInvestigation(
        concernId: 'c1',
        studentId: 's2',
        offenseId: 'o1',
        description: 'x',
        occurredAt: DateTime.utc(2026, 11, 19),
      ),
      throwsA(predicate((e) => '$e'.contains('already under investigation'))),
    );
  });
}
