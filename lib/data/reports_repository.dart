import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Backs the Admin Dashboard's Reports & Exports page — one method per
/// report type in `_reportTypeOptions` (reports_exports_page.dart). Every
/// method returns real query results (department-filtered client-side,
/// since result sets here are small enough not to need a server-side
/// embedded-column filter) rather than fabricated rows.
class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  static const _studentEmbed = '''
student_number,
course,
profiles ( first_name, last_name ),
sections ( name )
''';

  String _fullName(Map<String, dynamic>? profile) {
    final first = (profile?['first_name'] as String? ?? '').trim();
    final last = (profile?['last_name'] as String? ?? '').trim();
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Unknown student' : name;
  }

  bool _matchesCourse(Map<String, dynamic>? student, String? course) {
    if (course == null || course == 'All Departments') return true;
    return student?['course'] == course;
  }

  Future<ReportPreviewDataModel> fetchViolationSummary({
    DateTime? start,
    DateTime? end,
    String? course,
  }) async {
    var query = _client
        .from('student_violations')
        .select('created_at, status, students ( $_studentEmbed ), '
            'handbook_offenses ( description, category )')
        .filter('archived_at', 'is', null);
    if (start != null) query = query.gte('created_at', start.toIso8601String());
    if (end != null) query = query.lte('created_at', end.toIso8601String());

    final rows = (await query.order('created_at', ascending: false))
        as List<dynamic>;

    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Course',
      'Offense',
      'Category',
      'Status',
      'Date',
    ];

    final previewRows = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      if (!_matchesCourse(student, course)) continue;

      final offense = row['handbook_offenses'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');

      previewRows.add({
        'Student Name': _fullName(student?['profiles'] as Map<String, dynamic>?),
        'Student Number': student?['student_number'] as String? ?? '--',
        'Section': section?['name'] as String? ?? '--',
        'Course': student?['course'] as String? ?? '--',
        'Offense': offense?['description'] as String? ?? '--',
        'Category': offense?['category'] as String? ?? '--',
        'Status': row['status'] as String? ?? '--',
        'Date': createdAt == null
            ? '--'
            : '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}',
      });
    }

    return ReportPreviewDataModel(
      columns: columns,
      previewRows: previewRows,
      totalRows: previewRows.length,
      isPreviewGenerated: true,
      emptyMessage: previewRows.isEmpty
          ? 'No violations recorded for this date range/department.'
          : null,
    );
  }

  Future<ReportPreviewDataModel> fetchMlRiskSummary({
    DateTime? start,
    DateTime? end,
    String? course,
  }) async {
    var query = _client.from('risk_assessments').select(
        'computed_at, risk_level, dropout_probability, students ( $_studentEmbed )');
    if (start != null) query = query.gte('computed_at', start.toIso8601String());
    if (end != null) query = query.lte('computed_at', end.toIso8601String());

    final rows = (await query.order('computed_at', ascending: false))
        as List<dynamic>;

    const columns = [
      'Student Name',
      'Student Number',
      'Section',
      'Course',
      'Risk Level',
      'Dropout Probability',
      'Assessed Date',
    ];

    final previewRows = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      if (!_matchesCourse(student, course)) continue;

      final section = student?['sections'] as Map<String, dynamic>?;
      final computedAt = DateTime.tryParse(row['computed_at'] as String? ?? '');
      final probability = (row['dropout_probability'] as num?)?.toDouble() ?? 0;

      previewRows.add({
        'Student Name': _fullName(student?['profiles'] as Map<String, dynamic>?),
        'Student Number': student?['student_number'] as String? ?? '--',
        'Section': section?['name'] as String? ?? '--',
        'Course': student?['course'] as String? ?? '--',
        'Risk Level': row['risk_level'] as String? ?? '--',
        'Dropout Probability': '${(probability * 100).toStringAsFixed(1)}%',
        'Assessed Date': computedAt == null
            ? '--'
            : '${computedAt.year}-${computedAt.month.toString().padLeft(2, '0')}-${computedAt.day.toString().padLeft(2, '0')}',
      });
    }

    return ReportPreviewDataModel(
      columns: columns,
      previewRows: previewRows,
      totalRows: previewRows.length,
      isPreviewGenerated: true,
      emptyMessage: previewRows.isEmpty
          ? 'No ML risk assessments recorded for this date range/department.'
          : null,
    );
  }

  /// No `attendance_records` (or equivalent) table exists yet — that's the
  /// Professor module's attendance schema, not built yet. Returns a real,
  /// honestly-empty result rather than fabricated rows.
  Future<ReportPreviewDataModel> fetchAttendanceSummary({
    DateTime? start,
    DateTime? end,
    String? course,
  }) async {
    return const ReportPreviewDataModel(
      columns: ['Student Name', 'Student Number', 'Date', 'Status'],
      previewRows: [],
      totalRows: 0,
      isPreviewGenerated: true,
      emptyMessage: 'No attendance data recorded yet — this report will '
          "populate once the Professor module's attendance tracking is "
          'wired up.',
    );
  }
}
