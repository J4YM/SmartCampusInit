import 'package:capstone_dashboard/data/guidance_investigation_repository.dart';
import 'package:capstone_dashboard/data/investigation_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an investigation maps every field the Investigations tab shows', () {
    final investigation = GuidanceInvestigation.fromRow({
      'id': 'i1',
      'violation_id': 'v1',
      'student_id': 's1',
      'status': 'Open',
      'findings': 'Mutual altercation.',
      'recommendation': 'Warning',
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
          'location': 'Discipline Office',
          'invitee': 'parent',
          'status': 'Declined',
          'response_note': 'Out of town',
        }
      ],
    });

    final model = toInvestigationModel(investigation);

    expect(model.id, 'i1');
    expect(model.studentName, 'Jane Doe');
    expect(model.studentNumber, '2024-0001');
    expect(model.section, 'BSIT 3-A');
    expect(model.offenseLabel, 'Fighting');
    expect(model.offenseCategory, 'Major_B');
    expect(model.incidentNotes, 'Fight in hallway');
    expect(model.incidentAt, DateTime.utc(2026, 10, 19, 3).toLocal());
    expect(model.status, 'Open');
    expect(model.findings, 'Mutual altercation.');
    expect(model.recommendation, 'Warning');
    expect(model.evidencePaths, ['p/a.jpg']);
    final meeting = model.meetings.single;
    expect(meeting.id, 'm1');
    expect(meeting.invitee, 'parent');
    expect(meeting.status, 'Declined');
    expect(meeting.location, 'Discipline Office');
    expect(meeting.responseNote, 'Out of town');
  });

  test('a meeting that belongs to an endorsement has no investigation id', () {
    final meeting = GuidanceMeeting.fromRow({
      'id': 'm2',
      'investigation_id': null,
      'student_id': 's1',
      'scheduled_at': '2026-11-03T01:30:00Z',
      'invitee': 'parent',
      'status': 'Proposed',
    });
    expect(meeting.investigationId, isNull);
  });
}
