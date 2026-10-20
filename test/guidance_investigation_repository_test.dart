import 'package:capstone_dashboard/data/guidance_investigation_repository.dart';
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

  test('schedule, respond, setOutcome and complete call their RPCs', () async {
    final repo = GuidanceInvestigationRepository(client);
    await repo.schedule(
      investigationId: 'i1',
      scheduledAt: DateTime.utc(2026, 11, 3, 1, 30),
      location: 'Guidance Office',
      invitee: MeetingInvitee.both,
    );
    await repo.respond('m1', accept: false, note: 'Out of town');
    await repo.setOutcome('m1', MeetingStatus.missed);
    await repo.complete(
      investigationId: 'i1',
      findings: 'Mutual altercation',
      recommendation: 'Warning',
    );

    expect(server.requestTo('/rpc/schedule_guidance_meeting').json, {
      'p_investigation_id': 'i1',
      'p_scheduled_at': '2026-11-03T01:30:00.000Z',
      'p_location': 'Guidance Office',
      'p_invitee': 'both',
    });
    expect(server.requestTo('/rpc/respond_to_meeting').json,
        {'p_meeting_id': 'm1', 'p_accept': false, 'p_note': 'Out of town'});
    expect(server.requestTo('/rpc/set_meeting_outcome').json,
        {'p_meeting_id': 'm1', 'p_status': 'Missed'});
    expect(server.requestTo('/rpc/complete_investigation').json, {
      'p_investigation_id': 'i1',
      'p_findings': 'Mutual altercation',
      'p_recommendation': 'Warning',
    });
  });

  test('a database error reads as a readable exception', () async {
    server.respond = (r) =>
        (400, {'code': 'P0001', 'message': 'This meeting has already passed.'});
    expect(
      () => GuidanceInvestigationRepository(client).respond('m1', accept: true),
      throwsA(isA<GuidanceInvestigationException>()
          .having((e) => e.message, 'message', 'This meeting has already passed.')),
    );
  });

  test('fetchMeetingsForStudent parses statuses and the response', () async {
    server.respond = (r) => (200, [
          {
            'id': 'm1',
            'investigation_id': 'i1',
            'student_id': 's1',
            'scheduled_at': '2026-11-03T01:30:00Z',
            'location': 'Guidance Office',
            'invitee': 'parent',
            'status': 'Reschedule_Requested',
            'response_note': 'Can we do Friday?',
            'responded_at': '2026-11-01T02:00:00Z',
          }
        ]);
    final meetings =
        await GuidanceInvestigationRepository(client).fetchMeetingsForStudent('s1');

    expect(server.requestTo('/guidance_meetings').uri.queryParameters['student_id'],
        'eq.s1');
    expect(meetings.single.status, MeetingStatus.rescheduleRequested);
    expect(meetings.single.invitee, MeetingInvitee.parent);
    expect(meetings.single.responseNote, 'Can we do Friday?');
    expect(meetings.single.isAwaitingResponse, isFalse);
  });

  test('a proposed future meeting is awaiting a response', () {
    final m = GuidanceMeeting(
      id: 'm1',
      investigationId: 'i1',
      studentId: 's1',
      scheduledAt: DateTime.now().add(const Duration(days: 2)),
      invitee: MeetingInvitee.student,
      status: MeetingStatus.proposed,
    );
    expect(m.isAwaitingResponse, isTrue);
    expect(m.canRespond, isTrue);
  });

  test('a past meeting can no longer be answered', () {
    final m = GuidanceMeeting(
      id: 'm1',
      investigationId: 'i1',
      studentId: 's1',
      scheduledAt: DateTime.now().subtract(const Duration(hours: 1)),
      invitee: MeetingInvitee.student,
      status: MeetingStatus.proposed,
    );
    expect(m.canRespond, isFalse);
  });

  test('fetchAssigned embeds the case and its meetings', () async {
    server.respond = (r) => (200, [
          {
            'id': 'i1',
            'violation_id': 'v1',
            'student_id': 's1',
            'status': 'Open',
            'findings': null,
            'recommendation': null,
            'created_at': '2026-10-20T01:00:00Z',
            'students': {
              'student_number': '2024-0001',
              'profiles': {'first_name': 'Jane', 'last_name': 'Doe'},
              'sections': {'name': 'BSIT 3-A'},
            },
            'student_violations': {
              'incident_notes': 'Fight in hallway',
              'incident_at': '2026-10-19T03:00:00Z',
              'handbook_offenses': {'description': 'Fighting', 'category': 'Major_B'},
              'violation_evidence': [
                {'storage_path': 'p/a.jpg'}
              ],
            },
            'guidance_meetings': [
              {
                'id': 'm1',
                'investigation_id': 'i1',
                'student_id': 's1',
                'scheduled_at': '2026-11-03T01:30:00Z',
                'invitee': 'both',
                'status': 'Confirmed',
              }
            ],
          }
        ]);
    final list = await GuidanceInvestigationRepository(client).fetchAssigned();
    final i = list.single;
    expect(i.studentName, 'Jane Doe');
    expect(i.offenseDescription, 'Fighting');
    expect(i.evidencePaths, ['p/a.jpg']);
    expect(i.meetings.single.status, MeetingStatus.confirmed);
    expect(i.isOpen, isTrue);
  });
}
