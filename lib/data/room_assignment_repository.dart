import 'package:supabase_flutter/supabase_flutter.dart';

import 'room_assignment/room_assignment_algorithm.dart';
import 'room_assignment/room_assignment_models.dart';

class RoomAssignmentException implements Exception {
  RoomAssignmentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of one [RoomAssignmentRepository.autoAssignRooms] call.
class RoomAssignmentSummary {
  const RoomAssignmentSummary({
    required this.assigned,
    required this.unassigned,
    required this.totalConsidered,
  });

  final int assigned;

  /// One human-readable line per meeting that couldn't be placed (no
  /// eligible room of the right type/capacity, or every eligible room was
  /// already booked at that day/time) — not fatal, matches this
  /// codebase's established "report what didn't make it, don't abort the
  /// whole run" convention (EnrollmentImportSummary.errors,
  /// GradeImportSummary.errors).
  final List<String> unassigned;

  /// How many 'TBA' meetings were found for this school year/term —
  /// `totalConsidered == 0` is what the UI uses to say "nothing to do"
  /// instead of "0 assigned" reading like a failure.
  final int totalConsidered;
}

/// One row of the generated Room Assignment schedule — a meeting for a
/// given school year/term that already has a real room (not 'TBA'),
/// whether assigned by [RoomAssignmentRepository.autoAssignRooms] or
/// supplied directly on the CFL upload. Mirrors
/// SectionScheduleEntryModel's shape (section_schedule_repository.dart)
/// without this being specific to one section — this is every room
/// assignment for the whole school year/term, the analog of that model
/// for "Per Section Schedule".
class RoomAssignmentEntry {
  const RoomAssignmentEntry({
    required this.classSectionId,
    this.subjectCode,
    required this.subjectTitle,
    this.component,
    required this.sectionName,
    required this.professorName,
    required this.room,
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  final String classSectionId;
  final String? subjectCode;
  final String subjectTitle;

  /// 'Lecture', 'Laboratory', or null when the subject has no split.
  final String? component;

  final String sectionName;
  final String professorName;
  final String room;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'.
  final String day;

  /// 24-hour "HH:MM".
  final String startTime;
  final String endTime;
}

/// Auto-generates room assignments for every `class_section_meetings` row
/// still marked 'TBA' (the Confirmation of Faculty Loading upload's own
/// placeholder for "no room on this row" — see
/// ScheduleImportRepository.commitMeetings's doc comment) for a given
/// school year/term — replacing the old "upload a separate Room Schedule
/// file" step with real assignment against the `rooms` inventory
/// (supabase/add_rooms_schema.sql).
///
/// Deliberately leaves any meeting that already has a real (non-'TBA')
/// room untouched — CFL can and does supply a room directly on some rows,
/// and that's treated as the Scheduling Officer's own prior decision, not
/// something to override. Those rows still count as "already booked" when
/// checking the rest of the term for conflicts (see [_fetchAlreadyBooked]).
class RoomAssignmentRepository {
  RoomAssignmentRepository(this._client);
  final SupabaseClient _client;

  static const _dayRank = {'M': 0, 'T': 1, 'W': 2, 'TH': 3, 'F': 4, 'S': 5};

  /// Every meeting for [schoolYear]/[term] that already has a real room —
  /// the printable/exportable "Room Assignment Schedule", read fresh from
  /// class_sections/class_section_meetings rather than reusing
  /// [autoAssignRooms]'s transient result, so it also reflects rooms CFL
  /// supplied directly and stays correct if viewed again later without
  /// re-running the generator. Sorted by room, then chronologically
  /// (Monday through Saturday, then start time) — matches
  /// SectionScheduleRepository.fetchSectionSchedule's own day-ordering
  /// reasoning (`.order('day')` would sort alphabetically instead).
  Future<List<RoomAssignmentEntry>> fetchRoomAssignments({
    required String schoolYear,
    required String term,
  }) async {
    final classSectionRows = await _client
        .from('class_sections')
        .select(
          'id, sections ( name ), subjects ( code, title ), '
          'profiles ( first_name, last_name )',
        )
        .eq('school_year', schoolYear)
        .eq('term', term);
    final classSections = classSectionRows as List<dynamic>;
    if (classSections.isEmpty) return const [];

    final infoById = <
        String,
        ({
          String? subjectCode,
          String subjectTitle,
          String sectionName,
          String professorName,
        })>{
      for (final raw in classSections)
        (raw as Map<String, dynamic>)['id'] as String: (
          subjectCode: (raw['subjects'] as Map<String, dynamic>?)?['code'] as String?,
          subjectTitle:
              (raw['subjects'] as Map<String, dynamic>?)?['title'] as String? ??
                  '',
          sectionName:
              (raw['sections'] as Map<String, dynamic>?)?['name'] as String? ??
                  '',
          professorName: [
            (raw['profiles'] as Map<String, dynamic>?)?['first_name'] as String?,
            (raw['profiles'] as Map<String, dynamic>?)?['last_name'] as String?,
          ].where((s) => s != null && s.isNotEmpty).join(' '),
        ),
    };

    final meetingRows = await _client
        .from('class_section_meetings')
        .select('class_section_id, component, day, start_time, end_time, room')
        .inFilter('class_section_id', infoById.keys.toList());

    final entries = <RoomAssignmentEntry>[];
    for (final raw in meetingRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final room = row['room'] as String?;
      if (room == null || room == 'TBA') continue;
      final info = infoById[row['class_section_id'] as String];
      if (info == null) continue;
      entries.add(RoomAssignmentEntry(
        classSectionId: row['class_section_id'] as String,
        subjectCode: info.subjectCode,
        subjectTitle: info.subjectTitle,
        component: row['component'] as String?,
        sectionName: info.sectionName,
        professorName: info.professorName,
        room: room,
        day: row['day'] as String,
        startTime: (row['start_time'] as String).substring(0, 5),
        endTime: (row['end_time'] as String).substring(0, 5),
      ));
    }

    entries.sort((a, b) {
      final roomCompare = a.room.compareTo(b.room);
      if (roomCompare != 0) return roomCompare;
      final dayCompare =
          (_dayRank[a.day] ?? 99).compareTo(_dayRank[b.day] ?? 99);
      if (dayCompare != 0) return dayCompare;
      return a.startTime.compareTo(b.startTime);
    });

    return entries;
  }

  Future<RoomAssignmentSummary> autoAssignRooms({
    required String schoolYear,
    required String term,
  }) async {
    final classSectionRows = await _client
        .from('class_sections')
        .select('id, section_id, subjects ( code, title )')
        .eq('school_year', schoolYear)
        .eq('term', term);
    final classSections = classSectionRows as List<dynamic>;
    if (classSections.isEmpty) {
      return const RoomAssignmentSummary(
          assigned: 0, unassigned: [], totalConsidered: 0);
    }

    final sectionIdByClassSection = <String, String>{};
    // Lowercased "code title" per offering — checked against a restricted
    // room's keyword (e.g. the GYM's "PE") so only an actual PE subject can
    // land there. See RoomAssignmentAlgorithm's own doc comment.
    final subjectSearchTextByClassSection = <String, String>{};
    for (final raw in classSections) {
      final row = raw as Map<String, dynamic>;
      final classSectionId = row['id'] as String;
      sectionIdByClassSection[classSectionId] = row['section_id'] as String;
      final subject = row['subjects'] as Map<String, dynamic>?;
      subjectSearchTextByClassSection[classSectionId] =
          '${subject?['code'] ?? ''} ${subject?['title'] ?? ''}'
              .toLowerCase();
    }
    final classSectionIds = sectionIdByClassSection.keys.toList();

    final meetingRows = await _client
        .from('class_section_meetings')
        .select('id, class_section_id, component, day, start_time, end_time, room')
        .inFilter('class_section_id', classSectionIds);
    final allMeetings = meetingRows as List<dynamic>;

    final toAssign = <MeetingToAssign>[];
    final existingBookings = <Map<String, dynamic>>[];
    for (final raw in allMeetings) {
      final row = raw as Map<String, dynamic>;
      if ((row['room'] as String?) == 'TBA') {
        final classSectionId = row['class_section_id'] as String;
        toAssign.add(MeetingToAssign(
          meetingId: row['id'] as String,
          sectionId: sectionIdByClassSection[classSectionId]!,
          component: row['component'] as String?,
          day: row['day'] as String,
          startTime: row['start_time'] as String,
          endTime: row['end_time'] as String,
          subjectSearchText: subjectSearchTextByClassSection[classSectionId] ?? '',
        ));
      } else {
        existingBookings.add(row);
      }
    }

    if (toAssign.isEmpty) {
      return const RoomAssignmentSummary(
        assigned: 0,
        unassigned: [],
        totalConsidered: 0,
      );
    }

    final roomRows = await _client
        .from('rooms')
        .select('id, room_number, capacity, room_type, restricted_subject_keyword');
    final rooms = [
      for (final raw in roomRows as List<dynamic>)
        RoomRecord(
          id: (raw as Map<String, dynamic>)['id'] as String,
          roomNumber: raw['room_number'] as String,
          capacity: (raw['capacity'] as num).toInt(),
          roomType: raw['room_type'] as String,
          restrictedSubjectKeyword: raw['restricted_subject_keyword'] as String?,
        ),
    ];

    final headcounts = await _fetchSectionHeadcounts(
      sectionIdByClassSection.values.toSet(),
    );

    final alreadyBooked = _buildAlreadyBooked(existingBookings, rooms);

    final result = assignRooms(
      meetings: toAssign,
      rooms: rooms,
      sectionHeadcounts: headcounts,
      alreadyBooked: alreadyBooked,
    );

    for (final entry in result.assignments.entries) {
      await _client
          .from('class_section_meetings')
          .update({'room': entry.value.roomNumber}).eq('id', entry.key);
    }

    return RoomAssignmentSummary(
      assigned: result.assignments.length,
      unassigned: [
        for (final u in result.unassigned) u.reason,
      ],
      totalConsidered: toAssign.length,
    );
  }

  Future<Map<String, int>> _fetchSectionHeadcounts(Set<String> sectionIds) async {
    if (sectionIds.isEmpty) return const {};
    final rows = await _client
        .from('students')
        .select('section_id')
        .inFilter('section_id', sectionIds.toList());
    final counts = <String, int>{};
    for (final raw in rows as List<dynamic>) {
      final sectionId = (raw as Map<String, dynamic>)['section_id'] as String?;
      if (sectionId != null) counts[sectionId] = (counts[sectionId] ?? 0) + 1;
    }
    return counts;
  }

  /// Matches each already-booked meeting's free-text `room` string to a
  /// known `rooms.room_number` (case-insensitive, trimmed — the same
  /// looseness `resolveRoomCanonicalName`'s room_aliases table exists to
  /// paper over for the older per-string matching). A booked room that
  /// doesn't match any row in the new `rooms` inventory yet is silently
  /// excluded from the conflict check — it still physically occupies that
  /// slot, but there's no room id to key the conflict map on; populating
  /// `rooms` completely (the whole point of this table existing) is what
  /// closes that gap, not more string-matching cleverness here.
  Map<String, List<(int, int)>> _buildAlreadyBooked(
    List<Map<String, dynamic>> existingBookings,
    List<RoomRecord> rooms,
  ) {
    final roomIdByNumber = <String, String>{
      for (final r in rooms) r.roomNumber.trim().toLowerCase(): r.id,
    };
    final booked = <String, List<(int, int)>>{};
    for (final row in existingBookings) {
      final roomName = (row['room'] as String?)?.trim().toLowerCase();
      final roomId = roomName == null ? null : roomIdByNumber[roomName];
      if (roomId == null) continue;
      final start = minutesSinceMidnight(row['start_time'] as String);
      final end = minutesSinceMidnight(row['end_time'] as String);
      if (start == null || end == null) continue;
      final key = '$roomId|${row['day']}';
      (booked[key] ??= []).add((start, end));
    }
    return booked;
  }
}
