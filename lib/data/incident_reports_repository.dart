import 'package:supabase_flutter/supabase_flutter.dart';

class IncidentReportsException implements Exception {
  IncidentReportsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A student found by [IncidentReportsRepository.searchStudents].
class IncidentStudentHit {
  const IncidentStudentHit({
    required this.id,
    required this.name,
    required this.studentNumber,
    this.section = '',
  });

  final String id;
  final String name;
  final String studentNumber;
  final String section;
}

/// Student Affairs' manual incident reports
/// (supabase/add_manual_incident_reports.sql).
class IncidentReportsRepository {
  IncidentReportsRepository(this._client);

  final SupabaseClient _client;

  /// Records the incident quietly (`report_incident`); returns the new
  /// violation id. Nothing reaches the parent unless [notifyParent] is true.
  Future<String> report({
    required String studentId,
    required String offenseId,
    required String description,
    required DateTime occurredAt,
    String? location,
    bool notifyParent = false,
    String? concernId,
  }) async {
    try {
      final id = await _client.rpc('report_incident', params: {
        'p_student_id': studentId,
        'p_offense_id': offenseId,
        'p_description': description,
        'p_occurred_at': occurredAt.toUtc().toIso8601String(),
        'p_location': location,
        'p_notify_parent': notifyParent,
        if (concernId != null) 'p_concern_id': concernId,
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw IncidentReportsException(e.message);
    }
  }

  /// The officer's explicit "tell the parent" for an already recorded incident.
  Future<void> notifyParent(String violationId) async {
    try {
      await _client.rpc('notify_parent_of_incident',
          params: {'p_violation_id': violationId});
    } on PostgrestException catch (e) {
      throw IncidentReportsException(e.message);
    }
  }

  /// Students whose name or number contains [query] (everyone when empty).
  Future<List<IncidentStudentHit>> searchStudents(
    String query, {
    int limit = 40,
  }) async {
    try {
      // PostgREST returns at most 1,000 rows per request, so page through the
      // roster; filtering only the first page would hide every later student.
      const pageSize = 1000;
      final all = <dynamic>[];
      for (var page = 0; page < 50; page++) {
        final rows = await _client
            .from('students')
            .select(
                'id, student_number, profiles ( first_name, last_name ), sections ( name )')
            .order('student_number')
            .range(page * pageSize, (page + 1) * pageSize - 1);
        all.addAll(rows as List<dynamic>);
        if (rows.length < pageSize) break;
      }
      final needle = query.trim().toLowerCase();
      final hits = <IncidentStudentHit>[];
      for (final raw in all) {
        final row = raw as Map<String, dynamic>;
        final profile = row['profiles'] as Map<String, dynamic>?;
        final name =
            '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'
                .trim();
        final number = row['student_number'] as String? ?? '';
        if (needle.isNotEmpty &&
            !name.toLowerCase().contains(needle) &&
            !number.toLowerCase().contains(needle)) {
          continue;
        }
        hits.add(IncidentStudentHit(
          id: row['id'] as String,
          name: name.isEmpty ? number : name,
          studentNumber: number,
          section:
              (row['sections'] as Map<String, dynamic>?)?['name'] as String? ??
                  '',
        ));
        if (hits.length >= limit) break;
      }
      return hits;
    } on PostgrestException catch (e) {
      throw IncidentReportsException(e.message);
    }
  }
}
