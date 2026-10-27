import 'package:capstone_dashboard/data/attendance_activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

Map<String, dynamic> _student(String number, String first, String last) => {
      'student_number': number,
      'course': 'BS Information Technology',
      'profiles': {'first_name': first, 'last_name': last},
      'sections': {'name': 'BSIT 3-A'},
    };

// Plain tests only: this talks to a real local socket.
void main() {
  late RecordingServer server;
  late SupabaseClient client;

  List<Map<String, dynamic>> taps = [];
  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> studentIdHits = [];
  List<Map<String, dynamic>> profileHits = [];

  setUp(() async {
    taps = [
      {
        'id': 't1',
        'tapped_at': '2026-10-20T00:00:00Z', // 8:00 AM Manila
        'tap_direction': 'in',
        'student_id': 's1',
        'rfid_readers': {'label': 'Main Gate', 'location': 'Gate 1'},
        'students': _student('2024-0001', 'Jane', 'Doe'),
      },
      {
        'id': 't2',
        'tapped_at': '2026-10-20T09:00:00Z',
        'tap_direction': 'out',
        'student_id': 's1',
        'rfid_readers': {'label': 'Main Gate', 'location': null},
        'students': _student('2024-0001', 'Jane', 'Doe'),
      },
    ];
    classes = [
      {
        'id': 'c1',
        'status': 'Late',
        'session_date': '2026-10-20',
        'recorded_at': '2026-10-20T03:00:00Z',
        'student_id': 's1',
        'students': _student('2024-0001', 'Jane', 'Doe'),
        'class_sections': {
          'subjects': {'title': 'Data Structures'},
        },
      },
    ];
    studentIdHits = [];
    profileHits = [];
    server = RecordingServer();
    server.respond = (r) {
      if (r.path.endsWith('/rfid_tap_events')) return (200, taps);
      if (r.path.endsWith('/attendance_records')) return (200, classes);
      if (r.path.endsWith('/students')) return (200, studentIdHits);
      if (r.path.endsWith('/profiles')) return (200, profileHits);
      return (200, []);
    };
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });
  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  RecordedRequest req(String suffix) => server.requestTo(suffix);

  test('merges gate taps and class attendance, newest first', () async {
    final log = await AttendanceActivityRepository(client).fetch();

    expect(log.map((e) => e.id), ['t2', 'c1', 't1']);
    expect(log[0].kind, ActivityKind.tapOut);
    expect(log[0].label, 'Tapped out');
    expect(log[1].kind, ActivityKind.classLate);
    expect(log[1].label, 'Class: Late');
    expect(log[1].detail, 'Data Structures');
    expect(log[2].label, 'Tapped in');
    expect(log[2].detail, 'Gate 1');
    expect(log[0].detail, 'Main Gate'); // no location: falls back to the label
    expect(log[0].studentName, 'Jane Doe');
    expect(log[0].studentNumber, '2024-0001');
    expect(log[0].section, 'BSIT 3-A');
  });

  test('a section filter applies to taps (home section) and class records',
      () async {
    await AttendanceActivityRepository(client).fetch(sectionId: 'sec-1');
    expect(req('/rfid_tap_events').uri.queryParameters['students.section_id'],
        'eq.sec-1');
    expect(req('/attendance_records').uri.queryParameters['section_id'],
        'eq.sec-1');
  });

  test('a course filter applies to both sources', () async {
    await AttendanceActivityRepository(client)
        .fetch(course: 'BS Information Technology');
    expect(req('/rfid_tap_events').uri.queryParameters['students.course'],
        'eq.BS Information Technology');
    expect(req('/attendance_records').uri.queryParameters['students.course'],
        'eq.BS Information Technology');
  });

  test('a date range filters both sources and includes the whole last day',
      () async {
    await AttendanceActivityRepository(client).fetch(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 20),
    );
    final tapQuery = req('/rfid_tap_events').uri.query;
    expect(tapQuery, contains('tapped_at=gte.'));
    expect(tapQuery, contains('tapped_at=lt.')); // start of the day after `to`
    final classQuery = req('/attendance_records').uri.query;
    expect(classQuery, contains('session_date=gte.2026-10-01'));
    expect(classQuery, contains('session_date=lte.2026-10-20'));
  });

  test('searching a student resolves their ids by number or name first',
      () async {
    studentIdHits = [
      {'id': 's1'}
    ];
    profileHits = [
      {'id': 's2'}
    ];
    await AttendanceActivityRepository(client).fetch(studentQuery: 'jane');
    final ids = req('/rfid_tap_events').uri.queryParameters['student_id']!;
    expect(ids, startsWith('in.('));
    expect(ids, contains('s1'));
    expect(ids, contains('s2'));
    expect(req('/attendance_records').uri.queryParameters['student_id'],
        ids);
  });

  test('a student search that matches nobody returns nothing, not everyone',
      () async {
    final log =
        await AttendanceActivityRepository(client).fetch(studentQuery: 'zzz');
    expect(log, isEmpty);
    expect(server.requests.where((r) => r.path.endsWith('/rfid_tap_events')),
        isEmpty);
  });

  test('each source is limited', () async {
    await AttendanceActivityRepository(client).fetch(limit: 50);
    expect(req('/rfid_tap_events').uri.queryParameters['limit'], '50');
    expect(req('/attendance_records').uri.queryParameters['limit'], '50');
  });

  test('a missing source does not hide the other', () async {
    server.respond = (r) {
      if (r.path.endsWith('/attendance_records')) {
        return (404, {'code': '42P01', 'message': 'relation does not exist'});
      }
      if (r.path.endsWith('/rfid_tap_events')) return (200, taps);
      return (200, []);
    };
    final log = await AttendanceActivityRepository(client).fetch();
    expect(log.map((e) => e.id), ['t2', 't1']);
  });

  test('a student who did not tap out shows as "Did not tap out", not as a '
      'tap-out', () async {
    server.respond = (r) {
      if (r.path.endsWith('/rfid_tap_events')) return (200, taps);
      if (r.path.endsWith('/missed_tap_outs')) {
        return (
          200,
          [
            {
              'student_id': 's2',
              'school_day': '2026-10-20',
              'created_at': '2026-10-20T10:30:00Z',
              'students': _student('2024-0002', 'Ben', 'Reyes'),
            },
          ]
        );
      }
      return (200, []);
    };

    final log = await AttendanceActivityRepository(client).fetch();

    final missed = log.firstWhere((e) => e.kind == ActivityKind.didNotTapOut);
    expect(missed.label, 'Did not tap out');
    expect(missed.studentName, 'Ben Reyes');
    expect(missed.studentNumber, '2024-0002');
    expect(missed.kind.isClass, isFalse);
    expect(log.where((e) => e.kind == ActivityKind.tapOut), hasLength(1),
        reason: 'only the real tap-out');
    expect(req('/missed_tap_outs').uri.query, contains('select='));
  });

  test('filters apply to the did-not-tap-out source too', () async {
    await AttendanceActivityRepository(client).fetch(
      sectionId: 'sec-1',
      course: 'BS Information Technology',
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 20),
    );
    final q = req('/missed_tap_outs').uri.queryParameters;
    expect(q['students.section_id'], 'eq.sec-1');
    expect(q['students.course'], 'eq.BS Information Technology');
    expect(q['school_day'], isNotNull);
  });
}
