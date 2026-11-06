import 'package:capstone_dashboard/data/student_portal_repository.dart';
import 'package:dashboard_layout/dashboard_layout.dart' show ReferralFormData;
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/models/concern_report_status.dart';
import 'package:student_portal_module/models/referral_request_status.dart';
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

  test('submitReferral sends the External Referral Form with the referral',
      () async {
    await StudentPortalRepository(client).submitReferral(
      studentId: 's1',
      concern: ReferralConcern.academic,
      details: 'I cannot focus.',
      urgent: true,
      form: const ReferralFormData(
        studentName: 'Juan Dela Cruz',
        address: '12 Rizal St',
        academic: ['Test anxiety'],
      ),
    );

    final body = server.requestTo('/rpc/submit_student_referral').json as Map;
    expect(body['p_referrer_id'], 's1');
    expect(body['p_concern'], 'academic');
    expect(body['p_urgent'], true);
    final form = body['p_form'] as Map;
    expect(form['student_name'], 'Juan Dela Cruz');
    expect(form['address'], '12 Rizal St');
    expect(form['academic'], ['Test anxiety']);
  });

  test('a concern report carries no referral form', () async {
    await StudentPortalRepository(client).submitConcernReport(
      studentId: 's1',
      concern: ConcernType.bullying,
      details: 'Someone is being picked on.',
    );
    final body = server.requestTo('/rpc/submit_concern_report').json as Map;
    expect(body.containsKey('p_form'), isFalse);
  });

  test('fetchMyReferrals reads the details and the form; an empty form is '
      'null', () async {
    server.respond = (r) => r.path.endsWith('/rpc/my_student_referrals')
        ? (200, [
            {
              'id': 'r1',
              'concern': 'academic',
              'urgency': 'Normal',
              'status': 'Pending',
              'counselor_note': null,
              'created_at': '2026-11-06T01:00:00Z',
              'details': 'Exams are hard.',
              'form': {'address': '12 Rizal St', 'academic': ['Test anxiety']},
            },
            {
              'id': 'r0',
              'concern': 'other',
              'urgency': 'Normal',
              'status': 'Closed',
              'counselor_note': 'Seen.',
              'created_at': '2026-09-01T01:00:00Z',
              'details': 'Old one.',
              'form': {},
            },
          ])
        : null;

    final list = await StudentPortalRepository(client).fetchMyReferrals('s1');

    expect(list.first.details, 'Exams are hard.');
    expect(list.first.form!.address, '12 Rizal St');
    expect(list.first.form!.academic, ['Test anxiety']);
    expect(list.last.form, isNull);
  });
}
