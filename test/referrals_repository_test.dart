import 'package:capstone_dashboard/data/referrals_repository.dart';
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

  test('fetchAll maps self and endorsement referrals with their meetings',
      () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/student_referrals')
        ? (200, [
            {
              'id': 'r1',
              'student_id': 's1',
              'source': 'self',
              'concern': 'emotional',
              'details': 'I feel overwhelmed.',
              'urgency': 'Urgent',
              'status': 'Pending',
              'counselor_note': null,
              'created_at': '2026-10-01T00:00:00Z',
              'students': {
                'student_number': '24-0001',
                'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
              },
              'guidance_meetings': [
                {
                  'id': 'm1',
                  'scheduled_at': '2026-10-05T01:00:00Z',
                  'location': 'Guidance Office',
                  'invitee': 'student',
                  'status': 'Confirmed',
                },
              ],
            },
            {
              'id': 'r2',
              'student_id': 's2',
              'source': 'endorsement',
              'concern': 'other',
              'details': 'Check-in: Seems withdrawn.',
              'urgency': 'Normal',
              'status': 'In_Progress',
              'counselor_note': null,
              'created_at': '2026-10-02T00:00:00Z',
              'students': {
                'student_number': '24-0002',
                'profiles': {'first_name': 'Ben', 'last_name': 'Reyes'},
              },
              'guidance_meetings': <dynamic>[],
            },
          ])
        : null;

    final list = await ReferralsRepository(client).fetchAll();

    expect(list, hasLength(2));
    expect(list[0].studentName, 'Ana Cruz');
    expect(list[0].studentId, 's1');
    expect(list[0].isEndorsement, isFalse);
    expect(list[0].isUrgent, isTrue);
    expect(list[0].meetings.single.invitee, 'student');
    expect(list[0].meetings.single.status, 'Confirmed');
    expect(list[0].meetings.single.location, 'Guidance Office');
    expect(list[1].isEndorsement, isTrue);
    expect(list[1].meetings, isEmpty);
  });

  test('update sends the status and the note the student reads', () async {
    await ReferralsRepository(client).update('r1',
        status: 'Closed', note: '  See you Friday.  ', actorId: 'g1');

    final req = server.requests.lastWhere((r) =>
        r.method == 'PATCH' && r.path.endsWith('/rest/v1/student_referrals'));
    expect(req.json['status'], 'Closed');
    expect(req.json['counselor_note'], 'See you Friday.');
    expect(req.json['handled_by'], 'g1');
    expect(req.uri.queryParameters['id'], 'eq.r1');
  });

  test('scheduleMeeting calls schedule_referral_meeting in UTC', () async {
    await ReferralsRepository(client).scheduleMeeting(
      referralId: 'r1',
      scheduledAt: DateTime.utc(2026, 10, 20, 1),
      location: 'Guidance Office',
      invitee: 'student',
    );

    expect(server.requestTo('/rpc/schedule_referral_meeting').json, {
      'p_referral_id': 'r1',
      'p_scheduled_at': '2026-10-20T01:00:00.000Z',
      'p_location': 'Guidance Office',
      'p_invitee': 'student',
    });
  });

  test('setMeetingOutcome calls set_meeting_outcome', () async {
    await ReferralsRepository(client).setMeetingOutcome('m1', 'Completed');

    expect(server.requestTo('/rpc/set_meeting_outcome').json,
        {'p_meeting_id': 'm1', 'p_status': 'Completed'});
  });
}
