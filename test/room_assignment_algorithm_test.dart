import 'package:capstone_dashboard/data/room_assignment/room_assignment_algorithm.dart';
import 'package:capstone_dashboard/data/room_assignment/room_assignment_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('minutesSinceMidnight', () {
    test('parses HH:MM and HH:MM:SS the same way', () {
      expect(minutesSinceMidnight('08:30'), 510);
      expect(minutesSinceMidnight('08:30:00'), 510);
    });

    test('returns null for unparseable input', () {
      expect(minutesSinceMidnight('not-a-time'), isNull);
    });
  });

  group('assignRooms', () {
    const lecture101 = RoomRecord(id: 'r1', roomNumber: 'RM 101', capacity: 30, roomType: 'Lecture');
    const lecture102 = RoomRecord(id: 'r2', roomNumber: 'RM 102', capacity: 50, roomType: 'Lecture');
    const lab1 = RoomRecord(id: 'r3', roomNumber: 'Computer Lab 1', capacity: 25, roomType: 'Computer Laboratory');
    const gym = RoomRecord(
      id: 'r4',
      roomNumber: 'GYM',
      capacity: 150,
      roomType: 'Laboratory',
      restrictedSubjectKeyword: 'PE',
    );

    test('assigns a PE meeting to the restricted GYM room', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Laboratory',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
        subjectSearchText: 'pe 1 physical education',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lab1, gym],
        sectionHeadcounts: {'s1': 40}, // too big for Computer Lab 1 (cap 25)
      );

      expect(result.assignments['m1']?.roomNumber, 'GYM');
    });

    test('never assigns a non-PE laboratory meeting to the GYM, even when '
        'no other room fits', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Laboratory',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
        subjectSearchText: 'cs101 programming 1',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [gym], // only the restricted room exists
        sectionHeadcounts: {'s1': 20},
      );

      expect(result.assignments, isEmpty);
      expect(result.unassigned.single.meetingId, 'm1');
    });

    test('never assigns the GYM to a PE meeting scheduled as a lecture '
        'component either, as long as the subject matches', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
        subjectSearchText: 'pe 1 physical education',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [gym],
        sectionHeadcounts: {'s1': 20},
      );

      // The restriction keyword overrides the ordinary Lecture/Laboratory
      // room_type check entirely — a matching subject can use the GYM
      // regardless of which component this particular meeting is.
      expect(result.assignments['m1']?.roomNumber, 'GYM');
    });

    test('assigns a lecture meeting to a lecture room, never a lab room', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lecture101, lab1],
        sectionHeadcounts: {'s1': 20},
      );

      expect(result.assignments['m1']?.roomNumber, 'RM 101');
      expect(result.unassigned, isEmpty);
    });

    test('assigns a laboratory meeting only to a lab-type room', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Laboratory',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lecture101, lecture102, lab1],
        sectionHeadcounts: {'s1': 20},
      );

      expect(result.assignments['m1']?.roomNumber, 'Computer Lab 1');
    });

    test('picks the smallest eligible room that still fits the headcount', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lecture102, lecture101], // 50-cap listed before 30-cap
        sectionHeadcounts: {'s1': 28},
      );

      // RM 101 (cap 30) fits and is smaller than RM 102 (cap 50).
      expect(result.assignments['m1']?.roomNumber, 'RM 101');
    });

    test('leaves a meeting unassigned when no room has enough capacity', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lecture101],
        sectionHeadcounts: {'s1': 40},
      );

      expect(result.assignments, isEmpty);
      expect(result.unassigned, hasLength(1));
      expect(result.unassigned.single.meetingId, 'm1');
    });

    test('never double-books a room for two overlapping meetings on the same day', () {
      const meetingA = MeetingToAssign(
        meetingId: 'mA',
        sectionId: 'sA',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:30',
      );
      const meetingB = MeetingToAssign(
        meetingId: 'mB',
        sectionId: 'sB',
        component: 'Lecture',
        day: 'M',
        startTime: '09:00', // overlaps meetingA's 08:00-09:30
        endTime: '10:00',
      );

      final result = assignRooms(
        meetings: [meetingA, meetingB],
        rooms: [lecture101], // only one eligible room available
        sectionHeadcounts: {'sA': 20, 'sB': 20},
      );

      expect(result.assignments['mA']?.roomNumber, 'RM 101');
      // mB can't share RM 101 at an overlapping time, and there's no other
      // eligible room, so it's reported unassigned rather than conflicting.
      expect(result.assignments.containsKey('mB'), isFalse);
      expect(result.unassigned.single.meetingId, 'mB');
    });

    test('allows two non-overlapping meetings to share the same room on the same day', () {
      const meetingA = MeetingToAssign(
        meetingId: 'mA',
        sectionId: 'sA',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );
      const meetingB = MeetingToAssign(
        meetingId: 'mB',
        sectionId: 'sB',
        component: 'Lecture',
        day: 'M',
        startTime: '09:00', // starts exactly when meetingA ends — no overlap
        endTime: '10:00',
      );

      final result = assignRooms(
        meetings: [meetingA, meetingB],
        rooms: [lecture101],
        sectionHeadcounts: {'sA': 20, 'sB': 20},
      );

      expect(result.assignments['mA']?.roomNumber, 'RM 101');
      expect(result.assignments['mB']?.roomNumber, 'RM 101');
    });

    test('respects pre-existing bookings passed in via alreadyBooked', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 's1',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lecture101],
        sectionHeadcounts: {'s1': 20},
        alreadyBooked: {
          'r1|M': [(480, 540)], // 08:00-09:00, same room/day as the meeting
        },
      );

      expect(result.assignments, isEmpty);
      expect(result.unassigned.single.meetingId, 'm1');
    });

    test('treats an unrecognized headcount (section not in the map) as zero, '
        'not a crash', () {
      const meeting = MeetingToAssign(
        meetingId: 'm1',
        sectionId: 'unknown-section',
        component: 'Lecture',
        day: 'M',
        startTime: '08:00',
        endTime: '09:00',
      );

      final result = assignRooms(
        meetings: [meeting],
        rooms: [lecture101],
        sectionHeadcounts: const {},
      );

      expect(result.assignments['m1']?.roomNumber, 'RM 101');
    });
  });
}
