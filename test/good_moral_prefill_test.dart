import 'package:capstone_dashboard/data/good_moral_prefill.dart';
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

  test('the slip is filled in from the good_moral_prefill function', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/rpc/good_moral_prefill')
        ? (200, [
            {
              'last_name': ' Cruz ',
              'first_name': 'Ana',
              'student_number': '2024-0001',
              'section': 'BSIT 3-A',
              'contact_number': null,
              'enrollment_year': '2024',
            }
          ])
        : null;

    final form = await fetchGoodMoralPrefill(client, 's1');

    expect(server.requestTo('/rpc/good_moral_prefill').json['p_student_id'], 's1');
    expect(form!.lastName, 'Cruz');
    expect(form.firstName, 'Ana');
    expect(form.studentNumber, '2024-0001');
    expect(form.section, 'BSIT 3-A');
    expect(form.contactNumber, '');
    expect(form.ayStarted, '2024');
    expect(form.schoolStatus, 'Enrolled');
  });

  test('without the function installed it reads the tables directly',
      () async {
    server.respond = (r) {
      if (r.path.endsWith('/rpc/good_moral_prefill')) {
        return (404, {'code': 'PGRST202', 'message': 'not found'});
      }
      if (r.path.endsWith('/rest/v1/students')) {
        return (200, {
          'student_number': '2024-0002',
          'enrollment_year': 2023,
          'sections': {'name': 'BSIT 2-B'},
          'profiles': {
            'first_name': 'Ben',
            'last_name': 'Reyes',
            'phone_number': '0917',
          },
        });
      }
      return null;
    };

    final form = await fetchGoodMoralPrefill(client, 's2');

    expect(form!.lastName, 'Reyes');
    expect(form.section, 'BSIT 2-B');
    expect(form.contactNumber, '0917');
    expect(form.ayStarted, '2023');
  });

  test('a student with no readable record gives null', () async {
    server.respond = (r) => r.path.endsWith('/rpc/good_moral_prefill')
        ? (200, <dynamic>[])
        : (200, null);

    expect(await fetchGoodMoralPrefill(client, 's3'), isNull);
  });
}
