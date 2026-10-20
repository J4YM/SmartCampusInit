import 'dart:typed_data';

import 'package:capstone_dashboard/data/professor_repository.dart';
import 'package:capstone_dashboard/data/violation_evidence_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

EvidenceFile _photo(String name) => EvidenceFile(
      name: name,
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );

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

  test('upload stores each photo under the reporter folder and returns paths',
      () async {
    server.respond = (r) => (200, {'Key': 'violation-evidence/x'});
    final paths = await ViolationEvidenceRepository(client)
        .upload([_photo('one.jpg'), _photo('two.jpg')], folder: 'prof-1');

    expect(paths, hasLength(2));
    expect(paths.every((p) => p.startsWith('prof-1/')), isTrue);
    expect(paths.every((p) => p.endsWith('.jpg')), isTrue);
    final uploads = server.requests.where(
        (r) => r.path.contains('/storage/v1/object/violation-evidence/'));
    expect(uploads, hasLength(2));
  });

  test('only jpeg, png and webp photos up to 5 MB are accepted', () {
    expect(() => ViolationEvidenceRepository.validate(_photo('a.jpg')),
        returnsNormally);
    expect(
      () => ViolationEvidenceRepository.validate(EvidenceFile(
          name: 'a.pdf',
          bytes: Uint8List(10),
          contentType: 'application/pdf')),
      throwsA(isA<ViolationEvidenceException>()),
    );
    expect(
      () => ViolationEvidenceRepository.validate(EvidenceFile(
          name: 'big.jpg',
          bytes: Uint8List(5 * 1024 * 1024 + 1),
          contentType: 'image/jpeg')),
      throwsA(isA<ViolationEvidenceException>()),
    );
  });

  group('ProfessorRepository.submitIncidentReport', () {
    test('uploads evidence, then files the report with its paths', () async {
      server.respond = (r) => r.path.contains('/rpc/submit_incident_report')
          ? (200, 'violation-9')
          : (200, {'Key': 'k'});
      final id = await ProfessorRepository(client).submitIncidentReport(
        studentId: 's1',
        incidentAt: DateTime.utc(2026, 10, 19, 3),
        description: '  Seen vaping  ',
        evidence: [_photo('a.jpg')],
        professorId: 'p1',
      );

      expect(id, 'violation-9');
      final body = server.requestTo('/rpc/submit_incident_report').json;
      expect(body['p_student_id'], 's1');
      expect(body['p_incident_at'], '2026-10-19T03:00:00.000Z');
      expect(body['p_description'], 'Seen vaping');
      expect((body['p_evidence_paths'] as List), hasLength(1));
      expect(body['p_reported_by'], 'p1');
      expect(body['p_professor_id'], 'p1');
    });

    test('a future incident time is rejected before anything is sent', () async {
      await expectLater(
        ProfessorRepository(client).submitIncidentReport(
          studentId: 's1',
          incidentAt: DateTime.now().add(const Duration(days: 1)),
          description: 'x',
          evidence: const [],
          professorId: 'p1',
        ),
        throwsA(isA<ProfessorRepositoryException>().having(
            (e) => e.message, 'message',
            'Incident date and time cannot be in the future.')),
      );
      expect(server.requests, isEmpty);
    });

    test('a bad photo is rejected before the report is filed', () async {
      await expectLater(
        ProfessorRepository(client).submitIncidentReport(
          studentId: 's1',
          incidentAt: DateTime.utc(2026, 10, 19),
          description: 'x',
          evidence: [
            EvidenceFile(
                name: 'a.exe', bytes: Uint8List(5), contentType: 'application/x')
          ],
          professorId: 'p1',
        ),
        throwsA(isA<ProfessorRepositoryException>()),
      );
      expect(server.requests, isEmpty);
    });

    test('a blank description is rejected', () async {
      await expectLater(
        ProfessorRepository(client).submitIncidentReport(
          studentId: 's1',
          incidentAt: DateTime.utc(2026, 10, 19),
          description: '   ',
          evidence: const [],
          professorId: 'p1',
        ),
        throwsA(isA<ProfessorRepositoryException>()),
      );
      expect(server.requests, isEmpty);
    });
  });
}
