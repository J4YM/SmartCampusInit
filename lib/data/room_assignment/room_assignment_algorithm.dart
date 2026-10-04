import 'room_assignment_models.dart';

/// "HH:MM" or "HH:MM:SS" -> minutes since midnight. Returns null for
/// anything unparseable rather than throwing — a malformed time on one
/// meeting shouldn't crash the whole run; [assignRooms] treats that
/// meeting as unassignable instead.
int? minutesSinceMidnight(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

bool _rangesOverlap(int startA, int endA, int startB, int endB) =>
    startA < endB && startB < endA;

/// A restricted room (e.g. the GYM, keyed to "PE") only ever matches a
/// meeting whose own subject text contains its keyword — room_type is
/// irrelevant in that case, so a PE "Laboratory" meeting can't accidentally
/// land in some other lab just because its room_type isn't "Lecture", and
/// no OTHER Laboratory meeting can land in the GYM just because the GYM's
/// own room_type isn't "Lecture" either.
///
/// An unrestricted room matches by [MeetingToAssign.component] alone:
/// Laboratory meetings need an actual lab room; everything else (Lecture,
/// or no component recorded) needs a plain lecture room. A room "is" a lab
/// room if its type isn't literally "Lecture" (so "Laboratory", "Computer
/// Laboratory", or any future lab-ish type all qualify without an
/// algorithm change).
bool _roomTypeMatches(String component, RoomRecord room, String subjectSearchText) {
  final keyword = room.restrictedSubjectKeyword;
  if (keyword != null && keyword.isNotEmpty) {
    return subjectSearchText.toLowerCase().contains(keyword.toLowerCase());
  }
  final isLabMeeting = component == 'Laboratory';
  final isLabRoom = room.roomType.trim().toLowerCase() != 'lecture';
  return isLabMeeting == isLabRoom;
}

/// Greedy room assignment: processes [meetings] in (day, start time) order
/// so earlier-in-the-week classes get first pick, and for each one chooses
/// the smallest-capacity eligible room that still fits the section's
/// headcount and isn't already booked at an overlapping time — conserving
/// larger rooms for sections that actually need them, rather than the
/// first match found.
///
/// [alreadyBooked] seeds the conflict check with bookings this run must
/// not collide with (meetings that already have a real, non-'TBA' room —
/// see RoomAssignmentRepository's own doc comment for why those are left
/// untouched rather than reassigned). Keyed `'$roomId|$day'` -> list of
/// (start, end) minute ranges.
RoomAssignmentResult assignRooms({
  required List<MeetingToAssign> meetings,
  required List<RoomRecord> rooms,
  required Map<String, int> sectionHeadcounts,
  Map<String, List<(int, int)>> alreadyBooked = const {},
}) {
  final booked = <String, List<(int, int)>>{
    for (final entry in alreadyBooked.entries) entry.key: [...entry.value],
  };

  final sorted = [...meetings]..sort((a, b) {
      final dayCompare = a.day.compareTo(b.day);
      if (dayCompare != 0) return dayCompare;
      return a.startTime.compareTo(b.startTime);
    });

  final assignments = <String, RoomRecord>{};
  final unassigned = <UnassignedMeeting>[];

  for (final meeting in sorted) {
    final start = minutesSinceMidnight(meeting.startTime);
    final end = minutesSinceMidnight(meeting.endTime);
    if (start == null || end == null) {
      unassigned.add(UnassignedMeeting(
        meetingId: meeting.meetingId,
        reason: 'Could not parse this meeting\'s start/end time.',
      ));
      continue;
    }

    final headcount = sectionHeadcounts[meeting.sectionId] ?? 0;
    final component = meeting.component ?? 'Lecture';

    final eligible = rooms
        .where((r) =>
            _roomTypeMatches(component, r, meeting.subjectSearchText) &&
            r.capacity >= headcount)
        .toList()
      ..sort((a, b) => a.capacity.compareTo(b.capacity));

    RoomRecord? chosen;
    for (final room in eligible) {
      final key = '${room.id}|${meeting.day}';
      final existing = booked[key] ?? const [];
      final conflicts =
          existing.any((range) => _rangesOverlap(start, end, range.$1, range.$2));
      if (!conflicts) {
        chosen = room;
        break;
      }
    }

    if (chosen == null) {
      final reason = eligible.isEmpty
          ? 'No ${component == 'Laboratory' ? 'laboratory' : 'lecture'} room '
              'with capacity >= $headcount exists.'
          : 'Every eligible room is already booked on ${meeting.day} at '
              'that time.';
      unassigned.add(UnassignedMeeting(meetingId: meeting.meetingId, reason: reason));
      continue;
    }

    assignments[meeting.meetingId] = chosen;
    final key = '${chosen.id}|${meeting.day}';
    (booked[key] ??= []).add((start, end));
  }

  return RoomAssignmentResult(assignments: assignments, unassigned: unassigned);
}
