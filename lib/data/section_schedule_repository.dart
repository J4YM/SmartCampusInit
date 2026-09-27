import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of the generated per-section Class Schedule — either a real
/// meeting (component/day/start/end/room all set) or, when a class_
/// sections offering has no meetings committed yet (a subject assigned to
/// the section/professor but not yet scheduled — confirmed against the
/// school's own "SCHEDULE OF CLASSES" template, which still lists such a
/// subject with a blank day/time/room rather than omitting it), a
/// placeholder row with those fields null. [classSectionId] groups rows
/// that belong to the same offering back together (a subject with both a
/// Lecture and a Laboratory component produces multiple rows sharing one
/// classSectionId) — mirrors ProfessorScheduleEntryModel's shape
/// (lib/data/professor_repository.dart), which already solved the same
/// "one row per meeting, not per offering" problem for the Professor's
/// own "My Schedule" view.
class SectionScheduleEntryModel {
  const SectionScheduleEntryModel({
    required this.classSectionId,
    this.subjectCode,
    required this.subjectTitle,
    required this.professorName,
    this.component,
    this.day,
    this.startTime,
    this.endTime,
    this.room,
    this.units,
    this.schoolYear,
    this.term,
  });

  final String classSectionId;

  /// Null when the subject has no course code on file (e.g. it was only
  /// ever seen through a CFL/Room Schedule import, which never carries
  /// one — see ScheduleImportRow's own doc comment).
  final String? subjectCode;

  final String subjectTitle;
  final String professorName;

  /// 'Lecture', 'Laboratory', or null when the subject has no split (or
  /// no meeting at all yet).
  final String? component;

  /// One of 'M', 'T', 'W', 'TH', 'F', 'S'. Null when this offering has no
  /// meeting committed yet.
  final String? day;

  /// 24-hour "HH:MM". Null when this offering has no meeting committed
  /// yet.
  final String? startTime;
  final String? endTime;

  /// Null when this offering has no meeting committed yet.
  final String? room;

  /// Course unit count for this specific component, when the source file
  /// carried one (only CFL rows do — see parseFacultyLoading).
  final double? units;

  final String? schoolYear;
  final String? term;
}

/// A `sections` row, for the section picker every "generate the Class
/// Schedule" view (Registrar, Scheduling Officer) starts from. Named
/// distinctly from registrar_module's own `SectionOption` (a different
/// picker, for the manual "Add Class Schedule" form) since callers often
/// need both in the same file.
class SectionScheduleOption {
  const SectionScheduleOption({required this.id, required this.name});
  final String id;
  final String name;
}

/// Reads the generated, per-section Class Schedule — every subject a
/// section takes, each split into its own Lecture/Laboratory meetings —
/// from class_sections/class_section_meetings, the same tables the
/// Registrar's Classes+Professor list and the Scheduling Officer's CFL/
/// Room Schedule uploads (ScheduleImportRunner) commit into. Deliberately
/// separate from RegistrarRepository: this is a read-only view used by
/// several different dashboards (Registrar, Scheduling Officer, and —
/// filtered to one student's own section — the Student/Parent portals),
/// not Registrar-specific.
class SectionScheduleRepository {
  SectionScheduleRepository(this._client);
  final SupabaseClient _client;

  Future<List<SectionScheduleOption>> fetchSectionOptions() async {
    final rows = await _client.from('sections').select('id, name').order('name');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return SectionScheduleOption(id: row['id'] as String, name: row['name'] as String);
    }).toList();
  }

  static const _dayRank = {'M': 0, 'T': 1, 'W': 2, 'TH': 3, 'F': 4, 'S': 5};

  /// Every offering for [sectionId] — one or more rows per class_sections
  /// id (see [SectionScheduleEntryModel]'s own doc comment for why an
  /// offering with no meetings still produces exactly one row). Meetings
  /// are sorted chronologically (Monday through Saturday, then by start
  /// time) — `.order('day')` on the query would sort alphabetically
  /// (F, M, S, T, TH, W), not calendar order, so the sort happens
  /// client-side against [_dayRank] instead.
  Future<List<SectionScheduleEntryModel>> fetchSectionSchedule({
    required String sectionId,
  }) async {
    final classSections = await _client
        .from('class_sections')
        .select(
          'id, school_year, term, subjects ( code, title ), '
          'profiles ( first_name, last_name )',
        )
        .eq('section_id', sectionId);

    final sectionsList = classSections as List<dynamic>;
    if (sectionsList.isEmpty) return const [];

    final classSectionIds = sectionsList
        .map((e) => (e as Map<String, dynamic>)['id'] as String)
        .toList();

    final infoById = <
        String,
        ({
          String? subjectCode,
          String subjectTitle,
          String professorName,
          String? schoolYear,
          String? term,
        })>{
      for (final raw in sectionsList)
        (raw as Map<String, dynamic>)['id'] as String: (
          subjectCode: (raw['subjects'] as Map<String, dynamic>?)?['code'] as String?,
          subjectTitle:
              (raw['subjects'] as Map<String, dynamic>?)?['title'] as String? ??
                  '',
          professorName: [
            (raw['profiles'] as Map<String, dynamic>?)?['first_name'] as String?,
            (raw['profiles'] as Map<String, dynamic>?)?['last_name'] as String?,
          ].where((s) => s != null && s.isNotEmpty).join(' '),
          schoolYear: raw['school_year'] as String?,
          term: raw['term'] as String?,
        ),
    };

    final meetings = await _client
        .from('class_section_meetings')
        .select('id, class_section_id, component, day, start_time, end_time, room, units')
        .inFilter('class_section_id', classSectionIds);

    final meetingsByClassSection = <String, List<Map<String, dynamic>>>{};
    for (final raw in meetings as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      (meetingsByClassSection[row['class_section_id'] as String] ??= [])
          .add(row);
    }

    final entries = <SectionScheduleEntryModel>[];
    for (final classSectionId in classSectionIds) {
      final info = infoById[classSectionId]!;
      final rowsForSection = meetingsByClassSection[classSectionId] ?? const [];

      if (rowsForSection.isEmpty) {
        entries.add(SectionScheduleEntryModel(
          classSectionId: classSectionId,
          subjectCode: info.subjectCode,
          subjectTitle: info.subjectTitle,
          professorName: info.professorName,
          schoolYear: info.schoolYear,
          term: info.term,
        ));
        continue;
      }

      rowsForSection.sort((a, b) {
        final dayCompare = (_dayRank[a['day']] ?? 99)
            .compareTo(_dayRank[b['day']] ?? 99);
        if (dayCompare != 0) return dayCompare;
        return (a['start_time'] as String).compareTo(b['start_time'] as String);
      });

      for (final row in rowsForSection) {
        entries.add(SectionScheduleEntryModel(
          classSectionId: classSectionId,
          subjectCode: info.subjectCode,
          subjectTitle: info.subjectTitle,
          professorName: info.professorName,
          component: row['component'] as String?,
          day: row['day'] as String?,
          startTime: (row['start_time'] as String).substring(0, 5),
          endTime: (row['end_time'] as String).substring(0, 5),
          room: row['room'] as String?,
          units: (row['units'] as num?)?.toDouble(),
          schoolYear: info.schoolYear,
          term: info.term,
        ));
      }
    }
    return entries;
  }
}
