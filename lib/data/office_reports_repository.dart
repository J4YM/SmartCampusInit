import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'violation_notice_repository.dart' show ordinalLabel;

/// Report types offered to each office (the Reports page lists these).
const guidanceReportTypes = <String>[
  'Good Moral Requests',
  'Parent Meeting Log',
  'Student Behavioral Summary',
  'Attendance by Teacher and Subject',
];

const disciplineReportTypes = <String>[
  'Student Violation Summary',
  'Offense Tier Counts',
  'Suspensions',
  'Parent Acknowledgment Notices',
  'Student Behavioral Summary',
];

const adminReportTypes = <String>[
  'Attendance Summary Report',
  'Attendance by Teacher and Subject',
  'Student Violation Summary',
  'Offense Tier Counts',
  'Suspensions',
  'Parent Acknowledgment Notices',
  'Good Moral Requests',
  'Parent Meeting Log',
  'Student Behavioral Summary',
  'ML Dropout Risk Analysis',
];

/// The Guidance Office and Discipline Office reports. Every report lists its
/// rows most recent first (the aggregated ones by their latest activity) and
/// returns a real, honestly empty result when nothing matches or when a
/// migration has not been run yet.
class OfficeReportsRepository {
  OfficeReportsRepository(this._client);

  final SupabaseClient _client;

  static const _studentEmbed = '''
student_number,
course,
profiles ( first_name, last_name ),
sections ( name )
''';

  static const _pageSize = 1000;

  // -------------------------------------------------------------------------
  // helpers
  // -------------------------------------------------------------------------

  static String _name(Map<String, dynamic>? profile) {
    final first = (profile?['first_name'] as String? ?? '').trim();
    final last = (profile?['last_name'] as String? ?? '').trim();
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Unknown student' : name;
  }

  static bool _matchesCourse(Map<String, dynamic>? student, String? course) {
    if (course == null || course == 'All Departments') return true;
    return student?['course'] == course;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _dayOrDash(DateTime? d) => d == null ? '--' : _day(d);

  static DateTime? _parseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  /// Newest first by [field] (a date or timestamp string); rows without one last.
  static void _sortNewestFirst(List<Map<String, dynamic>> rows, String field) {
    rows.sort((a, b) {
      final x = _parseDate(a[field] as String?);
      final y = _parseDate(b[field] as String?);
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
  }

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  static String _studentName(Map<String, dynamic>? student) =>
      _name(student?['profiles'] as Map<String, dynamic>?);

  static String _section(Map<String, dynamic>? student) =>
      (student?['sections'] as Map<String, dynamic>?)?['name'] as String? ??
      '--';

  /// Runs a report. A missing table or column (migration not run yet) becomes
  /// an explanatory empty result instead of an error.
  Future<ReportPreviewDataModel> _report({
    required List<String> columns,
    required String emptyMessage,
    required Future<List<Map<String, dynamic>>> Function() build,
  }) async {
    try {
      final rows = await build();
      return ReportPreviewDataModel(
        columns: columns,
        previewRows: rows,
        totalRows: rows.length,
        isPreviewGenerated: true,
        emptyMessage: rows.isEmpty ? emptyMessage : null,
      );
    } on PostgrestException catch (e) {
      final missing = e.code == '42703' ||
          e.code == '42P01' ||
          e.code == 'PGRST204' ||
          e.code == 'PGRST205' ||
          e.message.contains('does not exist');
      return ReportPreviewDataModel(
        columns: columns,
        previewRows: const [],
        totalRows: 0,
        isPreviewGenerated: true,
        emptyMessage: missing
            ? 'This report needs a database update. Run '
                'supabase/add_defense_revisions.sql in the Supabase SQL '
                'Editor, then generate it again. (${e.message})'
            : 'Could not build this report: ${e.message}',
      );
    }
  }

  /// Every row of a query, [_pageSize] at a time (PostgREST caps one request).
  Future<List<Map<String, dynamic>>> _all(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function() query,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (var from = 0; from < 50 * _pageSize; from += _pageSize) {
      final page = await query().range(from, from + _pageSize - 1);
      out.addAll([for (final r in page) r]);
      if (page.length < _pageSize) break;
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Discipline Office
  // -------------------------------------------------------------------------

  /// Per student: how many Minor and Major violations, and the highest
  /// offense tier reached (1st, 2nd, 3rd...), most recent offender first.
  Future<ReportPreviewDataModel> fetchOffenseTierCounts({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Minor',
      'Major',
      'Total',
      'Highest Tier',
      'Latest Violation',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No violations recorded for this date range/department.',
      build: () async {
        final rows = await _all(() {
          var q = _client
              .from('student_violations')
              .select('student_id, created_at, students ( $_studentEmbed ), '
                  'handbook_offenses ( category )')
              .filter('archived_at', 'is', null);
          if (start != null) {
            q = q.gte('created_at', start.toUtc().toIso8601String());
          }
          if (end != null) {
            q = q.lte('created_at', _endOfDay(end).toUtc().toIso8601String());
          }
          return q.order('created_at', ascending: false);
        });

        final byStudent = <String, Map<String, dynamic>>{};
        for (final r in rows) {
          final student = r['students'] as Map<String, dynamic>?;
          if (!_matchesCourse(student, course)) continue;
          final id = r['student_id'] as String? ?? _studentName(student);
          final category =
              (r['handbook_offenses'] as Map<String, dynamic>?)?['category']
                  as String?;
          final created = _parseDate(r['created_at'] as String?)?.toLocal();
          final entry = byStudent.putIfAbsent(
              id,
              () => {
                    'student': student,
                    'minor': 0,
                    'major': 0,
                    'total': 0,
                    'latest': created,
                  });
          entry['total'] = (entry['total'] as int) + 1;
          if (category != null) {
            final key = category.toLowerCase().startsWith('major')
                ? 'major'
                : 'minor';
            entry[key] = (entry[key] as int) + 1;
          }
          final latest = entry['latest'] as DateTime?;
          if (created != null && (latest == null || created.isAfter(latest))) {
            entry['latest'] = created;
          }
        }

        final entries = byStudent.values.toList()
          ..sort((a, b) {
            final x = a['latest'] as DateTime?;
            final y = b['latest'] as DateTime?;
            if (x == null) return 1;
            if (y == null) return -1;
            return y.compareTo(x);
          });
        return [
          for (final e in entries)
            () {
              final minor = e['minor'] as int;
              final major = e['major'] as int;
              final highest = minor > major ? minor : major;
              final student = e['student'] as Map<String, dynamic>?;
              return <String, dynamic>{
                'Student Name': _studentName(student),
                'Student Number': student?['student_number'] ?? '--',
                'Section': _section(student),
                'Minor': minor,
                'Major': major,
                'Total': e['total'],
                'Highest Tier':
                    highest == 0 ? '--' : '${ordinalLabel(highest)} Offense',
                'Latest Violation': _dayOrDash(e['latest'] as DateTime?),
              };
            }(),
        ];
      },
    );
  }

  /// Every suspension (upcoming, active and completed), latest start first.
  Future<ReportPreviewDataModel> fetchSuspensions({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Start Date',
      'End Date',
      'Status',
      'Details',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No suspensions recorded for this date range/department.',
      build: () async {
        final rows = await _all(() {
          var q = _client
              .from('sanctions')
              .select('sanction_type, effective_on, ends_on, status, '
                  'description, students ( $_studentEmbed )')
              .eq('sanction_type', 'suspension');
          if (start != null) q = q.gte('effective_on', _day(start));
          if (end != null) q = q.lte('effective_on', _day(end));
          return q.order('effective_on', ascending: false);
        });
        _sortNewestFirst(rows, 'effective_on');

        final today = DateTime.now();
        final todayDay = DateTime(today.year, today.month, today.day);
        final out = <Map<String, dynamic>>[];
        for (final r in rows) {
          final student = r['students'] as Map<String, dynamic>?;
          if (!_matchesCourse(student, course)) continue;
          final from = _parseDate(r['effective_on'] as String?);
          final to = _parseDate(r['ends_on'] as String?);
          final String status;
          if (r['status'] == 'Completed' ||
              (to != null && to.isBefore(todayDay))) {
            status = 'Completed';
          } else if (from != null && from.isAfter(todayDay)) {
            status = 'Upcoming';
          } else {
            status = 'Active';
          }
          out.add({
            'Student Name': _studentName(student),
            'Student Number': student?['student_number'] ?? '--',
            'Section': _section(student),
            'Start Date': _dayOrDash(from),
            'End Date': to == null ? 'Open-ended' : _day(to),
            'Status': status,
            'Details': r['description'] as String? ?? '--',
          });
        }
        return out;
      },
    );
  }

  /// Which parents have returned the signed violation notice.
  Future<ReportPreviewDataModel> fetchParentAcknowledgments({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Violation',
      'Sanction',
      'Issued',
      'Acknowledged',
      'Parent / Guardian',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No sanctions recorded for this date range/department.',
      build: () async {
        final rows = await _all(() {
          var q = _client.from('sanctions').select(
              'decided_at, sanction_type, description, parent_ack_at, '
              'parent_ack_name, students ( $_studentEmbed ), '
              'student_violations ( handbook_offenses ( description ) )');
          if (start != null) {
            q = q.gte('decided_at', start.toUtc().toIso8601String());
          }
          if (end != null) {
            q = q.lte('decided_at', _endOfDay(end).toUtc().toIso8601String());
          }
          return q.order('decided_at', ascending: false);
        });
        _sortNewestFirst(rows, 'decided_at');

        final out = <Map<String, dynamic>>[];
        for (final r in rows) {
          final student = r['students'] as Map<String, dynamic>?;
          if (!_matchesCourse(student, course)) continue;
          final violation = r['student_violations'] as Map<String, dynamic>?;
          final offense = violation?['handbook_offenses'] as Map<String, dynamic>?;
          final ack = _parseDate(r['parent_ack_at'] as String?)?.toLocal();
          out.add({
            'Student Name': _studentName(student),
            'Student Number': student?['student_number'] ?? '--',
            'Section': _section(student),
            'Violation': offense?['description'] as String? ?? '--',
            'Sanction': r['description'] as String? ?? '--',
            'Issued':
                _dayOrDash(_parseDate(r['decided_at'] as String?)?.toLocal()),
            'Acknowledged': ack == null ? 'Not yet' : _day(ack),
            'Parent / Guardian': r['parent_ack_name'] as String? ?? '--',
          });
        }
        return out;
      },
    );
  }

  // -------------------------------------------------------------------------
  // Guidance Office
  // -------------------------------------------------------------------------

  /// Good Moral Certificate requests, newest first.
  Future<ReportPreviewDataModel> fetchGoodMoralRequests({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Document',
      'Purpose',
      'Requested',
      'Status',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No Good Moral requests for this date range/department.',
      build: () async {
        final rows = await _all(() {
          var q = _client.from('good_moral_requests').select(
              'document_type, purpose, request_date, status, '
              'students ( $_studentEmbed )');
          if (start != null) {
            q = q.gte('request_date', start.toUtc().toIso8601String());
          }
          if (end != null) {
            q = q.lte('request_date', _endOfDay(end).toUtc().toIso8601String());
          }
          return q.order('request_date', ascending: false);
        });
        _sortNewestFirst(rows, 'request_date');

        return [
          for (final r in rows)
            if (_matchesCourse(r['students'] as Map<String, dynamic>?, course))
              {
                'Student Name':
                    _studentName(r['students'] as Map<String, dynamic>?),
                'Student Number':
                    (r['students'] as Map<String, dynamic>?)?['student_number'] ??
                        '--',
                'Section': _section(r['students'] as Map<String, dynamic>?),
                'Document': r['document_type'] as String? ?? '--',
                'Purpose': r['purpose'] as String? ?? '--',
                'Requested': _dayOrDash(
                    _parseDate(r['request_date'] as String?)?.toLocal()),
                'Status': r['status'] as String? ?? 'Pending',
              },
        ];
      },
    );
  }

  /// Meetings with parents (disciplinary and guidance conferences), with the
  /// confirmation that the parent attended and the meeting summary.
  Future<ReportPreviewDataModel> fetchParentMeetingLog({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Scheduled',
      'Location',
      'Status',
      'Parent Attended',
      'Summary',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No parent meetings for this date range/department.',
      build: () async {
        final rows = await _all(() {
          var q = _client
              .from('guidance_meetings')
              .select('scheduled_at, location, status, invitee, '
                  'parent_attended, summary, students ( $_studentEmbed )')
              .inFilter('invitee', ['parent', 'both']);
          if (start != null) {
            q = q.gte('scheduled_at', start.toUtc().toIso8601String());
          }
          if (end != null) {
            q = q.lte('scheduled_at', _endOfDay(end).toUtc().toIso8601String());
          }
          return q.order('scheduled_at', ascending: false);
        });
        _sortNewestFirst(rows, 'scheduled_at');

        final out = <Map<String, dynamic>>[];
        for (final r in rows) {
          final student = r['students'] as Map<String, dynamic>?;
          if (!_matchesCourse(student, course)) continue;
          final status = r['status'] as String? ?? 'Proposed';
          final attended = r['parent_attended'] as bool?;
          out.add({
            'Student Name': _studentName(student),
            'Student Number': student?['student_number'] ?? '--',
            'Section': _section(student),
            'Scheduled': _dayOrDash(
                _parseDate(r['scheduled_at'] as String?)?.toLocal()),
            'Location': r['location'] as String? ?? '--',
            // A completed meeting reads "Finished" in the portals and here.
            'Status': status == 'Completed'
                ? 'Finished'
                : status.replaceAll('_', ' '),
            'Parent Attended': status != 'Completed'
                ? '--'
                : (attended == null
                    ? 'Not confirmed'
                    : (attended ? 'Yes' : 'No')),
            'Summary': r['summary'] as String? ?? '--',
          });
        }
        return out;
      },
    );
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  /// Per student: violations, pending cases, sanctions and any ongoing
  /// suspension, most recent violation first.
  Future<ReportPreviewDataModel> fetchBehavioralSummary({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Violations',
      'Pending Cases',
      'Sanctions',
      'Ongoing Suspension',
      'Last Violation',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No violations recorded for this date range/department.',
      build: () async {
        final violations = await _all(() {
          var q = _client
              .from('student_violations')
              .select('student_id, status, created_at, '
                  'students ( $_studentEmbed )')
              .filter('archived_at', 'is', null);
          if (start != null) {
            q = q.gte('created_at', start.toUtc().toIso8601String());
          }
          if (end != null) {
            q = q.lte('created_at', _endOfDay(end).toUtc().toIso8601String());
          }
          return q.order('created_at', ascending: false);
        });
        final sanctions = await _all(() => _client
            .from('sanctions')
            .select('student_id, sanction_type, status, effective_on, ends_on')
            .order('effective_on', ascending: false));

        final suspended = <String>{};
        final sanctionCount = <String, int>{};
        final today = DateTime.now();
        final todayDay = DateTime(today.year, today.month, today.day);
        for (final s in sanctions) {
          final id = s['student_id'] as String?;
          if (id == null) continue;
          sanctionCount[id] = (sanctionCount[id] ?? 0) + 1;
          final to = _parseDate(s['ends_on'] as String?);
          final from = _parseDate(s['effective_on'] as String?);
          if (s['sanction_type'] == 'suspension' &&
              s['status'] != 'Completed' &&
              (to == null || !to.isBefore(todayDay)) &&
              (from == null || !from.isAfter(todayDay))) {
            suspended.add(id);
          }
        }

        const pendingStatuses = {
          'Pending',
          'Under_Investigation',
          'Investigation_Complete',
        };
        final byStudent = <String, Map<String, dynamic>>{};
        for (final v in violations) {
          final student = v['students'] as Map<String, dynamic>?;
          if (!_matchesCourse(student, course)) continue;
          final id = v['student_id'] as String? ?? _studentName(student);
          final created = _parseDate(v['created_at'] as String?)?.toLocal();
          final e = byStudent.putIfAbsent(
              id,
              () => {
                    'student': student,
                    'id': id,
                    'violations': 0,
                    'pending': 0,
                    'latest': created,
                  });
          e['violations'] = (e['violations'] as int) + 1;
          if (pendingStatuses.contains(v['status'])) {
            e['pending'] = (e['pending'] as int) + 1;
          }
          final latest = e['latest'] as DateTime?;
          if (created != null && (latest == null || created.isAfter(latest))) {
            e['latest'] = created;
          }
        }

        final entries = byStudent.values.toList()
          ..sort((a, b) {
            final x = a['latest'] as DateTime?;
            final y = b['latest'] as DateTime?;
            if (x == null) return 1;
            if (y == null) return -1;
            return y.compareTo(x);
          });
        return [
          for (final e in entries)
            {
              'Student Name':
                  _studentName(e['student'] as Map<String, dynamic>?),
              'Student Number': (e['student']
                      as Map<String, dynamic>?)?['student_number'] ??
                  '--',
              'Section': _section(e['student'] as Map<String, dynamic>?),
              'Violations': e['violations'],
              'Pending Cases': e['pending'],
              'Sanctions': sanctionCount[e['id']] ?? 0,
              'Ongoing Suspension': suspended.contains(e['id']) ? 'Yes' : 'No',
              'Last Violation': _dayOrDash(e['latest'] as DateTime?),
            },
        ];
      },
    );
  }

  /// Class attendance tallied per teacher and subject (what the professors
  /// recorded), rather than campus-wide gate activity.
  Future<ReportPreviewDataModel> fetchAttendanceByTeacherSubject({
    DateTime? start,
    DateTime? end,
    String? course,
  }) {
    const columns = [
      'Teacher',
      'Subject',
      'Present',
      'Late',
      'Absent',
      'Excused',
      'Total',
      'Attendance Rate',
    ];
    return _report(
      columns: columns,
      emptyMessage: 'No class attendance recorded for this date range/department.',
      build: () async {
        final rows = await _all(() {
          var q = _client.from('attendance_records').select(
              'status, session_date, students ( course ), '
              'class_sections ( subjects ( title ), '
              'profiles ( first_name, last_name ) )');
          if (start != null) q = q.gte('session_date', _day(start));
          if (end != null) q = q.lte('session_date', _day(end));
          return q.order('session_date', ascending: false);
        });

        final groups = <String, Map<String, dynamic>>{};
        for (final r in rows) {
          if (!_matchesCourse(r['students'] as Map<String, dynamic>?, course)) {
            continue;
          }
          final cs = r['class_sections'] as Map<String, dynamic>?;
          final teacher = cs == null
              ? '--'
              : _name(cs['profiles'] as Map<String, dynamic>?)
                  .replaceFirst('Unknown student', '--');
          final subject =
              ((cs?['subjects'] as Map<String, dynamic>?)?['title'] as String?)
                          ?.trim()
                          .isNotEmpty ==
                      true
                  ? (cs!['subjects'] as Map<String, dynamic>)['title'] as String
                  : 'Unassigned class';
          final g = groups.putIfAbsent(
              '$teacher|$subject',
              () => {
                    'Teacher': teacher,
                    'Subject': subject,
                    'present': 0,
                    'late': 0,
                    'absent': 0,
                    'excused': 0,
                  });
          final key = switch ((r['status'] as String? ?? '').toLowerCase()) {
            'late' => 'late',
            'absent' => 'absent',
            'excused' => 'excused',
            _ => 'present',
          };
          g[key] = (g[key] as int) + 1;
        }

        final keys = groups.keys.toList()..sort();
        return [
          for (final k in keys)
            () {
              final g = groups[k]!;
              final present = g['present'] as int;
              final late = g['late'] as int;
              final absent = g['absent'] as int;
              final excused = g['excused'] as int;
              final total = present + late + absent + excused;
              return <String, dynamic>{
                'Teacher': g['Teacher'],
                'Subject': g['Subject'],
                'Present': present,
                'Late': late,
                'Absent': absent,
                'Excused': excused,
                'Total': total,
                'Attendance Rate': total == 0
                    ? '--'
                    : '${((present + late) / total * 100).toStringAsFixed(1)}%',
              };
            }(),
        ];
      },
    );
  }
}
