import 'package:capstone_dashboard/data/office_reports_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/recording_server.dart';

Map<String, dynamic> _student(String number, String first, String last,
        {String section = 'BSIT 3-A', String course = 'BSIT'}) =>
    {
      'student_number': number,
      'course': course,
      'profiles': {'first_name': first, 'last_name': last},
      'sections': {'name': section},
    };

// Plain tests only: this talks to a real local socket.
void main() {
  late RecordingServer server;
  late SupabaseClient client;
  final answers = <String, List<Map<String, dynamic>>>{};

  setUp(() async {
    answers.clear();
    server = RecordingServer();
    server.respond = (r) {
      for (final e in answers.entries) {
        if (r.path.endsWith('/${e.key}')) return (200, e.value);
      }
      return (200, []);
    };
    await server.start();
    client = SupabaseClient(server.url, 'anon-key');
  });
  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  OfficeReportsRepository repo() => OfficeReportsRepository(client);

  group('offense tier counts', () {
    test('counts Minor and Major per student and reports the highest tier',
        () async {
      answers['student_violations'] = [
        {
          'student_id': 's1',
          'created_at': '2026-03-01T00:00:00Z',
          'students': _student('2024-0001', 'Jane', 'Doe'),
          'handbook_offenses': {'category': 'Minor'},
        },
        {
          'student_id': 's1',
          'created_at': '2026-03-05T00:00:00Z',
          'students': _student('2024-0001', 'Jane', 'Doe'),
          'handbook_offenses': {'category': 'Minor'},
        },
        {
          'student_id': 's1',
          'created_at': '2026-03-09T00:00:00Z',
          'students': _student('2024-0001', 'Jane', 'Doe'),
          'handbook_offenses': {'category': 'Minor'},
        },
        {
          'student_id': 's2',
          'created_at': '2026-03-20T00:00:00Z',
          'students': _student('2024-0002', 'Ben', 'Reyes'),
          'handbook_offenses': {'category': 'Major_B'},
        },
      ];
      final r = await repo().fetchOffenseTierCounts();

      expect(r.columns,
          containsAll(['Student Name', 'Minor', 'Major', 'Total', 'Highest Tier']));
      // Most recent offender first.
      expect(r.previewRows.first['Student Name'], 'Ben Reyes');
      final jane = r.previewRows.firstWhere((x) => x['Student Name'] == 'Jane Doe');
      expect(jane['Minor'], 3);
      expect(jane['Major'], 0);
      expect(jane['Total'], 3);
      expect(jane['Highest Tier'], '3rd Offense');
      final ben = r.previewRows.firstWhere((x) => x['Student Name'] == 'Ben Reyes');
      expect(ben['Highest Tier'], '1st Offense');
    });
  });

  group('suspensions', () {
    test('labels each suspension Upcoming, Active or Completed, newest first',
        () async {
      final today = DateTime.now();
      String day(int offset) {
        final d = DateTime(today.year, today.month, today.day + offset);
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }

      answers['sanctions'] = [
        {
          'sanction_type': 'suspension',
          'effective_on': day(-10),
          'ends_on': day(-8),
          'status': 'Completed',
          'description': 'Old',
          'students': _student('1', 'Old', 'One'),
        },
        {
          'sanction_type': 'suspension',
          'effective_on': day(-1),
          'ends_on': day(2),
          'status': 'Serving',
          'description': 'Now',
          'students': _student('2', 'Now', 'Two'),
        },
        {
          'sanction_type': 'suspension',
          'effective_on': day(5),
          'ends_on': day(7),
          'status': 'Pending',
          'description': 'Soon',
          'students': _student('3', 'Soon', 'Three'),
        },
      ];
      final r = await repo().fetchSuspensions();

      expect(r.previewRows.map((x) => x['Student Name']),
          ['Soon Three', 'Now Two', 'Old One']);
      expect(r.previewRows.map((x) => x['Status']),
          ['Upcoming', 'Active', 'Completed']);
    });
  });

  group('parent meeting log', () {
    test('shows Finished for completed meetings and the parent confirmation',
        () async {
      answers['guidance_meetings'] = [
        {
          'scheduled_at': '2026-03-01T01:00:00Z',
          'location': 'Guidance Office',
          'status': 'Completed',
          'invitee': 'parent',
          'parent_attended': true,
          'summary': 'Agreed on a plan',
          'students': _student('2024-0001', 'Jane', 'Doe'),
        },
        {
          'scheduled_at': '2026-03-10T01:00:00Z',
          'location': null,
          'status': 'Completed',
          'invitee': 'both',
          'parent_attended': null,
          'summary': null,
          'students': _student('2024-0002', 'Ben', 'Reyes'),
        },
        {
          'scheduled_at': '2026-03-12T01:00:00Z',
          'location': null,
          'status': 'Proposed',
          'invitee': 'parent',
          'parent_attended': null,
          'summary': null,
          'students': _student('2024-0003', 'Cara', 'Lim'),
        },
      ];
      final r = await repo().fetchParentMeetingLog();

      expect(r.previewRows.map((x) => x['Student Name']),
          ['Cara Lim', 'Ben Reyes', 'Jane Doe']);
      expect(r.previewRows.map((x) => x['Status']),
          ['Proposed', 'Finished', 'Finished']);
      expect(r.previewRows.map((x) => x['Parent Attended']),
          ['--', 'Not confirmed', 'Yes']);
      expect(r.previewRows.last['Summary'], 'Agreed on a plan');
    });

    test('only parent-invited meetings are requested', () async {
      await repo().fetchParentMeetingLog();
      final q = server.requestTo('/guidance_meetings').uri.queryParameters;
      expect(q['invitee'], startsWith('in.'));
      expect(q['invitee'], contains('parent'));
      expect(q['invitee'], contains('both'));
    });
  });

  group('attendance by teacher and subject', () {
    test('tallies class marks per teacher and subject', () async {
      Map<String, dynamic> mark(String status, String teacher, String subject) =>
          {
            'status': status,
            'session_date': '2026-03-02',
            'students': _student('1', 'A', 'B'),
            'class_sections': {
              'subjects': {'title': subject},
              'profiles': {'first_name': teacher, 'last_name': 'T'},
            },
          };
      answers['attendance_records'] = [
        mark('Present', 'Ana', 'Data Structures'),
        mark('Present', 'Ana', 'Data Structures'),
        mark('Late', 'Ana', 'Data Structures'),
        mark('Absent', 'Ana', 'Data Structures'),
        mark('Excused', 'Ana', 'Data Structures'),
        mark('Present', 'Ben', 'Networks'),
      ];
      final r = await repo().fetchAttendanceByTeacherSubject();

      final ana = r.previewRows.firstWhere((x) => x['Teacher'] == 'Ana T');
      expect(ana['Subject'], 'Data Structures');
      expect(ana['Present'], 2);
      expect(ana['Late'], 1);
      expect(ana['Absent'], 1);
      expect(ana['Excused'], 1);
      expect(ana['Total'], 5);
      expect(ana['Attendance Rate'], '60.0%'); // (present + late) / total
      expect(r.previewRows, hasLength(2));
    });
  });

  group('good moral requests', () {
    test('lists requests newest first with the request status', () async {
      answers['good_moral_requests'] = [
        {
          'document_type': 'Good Moral Certificate',
          'purpose': 'Scholarship',
          'request_date': '2026-03-10T00:00:00Z',
          'status': 'Pending',
          'students': _student('2024-0001', 'Jane', 'Doe'),
        },
      ];
      final r = await repo().fetchGoodMoralRequests();
      expect(r.previewRows.single['Purpose'], 'Scholarship');
      expect(r.previewRows.single['Status'], 'Pending');
      expect(server.requestTo('/good_moral_requests').uri.queryParameters['order'],
          contains('request_date.desc'));
    });
  });

  test('a missing column explains which migration to run', () async {
    server.respond = (r) =>
        (400, {'code': '42703', 'message': 'column parent_ack_at does not exist'});
    final r = await repo().fetchParentAcknowledgments();
    expect(r.previewRows, isEmpty);
    expect(r.emptyMessage, contains('add_defense_revisions.sql'));
  });
}
