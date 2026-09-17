import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_conflict_detector.dart';
import 'package:capstone_dashboard/data/schedule_import/schedule_import_row.dart';

ScheduleImportRow _meeting({
  required ScheduleComponent? component,
  required String day,
  required String start,
  required String end,
}) =>
    ScheduleImportRow(
      subjectTitle: 'x',
      component: component,
      day: day,
      startTime: start,
      endTime: end,
    );

void main() {
  group('expectedWeeklyMinutes', () {
    test('a plain (non-split) subject maps units 1:1 to hours', () {
      expect(expectedWeeklyMinutes(lectureUnits: null, labUnits: null, plainUnits: 3), 180);
    });
    test('lecture units count 1 unit = 1 hour', () {
      expect(expectedWeeklyMinutes(lectureUnits: 2, labUnits: null, plainUnits: null), 120);
    });
    test('lab units count 1 unit = 3 hours', () {
      expect(expectedWeeklyMinutes(lectureUnits: null, labUnits: 1, plainUnits: null), 180);
    });
    test('lecture and lab units combine', () {
      expect(expectedWeeklyMinutes(lectureUnits: 2, labUnits: 1, plainUnits: null), 300);
    });
  });

  group('validateUnitHours', () {
    test('matches when a single 3-hour block covers a 3-unit plain subject', () {
      final result = validateUnitHours('The Entrepreneurial Mind', 'BSTM 3C', [
        _meeting(component: null, day: 'F', start: '07:00', end: '10:00'),
      ], plainUnits: 3);
      expect(result.expectedMinutes, 180);
      expect(result.actualMinutes, 180);
      expect(result.matches, isTrue);
    });

    test('matches when lecture and lab meetings sum to the expected total', () {
      final result = validateUnitHours('Human Computer Interaction', 'BSIT 2A', [
        _meeting(component: ScheduleComponent.lecture, day: 'T', start: '07:00', end: '09:00'),
        _meeting(component: ScheduleComponent.laboratory, day: 'TH', start: '07:00', end: '10:00'),
      ], lectureUnits: 2, labUnits: 1);
      expect(result.expectedMinutes, 300);
      expect(result.actualMinutes, 300);
      expect(result.matches, isTrue);
    });

    test('flags a mismatch when scheduled hours fall short of the expected total', () {
      final result = validateUnitHours('Great Books', 'BSTM 3C', [
        _meeting(component: null, day: 'W', start: '07:00', end: '09:00'),
      ], plainUnits: 3);
      expect(result.expectedMinutes, 180);
      expect(result.actualMinutes, 120);
      expect(result.matches, isFalse);
    });

    test('a subject with zero parsed meetings has zero actual minutes and does not match', () {
      final result = validateUnitHours('Ethics', 'BSTM 3C', [], plainUnits: 3);
      expect(result.actualMinutes, 0);
      expect(result.matches, isFalse);
    });
  });

  group('detectOverlapConflicts', () {
    test('flags the same professor double-booked at an overlapping time', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', professorName: 'Jane Cruz',
          day: 'M', startTime: '10:00', endTime: '12:00',
        ),
      ];
      final conflicts = detectOverlapConflicts(meetings);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ScheduleConflictKind.professorOverlap);
    });

    test('flags the same room double-booked at an overlapping time', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', room: 'RM 202',
          day: 'W', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', room: 'RM 202',
          day: 'W', startTime: '10:30', endTime: '12:00',
        ),
      ];
      final conflicts = detectOverlapConflicts(meetings);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ScheduleConflictKind.roomOverlap);
    });

    test('does not flag two meetings on different days', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', professorName: 'Jane Cruz',
          day: 'T', startTime: '09:00', endTime: '11:00',
        ),
      ];
      expect(detectOverlapConflicts(meetings), isEmpty);
    });

    test('does not flag two meetings that touch but do not overlap', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B', professorName: 'Jane Cruz',
          day: 'M', startTime: '11:00', endTime: '12:00',
        ),
      ];
      expect(detectOverlapConflicts(meetings), isEmpty);
    });

    test('ignores meetings with no professor/room set for that kind of overlap', () {
      final meetings = [
        ScheduleImportRow(
          subjectTitle: 'Subject A',
          day: 'M', startTime: '09:00', endTime: '11:00',
        ),
        ScheduleImportRow(
          subjectTitle: 'Subject B',
          day: 'M', startTime: '10:00', endTime: '12:00',
        ),
      ];
      expect(detectOverlapConflicts(meetings), isEmpty);
    });
  });

  group('detectSourceDisagreements', () {
    test('flags when CFL and Room Schedule give different rooms for the same meeting', () {
      final cfl = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      final roomSchedule = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 203',
        ),
      ];
      final conflicts = detectSourceDisagreements(cfl, roomSchedule);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.kind, ScheduleConflictKind.sourceDisagreement);
    });

    test('does not flag when both sources agree', () {
      final cfl = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      final roomSchedule = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      expect(detectSourceDisagreements(cfl, roomSchedule), isEmpty);
    });

    test('does not flag a meeting only present in one source', () {
      final cfl = [
        ScheduleImportRow(
          subjectTitle: 'Subject A', section: 'BSIT 2A', professorName: 'Jane Cruz',
          day: 'M', startTime: '09:00', endTime: '11:00', room: 'RM 202',
        ),
      ];
      expect(detectSourceDisagreements(cfl, []), isEmpty);
    });
  });
}
