import 'package:capstone_dashboard/data/professor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

// Plain tests only: this talks to a real local socket.
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

  test('one entry per student, with the subjects they share', () async {
    server.respond = (r) => r.path.endsWith('/rpc/suspended_students_for_professor')
        ? (
            200,
            [
              {
                'student_id': 's1',
                'student_name': 'Juan Dela Cruz',
                'student_number': '2024-0001',
                'subject_title': 'Data Structures',
                'effective_on': '2026-03-10',
                'ends_on': '2026-03-12',
              },
              {
                'student_id': 's1',
                'student_name': 'Juan Dela Cruz',
                'student_number': '2024-0001',
                'subject_title': 'Networks',
                'effective_on': '2026-03-10',
                'ends_on': '2026-03-12',
              },
              {
                'student_id': 's2',
                'student_name': 'Maria Santos',
                'student_number': '2024-0002',
                'subject_title': 'Networks',
                'effective_on': '2026-03-11',
                'ends_on': null,
              },
            ]
          )
        : (200, []);

    final notes = await ProfessorRepository(client).fetchSuspendedStudents();

    expect(notes, hasLength(2));
    expect(notes[0].studentName, 'Juan Dela Cruz');
    expect(notes[0].subjects, ['Data Structures', 'Networks']);
    expect(notes[0].startsOn, DateTime(2026, 3, 10));
    expect(notes[0].endsOn, DateTime(2026, 3, 12));
    expect(notes[1].studentName, 'Maria Santos');
    expect(notes[1].endsOn, isNull);
  });

  test('is empty when the function is not installed yet', () async {
    server.respond = (r) => (
          404,
          {
            'code': 'PGRST202',
            'message': 'Could not find the function',
          }
        );
    final notes = await ProfessorRepository(client).fetchSuspendedStudents();
    expect(notes, isEmpty);
  });
}
