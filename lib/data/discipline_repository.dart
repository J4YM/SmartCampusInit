import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DisciplineRepositoryException implements Exception {
  DisciplineRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `student_violations` grouped by `status` (`Pending` / `Under_Investigation`
/// / `Resolved`), plus a couple of derived figures for the Overview and DO
/// Dashboard summary cards.
class ViolationStatusCounts {
  const ViolationStatusCounts({
    this.pending = 0,
    this.underInvestigation = 0,
    this.resolved = 0,
    this.escalatedActive = 0,
    this.resolvedToday = 0,
    this.avgResolutionMinutes = 0.0,
  });

  final int pending;
  final int underInvestigation;
  final int resolved;

  /// Escalated (`is_escalated`) cases still `Pending`/`Under_Investigation`.
  final int escalatedActive;

  /// `Resolved` cases whose `updated_at` falls on today's date.
  final int resolvedToday;

  /// Average minutes between `created_at` and `updated_at` across every
  /// `Resolved` case — the closest available proxy for response time, since
  /// there's no dedicated "resolved at" timestamp.
  final double avgResolutionMinutes;

  int get activeTotal => pending + underInvestigation;
}

/// One `handbook_offenses.category` bucket (e.g. "Minor", "Major_A") and how
/// many `student_violations` rows currently reference an offense in it.
class HotzoneBucket {
  const HotzoneBucket({required this.category, required this.count});
  final String category;
  final int count;

  /// "Major_A" -> "Major A"; otherwise title-cases and de-underscores.
  String get displayLabel => category
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

class DisciplineRepository {
  DisciplineRepository(this._client);

  final SupabaseClient _client;

  static const _studentEmbed = '''
student_number,
profiles ( first_name, last_name ),
sections ( name )
''';

  static const _violationSelect = '''
id,
student_id,
offense_id,
is_escalated,
sla_due_at,
penalty_imposed,
status,
created_at,
students ( $_studentEmbed ),
handbook_offenses ( description, category, penalty_info ),
profiles ( first_name, last_name )
''';

  Future<ViolationStatusCounts> fetchStatusCounts() async {
    final rows = await _client
        .from('student_violations')
        .select('status, is_escalated, updated_at');

    var pending = 0, underInvestigation = 0, resolved = 0, escalatedActive = 0, resolvedToday = 0;
    var totalResolutionSeconds = 0;
    var resolvedWithTiming = 0;
    final now = DateTime.now();

    for (final raw in rows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final status = row['status'] as String?;
      final isEscalated = row['is_escalated'] as bool? ?? false;
      final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');

      switch (status) {
        case 'Pending':
          pending++;
          if (isEscalated) escalatedActive++;
        case 'Under_Investigation':
          underInvestigation++;
          if (isEscalated) escalatedActive++;
        case 'Resolved':
          resolved++;
          if (updatedAt != null) {
            if (updatedAt.year == now.year &&
                updatedAt.month == now.month &&
                updatedAt.day == now.day) {
              resolvedToday++;
            }
          }
      }
    }

    // Second pass for average resolution time (needs created_at too, kept
    // out of the loop above to avoid parsing two timestamps for every row
    // when most callers only need the counts).
    final timed = await _client
        .from('student_violations')
        .select('created_at, updated_at')
        .eq('status', 'Resolved');
    for (final raw in timed as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
      final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
      if (createdAt != null && updatedAt != null) {
        totalResolutionSeconds += updatedAt.difference(createdAt).inSeconds;
        resolvedWithTiming++;
      }
    }

    return ViolationStatusCounts(
      pending: pending,
      underInvestigation: underInvestigation,
      resolved: resolved,
      escalatedActive: escalatedActive,
      resolvedToday: resolvedToday,
      avgResolutionMinutes: resolvedWithTiming == 0
          ? 0.0
          : (totalResolutionSeconds / resolvedWithTiming) / 60.0,
    );
  }

  /// Violation counts grouped by `handbook_offenses.category` — backs the
  /// Overview page's "Violation Hotzone" chart. Buckets are whatever
  /// categories actually occur in the data (this schema's categories are a
  /// severity tier — Minor/Major_A/Major_B/Major_C/Major_D — rather than a
  /// tardiness/uniform/phone-use style breakdown).
  Future<List<HotzoneBucket>> fetchHotzoneByCategory() async {
    final rows = await _client
        .from('student_violations')
        .select('handbook_offenses ( category )');

    final counts = <String, int>{};
    for (final raw in rows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final offense = row['handbook_offenses'] as Map<String, dynamic>?;
      final category = offense?['category'] as String?;
      if (category == null) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }

    final buckets = counts.entries
        .map((e) => HotzoneBucket(category: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return buckets;
  }

  Future<List<OffenseOption>> fetchOffenseOptions() async {
    final rows = await _client
        .from('handbook_offenses')
        .select('id, description, category')
        .order('description');
    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      return OffenseOption(
        id: row['id'] as String,
        label: row['description'] as String,
        category: row['category'] as String?,
      );
    }).toList();
  }

  Future<List<DisciplineCaseModel>> fetchActiveViolations() async {
    final rows = await _client
        .from('student_violations')
        .select(_violationSelect)
        .inFilter('status', ['Pending', 'Under_Investigation'])
        .order('created_at', ascending: false);

    final parsed = (rows as List<dynamic>)
        .map((e) => _toCaseModel(e as Map<String, dynamic>))
        .toList();

    // Prior-violations count per student — a second lightweight query
    // (student_id only, every status) rather than a per-row round trip.
    final allStudentIds = await _client.from('student_violations').select('student_id');
    final tally = <String, int>{};
    for (final raw in allStudentIds as List<dynamic>) {
      final id = (raw as Map<String, dynamic>)['student_id'] as String;
      tally[id] = (tally[id] ?? 0) + 1;
    }

    return parsed.map((entry) {
      final total = tally[entry.studentId] ?? 1;
      return entry.caseModel.copyWith(
        priorViolationsCount: total > 0 ? total - 1 : 0,
      );
    }).toList();
  }

  ({DisciplineCaseModel caseModel, String studentId}) _toCaseModel(
    Map<String, dynamic> row,
  ) {
    final student = row['students'] as Map<String, dynamic>?;
    final studentProfile = student?['profiles'] as Map<String, dynamic>?;
    final section = student?['sections'] as Map<String, dynamic>?;
    final offense = row['handbook_offenses'] as Map<String, dynamic>?;
    final reporter = row['profiles'] as Map<String, dynamic>?;

    final studentName = _fullName(
      studentProfile?['first_name'] as String?,
      studentProfile?['last_name'] as String?,
    );
    final reporterName = _fullName(
      reporter?['first_name'] as String?,
      reporter?['last_name'] as String?,
    );

    final caseModel = DisciplineCaseModel(
      id: row['id'] as String,
      studentName: studentName.isEmpty ? 'Unknown student' : studentName,
      studentNumber: student?['student_number'] as String? ?? '',
      programGradeSection: section?['name'] as String? ?? '',
      violationType: offense?['description'] as String? ?? 'Unspecified offense',
      isEscalated: row['is_escalated'] as bool? ?? false,
      slaRemaining: _formatSlaRemaining(row['sla_due_at'] as String?),
      submittedBy: reporterName.isEmpty ? 'Unknown' : reporterName,
      incidentLocation: '',
      incidentDateTime: DateTime.parse(row['created_at'] as String),
      description: (offense?['penalty_info'] as String?) ?? '',
      offenseId: row['offense_id'] as String?,
      penaltyImposed: row['penalty_imposed'] as String?,
    );
    return (caseModel: caseModel, studentId: row['student_id'] as String);
  }

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  String? _formatSlaRemaining(String? slaDueAtIso) {
    if (slaDueAtIso == null) return null;
    final dueAt = DateTime.tryParse(slaDueAtIso);
    if (dueAt == null) return null;
    final remaining = dueAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Overdue';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  Future<List<GoodMoralRequestModel>> fetchGoodMoralRequests() async {
    final rows = await _client
        .from('good_moral_requests')
        .select('''
id,
document_type,
purpose,
requested_by,
request_date,
remarks,
students ( $_studentEmbed )
''')
        .order('request_date', ascending: false);

    return (rows as List<dynamic>).map((e) {
      final row = e as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final studentProfile = student?['profiles'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;

      return GoodMoralRequestModel(
        id: row['id'] as String,
        studentName: _fullName(
          studentProfile?['first_name'] as String?,
          studentProfile?['last_name'] as String?,
        ),
        studentNumber: student?['student_number'] as String? ?? '',
        programGradeSection: section?['name'] as String? ?? '',
        documentType: row['document_type'] as String,
        purpose: row['purpose'] as String,
        requestedBy: row['requested_by'] as String,
        requestDateTime: DateTime.parse(row['request_date'] as String),
        remarks: (row['remarks'] as String?) ?? '',
      );
    }).toList();
  }

  Future<List<StudentDirectoryEntryModel>> fetchStudentDirectory() async {
    final rows = await _client
        .from('students')
        .select('id, $_studentEmbed')
        .order('student_number');

    return (rows as List<dynamic>).map(_toStudentDirectoryEntry).toList();
  }

  /// One page of the student directory (1-indexed) plus the total row
  /// count — backs the Good Moral Management "Students List" so it doesn't
  /// have to load every enrolled student just to show one screenful.
  Future<({List<StudentDirectoryEntryModel> items, int totalCount})>
      fetchStudentDirectoryPage({required int page, int pageSize = 25}) async {
    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;

    final response = await _client
        .from('students')
        .select('id, $_studentEmbed')
        .order('student_number')
        .range(from, to)
        .count(CountOption.exact);

    final rows = response.data as List<dynamic>;
    return (
      items: rows.map(_toStudentDirectoryEntry).toList(),
      totalCount: response.count,
    );
  }

  StudentDirectoryEntryModel _toStudentDirectoryEntry(dynamic e) {
    final row = e as Map<String, dynamic>;
    final studentProfile = row['profiles'] as Map<String, dynamic>?;
    final section = row['sections'] as Map<String, dynamic>?;

    return StudentDirectoryEntryModel(
      id: row['id'] as String,
      studentName: _fullName(
        studentProfile?['first_name'] as String?,
        studentProfile?['last_name'] as String?,
      ),
      studentNumber: row['student_number'] as String? ?? '',
      programGradeSection: section?['name'] as String? ?? '',
    );
  }

  /// Validate/Deny both resolve the case the same way — this schema's
  /// `violation_status` enum has no distinct "denied" state (`Pending` ->
  /// `Under_Investigation` -> `Resolved` only).
  Future<void> resolveViolation(String violationId) async {
    try {
      await _client.from('student_violations').update({
        'status': 'Resolved',
        'acknowledged_at': DateTime.now().toIso8601String(),
      }).eq('id', violationId);
    } on PostgrestException catch (e) {
      throw DisciplineRepositoryException(e.message);
    }
  }

  Future<void> updateViolation(
    String violationId, {
    String? offenseId,
    bool? isEscalated,
    String? penaltyImposed,
  }) async {
    final patch = <String, dynamic>{
      if (offenseId != null) 'offense_id': offenseId,
      if (isEscalated != null) 'is_escalated': isEscalated,
      if (penaltyImposed != null) 'penalty_imposed': penaltyImposed,
    };
    if (patch.isEmpty) return;
    try {
      await _client.from('student_violations').update(patch).eq('id', violationId);
    } on PostgrestException catch (e) {
      throw DisciplineRepositoryException(e.message);
    }
  }
}
