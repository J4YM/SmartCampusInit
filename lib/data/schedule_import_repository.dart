import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'schedule_import/schedule_import_row.dart';

const _uuid = Uuid();

// Both "New " and the trailing number are optional: confirmed real data
// spells the SAME not-yet-filled position as "New IT Faculty 1" (Room
// Schedule), plain "IT Faculty 1" (a different tab/source), AND plain
// "New IT Faculty" with no number at all (confirmed by the school: the
// numbering is inconsistent, not a real distinction between separate
// openings) — treating only the fully-numbered "New ... N" spelling as a
// placeholder made every other variant look like a brand-new real
// professor, creating a duplicate offering for what's really one open
// slot.
final _placeholderNamePattern =
    RegExp(r'^(New\s+)?.*(Faculty|Instructor)(\s*\d+)?$', caseSensitive: false);

/// True for placeholder professor names like "New IT Faculty 2",
/// "New GE Instructor 2", "IT Faculty 1" (no "New"), or plain
/// "New IT Faculty" (no number) — unfilled positions, per the CFL/Room
/// Schedule samples — these auto-resolve to a stub profile without
/// asking the Scheduling Officer to confirm, unlike any other unmatched
/// name.
bool isPlaceholderProfessorName(String name) =>
    _placeholderNamePattern.hasMatch(name.trim());

/// Strips an optional leading "New " and a trailing number so
/// "New IT Faculty 1", "IT Faculty 1", and plain "New IT Faculty" all
/// compare equal — confirmed as the same not-yet-filled position, just
/// spelled inconsistently by different source files/tabs (the school
/// confirmed the numbering itself isn't meaningful — there's one open
/// slot per title, not one per number). Returns null for a
/// non-placeholder name, so callers can tell "not a placeholder" apart
/// from "a placeholder with an empty canonical form" (which can't
/// actually happen, but null is the honest "doesn't apply" signal either
/// way).
String? canonicalPlaceholderName(String name) {
  final trimmed = name.trim();
  if (!isPlaceholderProfessorName(trimmed)) return null;
  return trimmed
      .replaceFirst(RegExp(r'^New\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*\d+$'), '')
      .trim()
      .toLowerCase();
}

/// Comparison key for subject titles: case, punctuation, spacing and a
/// trailing "(…)" qualifier are ignored, so "Discrete Structures 1" matches
/// the curriculum's "Discrete Structures 1 (Discrete Mathematics)" and
/// "P.E./PATHFIT 1: Movement Competency Training" matches "PE PATHFIT 1
/// Movement Competency Training". Same rule as the final step of
/// supabase/seed_curriculum_subjects.sql.
String normalizeSubjectTitle(String title) => title
    .replaceFirst(RegExp(r'\s*\(.*\)\s*$'), '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

// Shared with resolveSectionId, which needs the same (program, year level)
// split to resolve `sections.program`/`year_level`.
final _sectionNamePattern = RegExp(r'^([A-Za-z]+)\s*[- ]?(\d+)([A-Za-z])$');

/// True when [rawSectionName]'s embedded year level marks it as Senior
/// High School (grade 11/12, e.g. "ABM 12A", "STEM 11-B") rather than a
/// college section — this system is college-only in scope. Confirmed real
/// case: a Room Schedule file listed SHS sections alongside college ones,
/// and letting those through hit `sections_year_level_check` as a raw,
/// unreadable PostgrestException instead of being skipped cleanly.
bool isSeniorHighSection(String rawSectionName) {
  final match = _sectionNamePattern.firstMatch(rawSectionName.trim());
  final yearLevel = match != null ? int.tryParse(match.group(2)!) : null;
  return yearLevel != null && yearLevel >= 11;
}

const _nameHonorifics = {'mr', 'mrs', 'ms', 'dr', 'engr', 'prof', 'sir', 'madam'};

/// Reduces a "First [Middle] Last" name (optionally with an honorific
/// prefix) to just its first and last significant word, for matching two
/// spellings of the same person that only differ in a middle initial or
/// an honorific — confirmed as a real duplicate-professor cause: "Mr.
/// Jayson Villafuerte" and "Jayson V. Villafuerte" refer to the same
/// person but compare unequal as plain strings, each creating its own
/// profile/class_sections/meetings for what should be one offering.
/// Deliberately NOT a fix for reversed "Last, First" ordering (the
/// Classes+Professor list's own name order) — that's a separate,
/// documented cross-format limitation, not what this evidence showed.
String coreProfessorName(String fullName) {
  final tokens = fullName
      .replaceAll('.', ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_nameHonorifics.contains(t.toLowerCase()))
      .toList();
  if (tokens.isEmpty) return '';
  return '${tokens.first.toLowerCase()} ${tokens.last.toLowerCase()}';
}

/// Derives the school Microsoft address `firstname.lastname@baliuag.sti.edu.ph`
/// a professor will actually sign in with, from their imported full name —
/// so the stub profile's email matches their real login and
/// `handle_new_auth_user` (supabase/add_professor_email_and_linking.sql) can
/// adopt the stub on first sign-in. Honorifics and middle names/initials are
/// dropped (first + last word only), a "Last, First" ordering is swapped, and
/// anything outside a-z (hyphens, apostrophes, accents) is removed so the
/// result passes that trigger's `^[a-z]+(\.[a-z]+)+@...` staff pattern —
/// "Mr. Kar-El Paulino" -> `karel.paulino@baliuag.sti.edu.ph`.
///
/// Returns null when no real two-part name can be derived (placeholder
/// positions like "New IT Faculty 2", or a single-word name) — the caller
/// then falls back to the synthetic placeholder address.
String? professorEmailFor(String fullName) {
  if (isPlaceholderProfessorName(fullName)) return null;
  var name = fullName.trim();
  final comma = name.indexOf(',');
  if (comma != -1) {
    name = '${name.substring(comma + 1)} ${name.substring(0, comma)}';
  }
  final tokens = name
      .replaceAll('.', ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_nameHonorifics.contains(t.toLowerCase()))
      .map((t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length < 2) return null;
  return '${tokens.first}.${tokens.last}@baliuag.sti.edu.ph';
}

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
  /// normalized [title] against `subjects.title`. CFL/Room Schedule rows
  /// never carry a course code (only the Classes+Professor list does) —
  /// a subject seen for the first time via either of those two formats
  /// still auto-creates, the same as [resolveProfessorId] does for a
  /// professor with no matching profile: `subjects.code` is NOT NULL
  /// UNIQUE, so a generated placeholder code is used purely to satisfy
  /// that constraint. It's never looked up again — later imports of the
  /// same subject still match by title above.
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

    final normalizedTitle = normalizeSubjectTitle(title);
    final candidates = await _client.from('subjects').select('id, title');
    for (final row in candidates as List) {
      if (normalizeSubjectTitle(row['title'] as String) == normalizedTitle) {
        return row['id'] as String;
      }
    }

    final autoCode = 'AUTO-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final inserted = await _client
        .from('subjects')
        .insert({'code': autoCode, 'title': title})
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Matches [rawSectionName] against `sections.name`, normalized by
  /// stripping spaces and hyphens ("BSIT 2A" == "BSIT-2A"). Creates a
  /// new section if none matches, resolving its program via
  /// `program_aliases` when the name's letter prefix matches a known
  /// alias — falling back to the raw abbreviation itself (e.g. "BSTM")
  /// when no alias row exists yet, since `sections.program` is NOT NULL
  /// and `program_aliases` only ever has whatever a human has manually
  /// entered so far; an unmapped-but-real program shouldn't block the
  /// section from being created.
  Future<String> resolveSectionId(String rawSectionName) async {
    String normalize(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final target = normalize(rawSectionName);

    final sections = await _client.from('sections').select('id, name');
    for (final row in sections as List) {
      if (normalize(row['name'] as String) == target) return row['id'] as String;
    }

    final match = _sectionNamePattern.firstMatch(rawSectionName.trim());
    final programAbbrev = match?.group(1);
    final yearLevel = match != null ? int.tryParse(match.group(2)!) : null;

    String? canonicalProgram = programAbbrev;
    if (programAbbrev != null) {
      final alias = await _client
          .from('program_aliases')
          .select('canonical_program')
          .eq('alias', programAbbrev)
          .maybeSingle();
      canonicalProgram = alias?['canonical_program'] as String? ?? programAbbrev;
    }

    final inserted = await _client
        .from('sections')
        .insert({
          'name': rawSectionName,
          // Last-resort fallback if even programAbbrev extraction failed
          // (a section name that doesn't match the expected pattern at
          // all) — sections.program is NOT NULL, so this always needs a
          // value.
          'program': canonicalProgram ?? rawSectionName,
          'year_level': yearLevel,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Matches by [instructorId] (exact, from the Classes+Professor list)
  /// against `profiles.employee_id` when given, else by normalized
  /// full-name against `profiles.first_name`/`last_name` (from CFL/Room
  /// Schedule, neither of which carries an Instructor ID at all). Falls
  /// back to auto-creating a stub profile (`role: 'Teacher'`) for any
  /// unmatched [fullName], without asking the caller to confirm first —
  /// every format this resolves for is the school's own roster/schedule
  /// export, not free-typed input, so an unmatched name is overwhelmingly
  /// "professor new to this system," not a typo worth second-guessing.
  /// [isPlaceholderProfessorName] (e.g. "New IT Faculty 2", an admitted
  /// not-yet-filled position) gets `status: 'Placeholder'`; every other
  /// name gets `status: 'approved'` since they're a real, already-
  /// employed professor. [instructorId], when given, is persisted as
  /// `employee_id` so a later import of the same professor matches on
  /// the fast path above instead of re-creating a duplicate.
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
      final coreName = coreProfessorName(fullName);
      final placeholderName = canonicalPlaceholderName(fullName);
      final profiles = await _client
          .from('profiles')
          .select('id, first_name, last_name');
      String? coreNameMatchId;
      for (final row in profiles as List) {
        final combined =
            '${row['first_name']} ${row['last_name']}'.trim().toLowerCase();
        if (combined == normalized) return row['id'] as String;
        // "New IT Faculty 1" / "IT Faculty 1" name the same open
        // position — an equally precise identity signal as an exact
        // match, so this also returns immediately rather than only
        // being tried as a last-resort fallback like coreName below.
        if (placeholderName != null &&
            canonicalPlaceholderName(combined) == placeholderName) {
          return row['id'] as String;
        }
        // Fallback only — checked after every row's exact match, so an
        // exact match anywhere always wins over a looser one.
        if (coreNameMatchId == null &&
            coreName.isNotEmpty &&
            coreProfessorName(combined) == coreName) {
          coreNameMatchId = row['id'] as String;
        }
      }
      if (coreNameMatchId != null) return coreNameMatchId;

      // Not a plain `.from('profiles').insert(...)`: profiles.id has no
      // default and is tied 1:1 to an auth.users row throughout this
      // schema, which PostgREST can't write to directly — this RPC
      // (supabase/add_scheduling_officer_role.sql) creates both rows
      // together under security definer.
      final newId = await _client.rpc(
        'create_auto_professor_profile',
        params: {
          'p_employee_id': instructorId,
          'p_full_name': fullName,
          'p_is_placeholder': isPlaceholderProfessorName(fullName),
          'p_email': professorEmailFor(fullName),
        },
      );
      return newId as String;
    }

    throw StateError(
        'No professor found for instructorId=$instructorId and no '
        'fullName was supplied — this professor cannot be resolved.');
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
          // class_section_meetings.room is NOT NULL, but a real CFL row
          // can genuinely leave Room blank (confirmed against a real
          // upload — several GE subjects like "Euthenics 1" and "Rizal's
          // Life and Works" have no room at all, presumably TBA/online).
          // Rather than dropping the whole meeting over a missing room,
          // this records it as explicitly unassigned.
          'room': meeting.room ?? 'TBA',
          'units': meeting.units,
        },
        onConflict: 'class_section_id,component,day,sequence',
      );
    }
  }
}
