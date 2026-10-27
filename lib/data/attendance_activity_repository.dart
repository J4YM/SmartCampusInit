import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceActivityException implements Exception {
  AttendanceActivityException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What happened in one row of the attendance activity log.
enum ActivityKind {
  tapIn('Tapped in'),
  tapOut('Tapped out'),
  didNotTapOut('Did not tap out'),
  classPresent('Class: Present'),
  classLate('Class: Late'),
  classAbsent('Class: Absent'),
  classExcused('Class: Excused');

  const ActivityKind(this.label);
  final String label;

  /// A class attendance mark (taken by the professor) rather than a gate tap
  /// (or the nightly "did not tap out" record).
  bool get isClass => index >= ActivityKind.classPresent.index;

  static ActivityKind fromClassStatus(String? status) =>
      switch ((status ?? '').toLowerCase()) {
        'late' => ActivityKind.classLate,
        'absent' => ActivityKind.classAbsent,
        'excused' => ActivityKind.classExcused,
        _ => ActivityKind.classPresent,
      };
}

class AttendanceActivityEntry {
  const AttendanceActivityEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.studentId,
    required this.studentName,
    required this.studentNumber,
    required this.section,
    required this.course,
    this.detail,
  });

  final String id;
  final DateTime at;
  final ActivityKind kind;
  final String studentId;
  final String studentName;
  final String studentNumber;
  final String section;
  final String course;

  /// The reader's location for a tap, the subject for a class mark.
  final String? detail;

  String get label => kind.label;
}

/// The attendance activity log: every gate tap (`rfid_tap_events`) and every
/// class attendance mark (`attendance_records`), newest first, filterable by
/// student, section, course and date.
class AttendanceActivityRepository {
  AttendanceActivityRepository(this._client);

  final SupabaseClient _client;

  static const _studentEmbed =
      'students!inner ( student_number, course, profiles ( first_name, last_name ), sections ( name ) )';

  /// Up to [limit] entries from EACH source, merged newest first.
  ///
  /// [sectionId] matches a tap's student's home section and a class mark's own
  /// section. [from]/[to] are calendar days, both inclusive. [studentQuery]
  /// matches a student number prefix or part of a name; a query that matches no
  /// one returns an empty log (not everyone's).
  Future<List<AttendanceActivityEntry>> fetch({
    String? studentQuery,
    String? sectionId,
    String? course,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    List<String>? studentIds;
    final q = (studentQuery ?? '').trim().replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (q.isNotEmpty) {
      studentIds = await _findStudentIds(q);
      if (studentIds.isEmpty) return const [];
    }

    final taps = await _source(() async {
      var query = _client.from('rfid_tap_events').select(
          'id, tapped_at, tap_direction, student_id, rfid_readers ( label, location ), $_studentEmbed');
      if (studentIds != null) query = query.inFilter('student_id', studentIds);
      if (sectionId != null) query = query.eq('students.section_id', sectionId);
      if (course != null) query = query.eq('students.course', course);
      if (from != null) {
        query = query.gte(
            'tapped_at', DateTime(from.year, from.month, from.day).toUtc().toIso8601String());
      }
      if (to != null) {
        // Everything up to the end of the last day.
        query = query.lt('tapped_at',
            DateTime(to.year, to.month, to.day + 1).toUtc().toIso8601String());
      }
      return query.order('tapped_at', ascending: false).limit(limit);
    });

    final missed = await _source(() async {
      var query = _client
          .from('missed_tap_outs')
          .select('student_id, school_day, created_at, $_studentEmbed');
      if (studentIds != null) query = query.inFilter('student_id', studentIds);
      if (sectionId != null) query = query.eq('students.section_id', sectionId);
      if (course != null) query = query.eq('students.course', course);
      if (from != null) query = query.gte('school_day', _day(from));
      if (to != null) query = query.lte('school_day', _day(to));
      return query.order('created_at', ascending: false).limit(limit);
    });

    final classes = await _source(() async {
      var query = _client.from('attendance_records').select(
          'id, status, session_date, recorded_at, student_id, class_sections ( subjects ( title ) ), $_studentEmbed');
      if (studentIds != null) query = query.inFilter('student_id', studentIds);
      if (sectionId != null) query = query.eq('section_id', sectionId);
      if (course != null) query = query.eq('students.course', course);
      if (from != null) query = query.gte('session_date', _day(from));
      if (to != null) query = query.lte('session_date', _day(to));
      return query.order('recorded_at', ascending: false).limit(limit);
    });

    final entries = <AttendanceActivityEntry>[
      for (final r in taps) _tap(r),
      for (final r in missed) _missed(r),
      for (final r in classes) _class(r),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

  /// Runs one source query; a table that does not exist yet reads as empty so
  /// the other source still shows.
  Future<List<Map<String, dynamic>>> _source(
      Future<dynamic> Function() run) async {
    try {
      final rows = await run();
      return [for (final r in rows as List<dynamic>) r as Map<String, dynamic>];
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205' || e.code == '404') {
        return const [];
      }
      throw AttendanceActivityException(e.message);
    }
  }

  Future<List<String>> _findStudentIds(String q) async {
    try {
      final byNumber = await _client
          .from('students')
          .select('id')
          .ilike('student_number', '$q%')
          .limit(50);
      final byName = await _client
          .from('profiles')
          .select('id')
          .or('first_name.ilike.%$q%,last_name.ilike.%$q%')
          .limit(50);
      return {
        for (final r in [...(byNumber as List<dynamic>), ...(byName as List<dynamic>)])
          (r as Map<String, dynamic>)['id'] as String,
      }.toList();
    } on PostgrestException catch (e) {
      throw AttendanceActivityException(e.message);
    }
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _name(Map<String, dynamic>? profile) =>
      '${(profile?['first_name'] as String? ?? '').trim()} '
              '${(profile?['last_name'] as String? ?? '').trim()}'
          .trim();

  AttendanceActivityEntry _tap(Map<String, dynamic> r) {
    final s = r['students'] as Map<String, dynamic>?;
    final reader = r['rfid_readers'] as Map<String, dynamic>?;
    final location = (reader?['location'] as String?)?.trim() ?? '';
    return AttendanceActivityEntry(
      id: r['id'] as String,
      at: DateTime.parse(r['tapped_at'] as String).toLocal(),
      kind: r['tap_direction'] == 'out' ? ActivityKind.tapOut : ActivityKind.tapIn,
      studentId: r['student_id'] as String? ?? '',
      studentName: _name(s?['profiles'] as Map<String, dynamic>?),
      studentNumber: s?['student_number'] as String? ?? '',
      section: (s?['sections'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      course: s?['course'] as String? ?? '',
      detail: location.isNotEmpty ? location : reader?['label'] as String?,
    );
  }

  /// A student who tapped in and never out on a school day
  /// (`missed_tap_outs`, supabase/replace_auto_tap_out.sql).
  AttendanceActivityEntry _missed(Map<String, dynamic> r) {
    final s = r['students'] as Map<String, dynamic>?;
    final day = r['school_day'] as String? ?? '';
    return AttendanceActivityEntry(
      id: 'missed-${r['student_id']}-$day',
      at: DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.tryParse(day) ??
          DateTime.now(),
      kind: ActivityKind.didNotTapOut,
      studentId: r['student_id'] as String? ?? '',
      studentName: _name(s?['profiles'] as Map<String, dynamic>?),
      studentNumber: s?['student_number'] as String? ?? '',
      section: (s?['sections'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      course: s?['course'] as String? ?? '',
      detail: null,
    );
  }

  AttendanceActivityEntry _class(Map<String, dynamic> r) {
    final s = r['students'] as Map<String, dynamic>?;
    final subject = ((r['class_sections'] as Map<String, dynamic>?)?['subjects']
        as Map<String, dynamic>?)?['title'] as String?;
    final at = DateTime.tryParse(r['recorded_at'] as String? ?? '') ??
        DateTime.tryParse(r['session_date'] as String? ?? '') ??
        DateTime.now();
    return AttendanceActivityEntry(
      id: r['id'] as String,
      at: at.toLocal(),
      kind: ActivityKind.fromClassStatus(r['status'] as String?),
      studentId: r['student_id'] as String? ?? '',
      studentName: _name(s?['profiles'] as Map<String, dynamic>?),
      studentNumber: s?['student_number'] as String? ?? '',
      section: (s?['sections'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      course: s?['course'] as String? ?? '',
      detail: subject,
    );
  }
}
