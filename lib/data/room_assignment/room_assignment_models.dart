/// One `class_section_meetings` row still needing a real room (`room =
/// 'TBA'`) — everything [assignRooms] needs to pick one, without this
/// pure-Dart algorithm module depending on Supabase directly (matches
/// enrollment_file_parser.dart's own "parser knows nothing about the
/// database" convention).
class MeetingToAssign {
  const MeetingToAssign({
    required this.meetingId,
    required this.sectionId,
    required this.component,
    required this.day,
    required this.startTime,
    required this.endTime,
    this.subjectSearchText = '',
  });

  final String meetingId;

  /// The home `sections.id` this offering's students belong to — looked
  /// up in [RoomAssignmentInput.sectionHeadcounts] for the capacity check.
  final String sectionId;

  /// 'Lecture', 'Laboratory', or null — null is treated the same as
  /// 'Lecture' (a plain classroom, not a lab) for room-type matching.
  final String? component;

  /// 'M','T','W','TH','F','S'.
  final String day;

  /// "HH:MM" or "HH:MM:SS" (Postgres `time` serialization) — either works,
  /// see [minutesSinceMidnight].
  final String startTime;
  final String endTime;

  /// The offering's subject code + title, lowercased and concatenated —
  /// checked against a restricted room's [RoomRecord.restrictedSubjectKeyword]
  /// (e.g. the GYM only matching a "PE" subject). Empty when the caller
  /// doesn't have/need subject info, which simply means this meeting can
  /// never match a restricted room (the common, correct case for anything
  /// that isn't PE).
  final String subjectSearchText;
}

/// One `rooms` row (supabase/add_rooms_schema.sql).
class RoomRecord {
  const RoomRecord({
    required this.id,
    required this.roomNumber,
    required this.capacity,
    required this.roomType,
    this.restrictedSubjectKeyword,
  });

  final String id;
  final String roomNumber;
  final int capacity;

  /// Free text (e.g. "Lecture", "Laboratory", "Computer Laboratory") — only
  /// "does this say Lecture or not" is checked, see
  /// [MeetingToAssign.component]'s own doc comment, so new lab-ish types
  /// don't need an algorithm change to become eligible for Laboratory
  /// meetings. Ignored entirely when [restrictedSubjectKeyword] is set —
  /// that check takes over instead.
  final String roomType;

  /// When non-null, this room is eligible ONLY for a meeting whose
  /// [MeetingToAssign.subjectSearchText] contains this keyword
  /// (case-insensitive) — e.g. the GYM is restricted to "PE" so it's never
  /// handed to an unrelated Laboratory-component meeting just because its
  /// room_type isn't "Lecture". Null (the common case) means no
  /// restriction — matched by [roomType] alone.
  final String? restrictedSubjectKeyword;
}

/// One meeting [assignRooms] couldn't place, with a human-readable reason
/// for the Scheduling Officer's result dialog.
class UnassignedMeeting {
  const UnassignedMeeting({required this.meetingId, required this.reason});

  final String meetingId;
  final String reason;
}

class RoomAssignmentResult {
  const RoomAssignmentResult({
    required this.assignments,
    required this.unassigned,
  });

  /// meetingId -> the room picked for it.
  final Map<String, RoomRecord> assignments;
  final List<UnassignedMeeting> unassigned;
}
