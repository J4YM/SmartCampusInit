import 'package:capstone_dashboard/data/academic_term_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

// Plain tests only: the repository group talks to a real local socket.
void main() {
  group('AcademicTerm', () {
    Map<String, dynamic> row({String? startsOn, String? endsOn}) => {
          'id': 't1',
          'school_year': '2026-2027',
          'term': '1st Semester',
          'is_current': true,
          'started_at': '2026-08-01T00:00:00Z',
          'starts_on': startsOn,
          'ends_on': endsOn,
        };

    test('reads the academic-year start and end dates', () {
      final t = AcademicTerm.fromRow(row(startsOn: '2026-08-04', endsOn: '2027-05-30'));
      expect(t.startsOn, DateTime(2026, 8, 4));
      expect(t.endsOn, DateTime(2027, 5, 30));
      expect(t.hasDates, isTrue);
      expect(t.datesLabel, 'Aug 4, 2026 – May 30, 2027');
    });

    test('a term without dates says so', () {
      final t = AcademicTerm.fromRow(row());
      expect(t.hasDates, isFalse);
      expect(t.datesLabel, 'Dates not set');
    });

    test('contains() is inclusive of both ends and ignores the time of day', () {
      final t = AcademicTerm.fromRow(row(startsOn: '2026-08-04', endsOn: '2027-05-30'));
      expect(t.contains(DateTime(2026, 8, 4, 0, 1)), isTrue);
      expect(t.contains(DateTime(2027, 5, 30, 23, 59)), isTrue);
      expect(t.contains(DateTime(2026, 8, 3, 23, 59)), isFalse);
      expect(t.contains(DateTime(2027, 5, 31)), isFalse);
    });
  });

  group('AcademicTermRepository.setTermDates', () {
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

    test('saves the dates on the term row', () async {
      await AcademicTermRepository(client).setTermDates(
        termId: 't1',
        startsOn: DateTime(2026, 8, 4),
        endsOn: DateTime(2027, 5, 30),
      );
      final req = server.requests.lastWhere((r) => r.method == 'PATCH');
      expect(req.path, endsWith('/academic_terms'));
      expect(req.uri.queryParameters['id'], 'eq.t1');
      expect(req.json, {'starts_on': '2026-08-04', 'ends_on': '2027-05-30'});
    });

    test('an end on or before the start is refused before anything is sent',
        () async {
      for (final end in [DateTime(2026, 8, 4), DateTime(2026, 8, 3)]) {
        await expectLater(
          AcademicTermRepository(client).setTermDates(
            termId: 't1',
            startsOn: DateTime(2026, 8, 4),
            endsOn: end,
          ),
          throwsA(isA<AcademicTermRepositoryException>().having(
              (e) => e.message, 'message', 'The end date must be after the start date.')),
        );
      }
      expect(server.requests, isEmpty);
    });

    test('a database without the columns explains what to run', () async {
      server.respond = (r) => (
            400,
            {
              'code': '42703',
              'message': 'column "starts_on" of relation "academic_terms" does not exist'
            }
          );
      await expectLater(
        AcademicTermRepository(client).setTermDates(
          termId: 't1',
          startsOn: DateTime(2026, 8, 4),
          endsOn: DateTime(2027, 5, 30),
        ),
        throwsA(isA<AcademicTermRepositoryException>().having(
            (e) => e.message, 'message', contains('add_academic_term_dates.sql'))),
      );
    });
  });
}
