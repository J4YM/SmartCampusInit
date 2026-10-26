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
}
