import 'package:capstone_dashboard/data/escalation_repository.dart';
import 'package:capstone_dashboard/data/guidance_investigation_repository.dart';
import 'package:capstone_dashboard/data/models/parent_availability_round.dart';
import 'package:capstone_dashboard/data/referrals_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

const _roundRow = {
  'id': 'r1',
  'escalation_report_id': 'e1',
  'student_id': 's1',
  'round_no': 2,
  'status': 'Offered',
  'requested_at': '2026-11-18T01:00:00Z',
  'offered_at': '2026-11-18T02:00:00Z',
  'meeting_id': null,
  'meeting_availability_slots': [
    {'id': 'sl2', 'slot_at': '2026-11-25T03:00:00Z', 'status': 'Offered'},
    {'id': 'sl1', 'slot_at': '2026-11-24T01:30:00Z', 'status': 'Offered'},
  ],
};

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

  test('ParentAvailabilityRound.fromJson parses nested slots in time order', () {
    final round = ParentAvailabilityRound.fromJson(_roundRow);
    expect(round.id, 'r1');
    expect(round.escalationReportId, 'e1');
    expect(round.studentId, 's1');
    expect(round.roundNo, 2);
    expect(round.status, 'Offered');
    expect(round.requestedAt, DateTime.utc(2026, 11, 18, 1).toLocal());
    expect(round.offeredAt, DateTime.utc(2026, 11, 18, 2).toLocal());
    expect(round.meetingId, isNull);
    expect(round.slots.map((s) => s.id), ['sl1', 'sl2']);
    expect(round.slots.first.slotAt, DateTime.utc(2026, 11, 24, 1, 30).toLocal());
    expect(round.slots.first.status, 'Offered');
  });

  test('request and cancel call their RPCs; request returns the round id',
      () async {
    server.respond = (r) =>
        r.path.endsWith('/rpc/request_parent_availability') ? (200, 'r9') : null;
    final repo = EscalationRepository(client);
    expect(await repo.requestParentAvailability('e1'), 'r9');
    await repo.cancelParentAvailability('r9');
    expect(server.requestTo('/rpc/request_parent_availability').json,
        {'p_report_id': 'e1'});
    expect(server.requestTo('/rpc/cancel_parent_availability').json,
        {'p_round_id': 'r9'});
  });

  test('fetchAvailabilityRounds reads rounds for the reports', () async {
    server.respond = (r) => (200, [_roundRow]);
    final rounds =
        await EscalationRepository(client).fetchAvailabilityRounds(['e1']);
    expect(rounds.single.slots, hasLength(2));
    final req = server.requests.last;
    expect(req.path, endsWith('/rest/v1/meeting_availability_rounds'));
    expect(req.uri.queryParameters['escalation_report_id'], 'in.("e1")');
  });

  test('fetchAvailabilityRounds with no reports makes no request', () async {
    expect(await EscalationRepository(client).fetchAvailabilityRounds([]),
        isEmpty);
    expect(server.requests, isEmpty);
  });

  test('referrals repo fetches offered rounds and decides', () async {
    server.respond = (r) =>
        r.path.endsWith('/meeting_availability_rounds') ? (200, [_roundRow]) : null;
    final repo = ReferralsRepository(client);
    final rounds = await repo.fetchOfferedRounds();
    expect(rounds.single.id, 'r1');
    expect(server.requests.last.uri.queryParameters['status'], 'eq.Offered');

    await repo.decideParentAvailability(
        roundId: 'r1', slotId: 'sl1', location: 'Guidance Office', note: 'ok');
    expect(server.requestTo('/rpc/decide_parent_availability').json, {
      'p_round_id': 'r1',
      'p_slot_id': 'sl1',
      'p_location': 'Guidance Office',
      'p_note': 'ok',
    });
    await repo.decideParentAvailability(roundId: 'r1', note: 'none fit');
    expect(server.requestTo('/rpc/decide_parent_availability').json, {
      'p_round_id': 'r1',
      'p_slot_id': null,
      'p_location': null,
      'p_note': 'none fit',
    });
  });

  test('parent submits slots as UTC ISO strings and lists open rounds',
      () async {
    server.respond = (r) =>
        r.path.endsWith('/meeting_availability_rounds') ? (200, [_roundRow]) : null;
    final repo = GuidanceInvestigationRepository(client);
    await repo.submitParentAvailability('r1', [
      DateTime.utc(2026, 11, 24, 1, 30),
      DateTime.utc(2026, 11, 25, 3),
    ]);
    expect(server.requestTo('/rpc/submit_parent_availability').json, {
      'p_round_id': 'r1',
      'p_slots': ['2026-11-24T01:30:00.000Z', '2026-11-25T03:00:00.000Z'],
    });
    final rounds = await repo.fetchMyOpenRounds();
    expect(rounds.single.id, 'r1');
    expect(server.requests.last.uri.queryParameters['status'], 'eq.Open');
  });

  test('a database error reads as a readable exception', () async {
    server.respond = (r) => (400, {'code': 'P0001', 'message': 'Nope.'});
    expect(
      () => EscalationRepository(client).requestParentAvailability('e1'),
      throwsA(isA<EscalationRepositoryException>()),
    );
    expect(
      () => GuidanceInvestigationRepository(client)
          .submitParentAvailability('r1', [DateTime.utc(2026, 11, 24)]),
      throwsA(isA<GuidanceInvestigationException>()),
    );
  });

  test('a round can belong to an investigation instead of an endorsement', () {
    final round = ParentAvailabilityRound.fromJson({
      ..._roundRow,
      'escalation_report_id': null,
      'investigation_id': 'i1',
    });
    expect(round.escalationReportId, isNull);
    expect(round.investigationId, 'i1');
    expect(round.slots, hasLength(2));
  });

  test("Guidance's offered list only asks for endorsement rounds", () async {
    server.respond = (r) => (200, [_roundRow]);
    await ReferralsRepository(client).fetchOfferedRounds();
    expect(server.requests.last.uri.queryParameters['escalation_report_id'],
        'not.is.null');
  });

  test('requestInvestigationAvailability sends the investigation id', () async {
    server.respond = (r) => (200, 'r42');
    final id = await GuidanceInvestigationRepository(client)
        .requestInvestigationAvailability('i1');
    expect(id, 'r42');
    expect(server.requestTo('/rpc/request_investigation_availability').json,
        {'p_investigation_id': 'i1'});
  });

  test('fetchInvestigationRounds reads rounds for the investigations',
      () async {
    server.respond = (r) => (200, [
          {
            ..._roundRow,
            'escalation_report_id': null,
            'investigation_id': 'i1',
          }
        ]);
    final rounds = await GuidanceInvestigationRepository(client)
        .fetchInvestigationRounds(['i1']);
    expect(rounds.single.investigationId, 'i1');
    final req = server.requests.last;
    expect(req.path, endsWith('/rest/v1/meeting_availability_rounds'));
    expect(req.uri.queryParameters['investigation_id'], 'in.("i1")');
  });

  test('fetchInvestigationRounds with no ids makes no request', () async {
    expect(
        await GuidanceInvestigationRepository(client)
            .fetchInvestigationRounds([]),
        isEmpty);
    expect(server.requests, isEmpty);
  });

  test('approve and decline call decide_investigation_availability', () async {
    final repo = GuidanceInvestigationRepository(client);
    await repo.approveInvestigationAvailability('r1', 'sl2',
        location: 'Guidance Office');
    expect(server.requestTo('/rpc/decide_investigation_availability').json, {
      'p_round_id': 'r1',
      'p_slot_id': 'sl2',
      'p_location': 'Guidance Office',
      'p_note': null,
    });
    await repo.declineInvestigationAvailability('r1', note: 'Exams that week');
    expect(server.requestTo('/rpc/decide_investigation_availability').json, {
      'p_round_id': 'r1',
      'p_slot_id': null,
      'p_location': null,
      'p_note': 'Exams that week',
    });
  });
}
