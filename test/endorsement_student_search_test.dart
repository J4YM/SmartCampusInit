import 'package:capstone_dashboard/data/discipline_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

void main() {
  late RecordingServer server;
  late SupabaseClient client;

  setUp(() async {
    server = RecordingServer();
    server.headers['content-range'] = '0-0/1';
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  test('with no query it pages the whole roster, with no violation lookups',
      () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/students')
        ? (200, [
            {
              'id': 's1',
              'student_number': '24-0001',
              'enrollment_year': 2024,
              'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
              'sections': {'name': 'BSIT 3-A', 'program': 'BSIT', 'year_level': 3},
            }
          ])
        : null;

    final page = await DisciplineRepository(client)
        .fetchEndorsementStudents(page: 2, pageSize: 10);

    final req = server.requests.singleWhere(
        (r) => r.method == 'GET' && r.path.endsWith('/rest/v1/students'));
    expect(req.uri.queryParameters['offset'], '10');
    expect(req.uri.queryParameters['limit'], '10');
    expect(req.uri.queryParameters.containsKey('or'), isFalse);
    expect(server.requests.where((r) => r.path.contains('student_violations')),
        isEmpty);
    expect(page.items.single.studentName, 'Ana Cruz');
    expect(page.items.single.studentNumber, '24-0001');
    expect(page.items.single.programGradeSection, 'BSIT 3-A');
  });

  test('a query matches the student number or the name on the server',
      () async {
    server.respond = (r) {
      if (r.path.endsWith('/rest/v1/profiles')) {
        return (200, [
          {'id': 'p1'},
          {'id': 'p2'},
        ]);
      }
      return null;
    };

    await DisciplineRepository(client)
        .fetchEndorsementStudents(page: 1, query: 'ana');

    final profiles = server.requests
        .firstWhere((r) => r.path.endsWith('/rest/v1/profiles'));
    expect(profiles.uri.queryParameters['or'],
        contains('first_name.ilike.*ana*'));
    expect(profiles.uri.queryParameters['or'],
        contains('last_name.ilike.*ana*'));

    final students = server.requests
        .lastWhere((r) => r.path.endsWith('/rest/v1/students'));
    final or = students.uri.queryParameters['or']!;
    expect(or, contains('student_number.ilike.*ana*'));
    expect(or, contains('id.in.(p1,p2)'));
  });

  test('wildcard characters in a query are not passed through', () async {
    await DisciplineRepository(client)
        .fetchEndorsementStudents(page: 1, query: r'a%_,(b)');

    final students = server.requests
        .lastWhere((r) => r.path.endsWith('/rest/v1/students'));
    final or = students.uri.queryParameters['or']!;
    expect(or, isNot(contains('%')));
    expect(or, isNot(contains(',(b)')));
  });
}
