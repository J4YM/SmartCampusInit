import 'package:supabase_flutter/supabase_flutter.dart';

import 'schedule_import/schedule_import_row.dart';

final _placeholderNamePattern =
    RegExp(r'^New .*(Faculty|Instructor)\s*\d+$', caseSensitive: false);

/// True for placeholder professor names like "New IT Faculty 2" or
/// "New GE Instructor 2" (unfilled positions, per the CFL/Room Schedule
/// samples) — these auto-resolve to a stub profile without asking the
/// Scheduling Officer to confirm, unlike any other unmatched name.
bool isPlaceholderProfessorName(String name) =>
    _placeholderNamePattern.hasMatch(name.trim());

/// Owns every Supabase read/write this feature needs: resolving parsed
/// [ScheduleImportRow]s against existing subjects/sections/profiles/
/// room_aliases/program_aliases, and committing the reconciled result
/// into class_sections/class_section_meetings. The parsing and conflict
/// detection this depends on (schedule_import/) has no Supabase
/// dependency and is unit-tested separately.
class ScheduleImportRepository {
  ScheduleImportRepository(this._client);
  final SupabaseClient _client;

  /// Matches by [code] (exact) when given, else by case/whitespace-
  /// normalized [title] against `subjects.title`. Throws
  /// [StateError] with a message identifying the missing code if no
  /// match is found and [code] is null — callers sourced from CFL/Room
  /// Schedule (no code available) must have already collected a code
  /// from the Scheduling Officer during review before calling this.
  Future<String> resolveSubjectId({required String title, String? code}) async {
    if (code != null) {
      final existing = await _client
          .from('subjects')
          .select('id')
          .eq('code', code)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;
      final inserted = await _client
          .from('subjects')
          .insert({'code': code, 'title': title})
          .select('id')
          .single();
      return inserted['id'] as String;
    }

    final normalizedTitle = title.trim().toLowerCase();
    final candidates = await _client.from('subjects').select('id, title');
    for (final row in candidates as List) {
      if ((row['title'] as String).trim().toLowerCase() == normalizedTitle) {
        return row['id'] as String;
      }
    }
    throw StateError(
        'No subject found for "$title" and no code was supplied — '
        'the Scheduling Officer must provide a course code for this new '
        'subject before it can be created.');
  }

  /// Matches [rawSectionName] against `sections.name`, normalized by
  /// stripping spaces and hyphens ("BSIT 2A" == "BSIT-2A"). Creates a
  /// new section if none matches, resolving its program via
  /// `program_aliases` when the name's letter prefix matches a known
  /// alias.
  Future<String> resolveSectionId(String rawSectionName) async {
    String normalize(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final target = normalize(rawSectionName);

    final sections = await _client.from('sections').select('id, name');
    for (final row in sections as List) {
      if (normalize(row['name'] as String) == target) return row['id'] as String;
    }

    final match = RegExp(r'^([A-Za-z]+)\s*[- ]?(\d+)([A-Za-z])$')
        .firstMatch(rawSectionName.trim());
    final programAbbrev = match?.group(1);
    final yearLevel = match != null ? int.tryParse(match.group(2)!) : null;

    String? canonicalProgram;
    if (programAbbrev != null) {
      final alias = await _client
          .from('program_aliases')
          .select('canonical_program')
          .eq('alias', programAbbrev)
          .maybeSingle();
      canonicalProgram = alias?['canonical_program'] as String?;
    }

    final inserted = await _client
        .from('sections')
        .insert({
          'name': rawSectionName,
          'program': canonicalProgram,
          'year_level': yearLevel,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Matches by [instructorId] (exact, from the Classes+Professor list)
  /// against `profiles.employee_id` when given, else by normalized
  /// full-name against `profiles.first_name`/`last_name` (from CFL/Room
  /// Schedule). A placeholder name ([isPlaceholderProfessorName])
  /// auto-creates a stub profile (`role: 'Teacher'`, `status:
  /// 'Placeholder'`) without requiring the caller to confirm first.
  Future<String> resolveProfessorId({String? instructorId, String? fullName}) async {
    if (instructorId != null) {
      final existing = await _client
          .from('profiles')
          .select('id')
          .eq('employee_id', instructorId)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;
    }

    if (fullName != null) {
      final normalized = fullName.trim().toLowerCase();
      final profiles = await _client
          .from('profiles')
          .select('id, first_name, last_name');
      for (final row in profiles as List) {
        final combined =
            '${row['first_name']} ${row['last_name']}'.trim().toLowerCase();
        if (combined == normalized) return row['id'] as String;
      }

      if (isPlaceholderProfessorName(fullName)) {
        final inserted = await _client
            .from('profiles')
            .insert({
              'first_name': fullName,
              'last_name': '',
              'role': 'Teacher',
              'status': 'Placeholder',
            })
            .select('id')
            .single();
        return inserted['id'] as String;
      }
    }

    throw StateError(
        'No professor found for instructorId=$instructorId, '
        'fullName=$fullName, and it is not a recognized placeholder name '
        '— the Scheduling Officer must confirm create-new-vs-pick-existing '
        'before this professor can be resolved.');
  }

  /// Resolves [rawRoomName] to its canonical name via `room_aliases`.
  /// A room with no existing alias returns [rawRoomName] itself as its
  /// own canonical name (the "this is a new room" review choice) — it is
  /// the caller's responsibility to have already written that decision
  /// as a `room_aliases` row (via the review screen, not this method)
  /// before calling this for a name that should now resolve.
  Future<String> resolveRoomCanonicalName(String rawRoomName) async {
    final alias = await _client
        .from('room_aliases')
        .select('canonical_room')
        .eq('alias', rawRoomName)
        .maybeSingle();
    return (alias?['canonical_room'] as String?) ?? rawRoomName;
  }

  /// Cross-checks the Registrar's roster against what was actually
  /// scheduled (Component 3's roster cross-check). Returns one
  /// human-readable description per mismatch, in both directions: a
  /// roster pairing never scheduled anywhere, and a scheduled pairing
  /// not present in the roster.
  Future<List<String>> findRosterMismatches(
    List<ScheduleImportRow> roster,
    List<ScheduleImportRow> scheduledMeetings,
  ) async {
    String pairingKey(ScheduleImportRow row) =>
        '${row.subjectTitle.trim().toLowerCase()}::${(row.professorName ?? '').trim().toLowerCase()}';

    final rosterPairings = roster.map(pairingKey).toSet();
    final scheduledPairings = scheduledMeetings.map(pairingKey).toSet();

    final mismatches = <String>[];
    for (final row in roster) {
      if (!scheduledPairings.contains(pairingKey(row))) {
        mismatches.add(
            'Roster lists ${row.professorName} teaching ${row.subjectTitle}, '
            'but no CFL/Room Schedule meeting was found for that pairing.');
      }
    }
    for (final row in scheduledMeetings) {
      if (!rosterPairings.contains(pairingKey(row))) {
        mismatches.add(
            '${row.professorName} is scheduled to teach ${row.subjectTitle}, '
            'but that pairing is not in the uploaded roster.');
      }
    }
    return mismatches;
  }

  /// Upserts every meeting in [meetings] under [classSectionId]. Keyed
  /// on (class_section_id, component, day, sequence) — sequence is each
  /// meeting's position among same-component-same-day meetings in
  /// [meetings]'s own order, so a correction that only changes a time
  /// range still updates the same row instead of duplicating it (see
  /// spec Component 5). Requires
  /// supabase/add_schedule_import_commit_support.sql's `sequence` column
  /// and unique index to already exist.
  Future<void> commitMeetings({
    required String classSectionId,
    required List<ScheduleImportRow> meetings,
  }) async {
    final sequenceCounters = <String, int>{};
    for (final meeting in meetings) {
      final componentKey = meeting.component?.name ?? 'null';
      final groupKey = '$componentKey::${meeting.day}';
      final sequence = sequenceCounters.update(
        groupKey,
        (n) => n + 1,
        ifAbsent: () => 0,
      );

      await _client.from('class_section_meetings').upsert(
        {
          'class_section_id': classSectionId,
          'component': meeting.component?.name.replaceFirstMapped(
              RegExp('^.'), (m) => m.group(0)!.toUpperCase()),
          'day': meeting.day,
          'sequence': sequence,
          'start_time': meeting.startTime,
          'end_time': meeting.endTime,
          'room': meeting.room,
        },
        onConflict: 'class_section_id,component,day,sequence',
      );
    }
  }
}
