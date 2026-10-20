import 'package:capstone_dashboard/data/sanctions_repository.dart';
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

  test('record sends every sanction field to record_sanction', () async {
    server.respond = (r) => (200, 'sanction-1');
    final id = await SanctionsRepository(client).record(SanctionInput(
      violationId: 'v1',
      basis: SanctionBasis.custom,
      sanctionType: SanctionType.nonReadmission,
      description: 'Not to be readmitted next term',
      effectiveOn: DateTime(2026, 11, 2),
      affectsEnrollment: true,
      overrideReason: 'Student leaving anyway',
    ));

    expect(id, 'sanction-1');
    expect(server.requestTo('/rpc/record_sanction').json, {
      'p_violation_id': 'v1',
      'p_basis': 'custom',
      'p_handbook_offense_id': null,
      'p_sanction_type': 'non_readmission',
      'p_description': 'Not to be readmitted next term',
      'p_effective_on': '2026-11-02',
      'p_ends_on': null,
      'p_affects_enrollment': true,
      'p_override_reason': 'Student leaving anyway',
    });
  });

  test('only non-readmission and dismissal affect enrollment', () {
    expect(SanctionType.nonReadmission.affectsEnrollment, isTrue);
    expect(SanctionType.dismissal.affectsEnrollment, isTrue);
    for (final t in [
      SanctionType.warning,
      SanctionType.communityService,
      SanctionType.suspension,
      SanctionType.other,
    ]) {
      expect(t.affectsEnrollment, isFalse, reason: t.value);
    }
  });

  test('a database error reads as a SanctionsRepositoryException', () async {
    server.respond = (r) => (
          400,
          {'code': 'P0001', 'message': 'This case already has a sanction.'}
        );
    expect(
      () => SanctionsRepository(client).record(const SanctionInput(
        violationId: 'v1',
        basis: SanctionBasis.handbook,
        sanctionType: SanctionType.warning,
        description: 'x',
      )),
      throwsA(isA<SanctionsRepositoryException>()
          .having((e) => e.message, 'message', 'This case already has a sanction.')),
    );
  });

  test('forStudent lists a student\'s sanctions newest first', () async {
    server.respond = (r) => (200, [
          {
            'id': 'sa1',
            'violation_id': 'v1',
            'student_id': 's1',
            'basis': 'handbook',
            'sanction_type': 'suspension',
            'description': '3 days',
            'effective_on': '2026-10-05',
            'ends_on': '2026-10-08',
            'affects_enrollment': false,
            'decided_at': '2026-10-04T08:00:00Z',
            'override_reason': null,
          }
        ]);
    final list = await SanctionsRepository(client).forStudent('s1');

    final req = server.requestTo('/sanctions');
    expect(req.uri.queryParameters['student_id'], 'eq.s1');
    expect(req.uri.queryParameters['order'], startsWith('decided_at.desc'));
    expect(list.single.sanctionType, SanctionType.suspension);
    expect(list.single.endsOn, DateTime(2026, 10, 8));
    expect(list.single.affectsEnrollment, isFalse);
  });
}
