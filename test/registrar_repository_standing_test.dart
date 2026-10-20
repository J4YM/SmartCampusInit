import 'package:capstone_dashboard/data/registrar_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

// Kept apart from the widget tests: a TestWidgetsFlutterBinding in the same
// file would answer every real HTTP request with 400.
void main() {
  late RecordingServer server;
  late SupabaseClient client;

  Map<String, dynamic> row({String? standing}) => {
        'id': 's1',
        'student_number': '2024-0001',
        'rfid_uid': 'abc',
        'created_at': '2026-08-01T00:00:00Z',
        'profiles': {
          'first_name': 'Jane',
          'last_name': 'Doe',
          'is_active': false,
        },
        'sections': {'name': 'BSIT 3-A', 'program': 'BS Information Technology'},
        'parent_student_links': [],
        if (standing != null) 'enrollment_standing': standing,
      };

  setUp(() async {
    server = RecordingServer();
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  test('fetchStudents reads enrollment_standing', () async {
    server.respond = (r) => r.path.endsWith('/students')
        ? (200, [row(standing: 'Non_Readmission')])
        : (200, []);
    final list = await RegistrarRepository(client).fetchStudents();
    expect(list.single.enrollmentStanding, 'Non_Readmission');
    expect(list.single.isRestricted, isTrue);
  });

  test('enrolling a restricted student fails with the readable database message',
      () async {
    const message = 'Jane Doe is marked Not for Readmission by Student Affairs '
        'and cannot be enrolled. An administrator must lift the restriction first.';
    server.respond = (r) => (400, {'code': 'P0001', 'message': message});

    await expectLater(
      RegistrarRepository(client)
          .enrollStudent(studentId: 's1', classSectionId: 'cs1'),
      throwsA(isA<RegistrarRepositoryException>()
          .having((e) => e.toString(), 'message', message)),
    );
  });

  test('lifting a restriction calls the Admin RPC with the reason', () async {
    await RegistrarRepository(client)
        .liftEnrollmentStanding('s1', reason: 'Appeal granted');
    expect(server.requestTo('/rpc/lift_enrollment_standing').json,
        {'p_student_id': 's1', 'p_reason': 'Appeal granted'});
  });

  test('a refused lift surfaces the database message', () async {
    server.respond = (r) => (
          400,
          {
            'code': '42501',
            'message': 'Only an administrator can lift an enrollment restriction.'
          }
        );
    await expectLater(
      RegistrarRepository(client).liftEnrollmentStanding('s1', reason: 'x'),
      throwsA(isA<RegistrarRepositoryException>().having((e) => e.message,
          'message', 'Only an administrator can lift an enrollment restriction.')),
    );
  });

  test('a database without the column still lists students as Good', () async {
    server.respond = (r) {
      if (!r.path.endsWith('/students')) return (200, []);
      final select = r.uri.queryParameters['select'] ?? '';
      if (select.contains('enrollment_standing')) {
        return (
          400,
          {
            'code': '42703',
            'message': 'column students.enrollment_standing does not exist'
          }
        );
      }
      return (200, [row()]);
    };
    final list = await RegistrarRepository(client).fetchStudents();
    expect(list.single.name, 'Jane Doe');
    expect(list.single.enrollmentStanding, 'Good');
  });
}
