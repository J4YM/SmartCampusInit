import 'package:capstone_dashboard/data/escalation_repository.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show EndorsementKind, EscalationDraft, EscalationReportModel;
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

  (int, Object?)? studentFound(RecordedRequest r) =>
      r.path.endsWith('/rest/v1/students') ? (200, {'id': 's1'}) : null;

  test('a counseling endorsement with no violations posts empty lists',
      () async {
    server.respond = studentFound;
    await EscalationRepository(client).issue(const EscalationDraft(
      studentNumber: '24-0001',
      violationIds: [],
      summary: 'Seems withdrawn.',
      message: '',
      channels: [],
      kind: EndorsementKind.counseling,
    ));

    final body = server.requests
        .lastWhere((r) =>
            r.method == 'POST' && r.path.endsWith('/rest/v1/escalation_reports'))
        .json;
    expect(body['kind'], 'counseling');
    expect(body['violation_ids'], isEmpty);
    expect(body['channels'], isEmpty);
    expect(body['student_id'], 's1');
  });

  test('a parent-intervention endorsement keeps its message and channels',
      () async {
    server.respond = studentFound;
    await EscalationRepository(client).issue(const EscalationDraft(
      studentNumber: '24-0001',
      violationIds: ['v1'],
      summary: 'Repeated conduct concerns.',
      message: 'Please visit the Guidance Office.',
      channels: ['sms', 'email'],
      kind: EndorsementKind.both,
    ));

    final body = server.requests
        .lastWhere((r) =>
            r.method == 'POST' && r.path.endsWith('/rest/v1/escalation_reports'))
        .json;
    expect(body['kind'], 'both');
    expect(body['message'], 'Please visit the Guidance Office.');
    expect(body['channels'], ['sms', 'email']);
    expect(body['violation_ids'], ['v1']);
  });

  test('endorsing a concern sends its id', () async {
    server.respond = studentFound;
    await EscalationRepository(client).issue(const EscalationDraft(
      studentNumber: '24-0001',
      violationIds: [],
      summary: 'From a concern.',
      message: '',
      channels: [],
      kind: EndorsementKind.counseling,
      concernId: 'ref1',
    ));

    final body = server.requests
        .lastWhere((r) =>
            r.method == 'POST' && r.path.endsWith('/rest/v1/escalation_reports'))
        .json;
    expect(body['concern_id'], 'ref1');
  });

  test('fetchViolationHistory calls the column-limited function', () async {
    server.respond = (r) => r.path.endsWith('/rpc/endorsement_violation_history')
        ? (200, [
            {
              'violation_id': 'v1',
              'offense': 'Fighting',
              'category': 'Major_A',
              'incident_at': '2026-10-01T02:00:00Z',
              'status': 'Pending',
            }
          ])
        : null;

    final history =
        await EscalationRepository(client).fetchViolationHistory('s1');

    expect(server.requestTo('/rpc/endorsement_violation_history').json,
        {'p_student_id': 's1'});
    expect(history, hasLength(1));
    expect(history.single.id, 'v1');
    expect(history.single.offense, 'Fighting');
    expect(history.single.category, 'Major_A');
    expect(history.single.status, 'Pending');
    expect(history.single.incidentAt, DateTime.utc(2026, 10, 1, 2).toLocal());
  });

  test('a report row without a kind reads as a parent intervention', () {
    expect(EndorsementKind.fromDb(null), EndorsementKind.parentIntervention);
    expect(EndorsementKind.fromDb('counseling'), EndorsementKind.counseling);
    expect(EndorsementKind.counseling.notifiesParent, isFalse);
    expect(EndorsementKind.both.notifiesParent, isTrue);
    expect(EndorsementKind.parentIntervention.dbValue, 'parent_intervention');
    expect(EndorsementKind.both.label, 'Counseling and parent intervention');
  });

  test('fetchReports maps kind and concern id', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/escalation_reports')
        ? (200, [
            {
              'id': 'r1',
              'student_id': 's1',
              'violation_ids': <String>[],
              'title': 'Endorsement',
              'summary': 'x',
              'message': '',
              'channels': <String>[],
              'source': 'officer',
              'status': 'Pending_GC',
              'created_at': '2026-10-01T00:00:00Z',
              'kind': 'counseling',
              'concern_id': 'ref1',
              'students': {
                'student_number': '24-0001',
                'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
              },
            }
          ])
        : null;

    final List<EscalationReportModel> reports =
        await EscalationRepository(client).fetchReports();

    expect(reports.single.kind, EndorsementKind.counseling);
    expect(reports.single.concernId, 'ref1');
    expect(reports.single.violationCount, 0);
  });

  test('an Other endorsement posts its description and the exclude flag',
      () async {
    server.respond = studentFound;
    await EscalationRepository(client).issue(const EscalationDraft(
      studentNumber: '24-0001',
      violationIds: [],
      summary: 'Needs a mediator.',
      message: '',
      channels: [],
      kind: EndorsementKind.other,
      otherDescription: 'Peer mediation',
      excludeParent: true,
    ));

    final body = server.requests
        .lastWhere((r) =>
            r.method == 'POST' && r.path.endsWith('/rest/v1/escalation_reports'))
        .json;
    expect(body['kind'], 'other');
    expect(body['other_description'], 'Peer mediation');
    expect(body['exclude_parent'], true);
    expect(body['channels'], isEmpty);
    expect(EndorsementKind.other.notifiesParent, isFalse);
    expect(EndorsementKind.other.label, 'Other');
  });

  test('fetchReports maps the description and exclude flag', () async {
    server.respond = (r) => r.path.endsWith('/rest/v1/escalation_reports')
        ? (200, [
            {
              'id': 'e1',
              'student_id': 's1',
              'violation_ids': <dynamic>[],
              'title': 'Private',
              'summary': 'Private matter.',
              'message': '',
              'channels': <dynamic>[],
              'source': 'officer',
              'status': 'Approved',
              'created_at': '2026-10-01T00:00:00Z',
              'kind': 'other',
              'other_description': 'Peer mediation',
              'exclude_parent': true,
              'students': {
                'student_number': '24-0001',
                'profiles': {'first_name': 'Ana', 'last_name': 'Cruz'},
              },
            }
          ])
        : null;

    final reports = await EscalationRepository(client).fetchReports();

    expect(reports.single.kind, EndorsementKind.other);
    expect(reports.single.otherDescription, 'Peer mediation');
    expect(reports.single.excludeParent, isTrue);
  });

  test('deciding sends no meeting: Student Affairs arranges it afterwards',
      () async {
    await EscalationRepository(client)
        .decide('e1', approve: true, note: 'ok', actorName: 'Ms Reyes');

    expect(server.requestTo('/rpc/decide_escalation_report').json, {
      'p_id': 'e1',
      'p_approve': true,
      'p_note': 'ok',
      'p_message': null,
      'p_actor_name': 'Ms Reyes',
    });
  });
}
