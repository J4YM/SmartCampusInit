import 'package:capstone_dashboard/data/discipline_repository.dart';
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

  Map<String, dynamic> row({Object? formData, String status = 'Pending'}) => {
        'id': 'r1',
        'student_id': 's1',
        'document_type': 'Certificate of Good Moral',
        'purpose': 'Employment',
        'requested_by': 'Ana Cruz',
        'request_date': '2026-10-01T01:00:00Z',
        'remarks': 'Name: Cruz, Ana',
        'status': status,
        'flag_note': status == 'Returned' ? 'Fix the section.' : null,
        'form_data': formData,
        'history': [
          {'purpose': 'Employment'},
          {'purpose': 'Employment'},
        ],
        'students': {
          'enrollment_year': 2024,
          'student_number': '2024-0001',
          'profiles': {
            'first_name': 'Ana',
            'last_name': 'Cruz',
            'phone_number': '0917 123 4567',
          },
          'sections': {'name': 'BSIT 3-A', 'program': 'BSIT', 'year_level': 3},
        },
      };

  test('a request carries its slip, status, note, history and the school record',
      () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/good_moral_requests')
        ? (200, [
            row(
              status: 'Returned',
              formData: {
                'last_name': 'Cruz',
                'first_name': 'Ana',
                'section': 'BSIT 3-B',
              },
            )
          ])
        : null;

    final requests = await DisciplineRepository(client).fetchGoodMoralRequests();
    final r = requests.single;

    expect(r.status, 'Returned');
    expect(r.flagNote, 'Fix the section.');
    expect(r.historyCount, 2);
    expect(r.formData!.section, 'BSIT 3-B');
    expect(r.record!.section, 'BSIT 3-A');
    expect(r.record!.contactNumber, '0917 123 4567');
    expect(r.record!.enrollmentYear, 2024);
    expect(r.record!.firstName, 'Ana');
  });

  test('an older request without a stored slip has no comparison', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/good_moral_requests')
        ? (200, [row()])
        : null;

    final r = (await DisciplineRepository(client).fetchGoodMoralRequests()).single;

    expect(r.formData, isNull);
    expect(r.status, 'Pending');
    expect(r.flagNote, isNull);
  });

  test('the request query asks for the slip, note, history and phone number',
      () async {
    await DisciplineRepository(client).fetchGoodMoralRequests();
    final select = server.requests
        .firstWhere((r) => r.path.endsWith('/rest/v1/good_moral_requests'))
        .uri
        .queryParameters['select']!;
    expect(select, contains('form_data'));
    expect(select, contains('flag_note'));
    expect(select, contains('history'));
    expect(select, contains('phone_number'));
  });

  test('flag and send back call the RPC', () async {
    final repo = DisciplineRepository(client);
    await repo.flagGoodMoralRequest('r1', 'Section does not match.',
        sendBack: false);
    await repo.flagGoodMoralRequest('r1', 'Please fix it.', sendBack: true);

    final calls = server.requests
        .where((r) => r.path.endsWith('/rpc/flag_good_moral_request'))
        .map((r) => r.json)
        .toList();
    expect(calls, [
      {'p_request_id': 'r1', 'p_note': 'Section does not match.', 'p_send_back': false},
      {'p_request_id': 'r1', 'p_note': 'Please fix it.', 'p_send_back': true},
    ]);
  });

  test('using the registrar record calls its function with the request id',
      () async {
    await DisciplineRepository(client).useRegistrarRecordForGoodMoral('r1');

    expect(server.requestTo('/rpc/use_registrar_record_for_good_moral').json,
        {'p_request_id': 'r1'});
  });
}
