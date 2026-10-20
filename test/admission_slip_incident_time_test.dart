import 'package:capstone_dashboard/data/admission_slip_repository.dart';
import 'package:capstone_dashboard/kiosk/supabase_kiosk_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_offline/kiosk_offline.dart';
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

  final incidentAt = DateTime.utc(2026, 10, 19, 3, 30);

  test('the slip repository sends the incident time when it is known', () async {
    await AdmissionSlipRepository(client).submit(AdmissionSlipSubmission(
      slipId: 'slip-1',
      studentId: 's1',
      reportedBy: 'staff-1',
      offenseIds: const [],
      notes: 'Fight near the canteen',
      incidentAt: incidentAt,
    ));
    final body = server.requestTo('/rpc/submit_admission_slip').json;
    expect(body['p_incident_at'], '2026-10-19T03:30:00.000Z');
    expect(body['p_offense_ids'], isEmpty);
    expect(body['p_incident_notes'], 'Fight near the canteen');
  });

  test('without an incident time the parameter is omitted', () async {
    await AdmissionSlipRepository(client).submit(const AdmissionSlipSubmission(
      slipId: 'slip-2',
      studentId: 's1',
      reportedBy: 'kiosk',
      offenseIds: ['o1'],
    ));
    expect(server.requestTo('/rpc/submit_admission_slip').json,
        isNot(contains('p_incident_at')));
  });

  test('the offline kiosk remote forwards the incident time', () async {
    await SupabaseKioskRemote(client).submitSlip(SlipSubmission(
      slipId: 'slip-3',
      studentId: 's1',
      reportedBy: 'staff-1',
      offenseIds: const [],
      notes: 'Vandalism',
      incidentAt: incidentAt,
    ));
    expect(server.requestTo('/rpc/submit_admission_slip').json['p_incident_at'],
        '2026-10-19T03:30:00.000Z');
  });

  test('an outbox row round-trips the incident time', () {
    final slip = SlipSubmission(
      slipId: 'slip-4',
      studentId: 's1',
      reportedBy: 'staff-1',
      offenseIds: const [],
      notes: 'n',
      incidentAt: incidentAt,
    );
    expect(SlipSubmission.fromJson(slip.toJson()).incidentAt, incidentAt);
  });

  test('an outbox row queued by an older build still loads', () {
    final old = SlipSubmission.fromJson({
      'slipId': 'old',
      'studentId': 's1',
      'reportedBy': 'kiosk',
      'offenseIds': ['o1'],
    });
    expect(old.incidentAt, isNull);
  });

  test('a slip with an unclassified violation reads as awaiting classification',
      () async {
    server.respond = (r) => r.path.endsWith('/admission_slips')
        ? (200, {
            'id': 'slip-5',
            'created_at': '2026-10-19T04:00:00Z',
            'students': {
              'student_number': '2024-1',
              'profiles': {'first_name': 'Jane', 'last_name': 'Doe'},
              'sections': {'name': 'BSIT 1A'},
            },
            'profiles': {'first_name': 'Sec', 'last_name': 'Guard'},
          })
        : (200, [
            {'status': 'Pending', 'handbook_offenses': null}
          ]);
    final detail = await AdmissionSlipRepository(client).fetchSlipDetail('slip-5');
    expect(detail, isNotNull);
    expect(detail!.violations.single.offenseLabel, 'Awaiting classification');
  });
}
