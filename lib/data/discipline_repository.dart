import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/foundation.dart';
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
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

/// One calendar day's count for a 7-day trend — [date] is the local
/// calendar date the count is bucketed under.
class DailyCount {
  const DailyCount({required this.date, required this.count});
  final DateTime date;
  final int count;
}

/// One row of the Overview page's "Recent Attendance Activity" feed —
/// `attendance_records` reinterpreted honestly as check-in events (only
/// `Present`/`Late` rows carry an actual scan; `Absent` has none to show).
class AttendanceActivityEntry {
  const AttendanceActivityEntry({
    required this.studentName,
    required this.studentNumber,
    required this.sectionName,
    required this.isLate,
    required this.recordedAt,
  });

  final String studentName;
  final String studentNumber;
  final String sectionName;
  final bool isLate;
  final DateTime recordedAt;
}

/// One row of the Overview page's "Early Warning Triggers" panel —
/// `risk_assessments` rows flagged `early_warning_30d`.
class EarlyWarningEntry {
  const EarlyWarningEntry({
    required this.studentName,
    required this.studentNumber,
    required this.sectionName,
    required this.riskPercent,
    required this.riskLevel,
    required this.factors,
  });

  final String studentName;
  final String studentNumber;
  final String sectionName;
  final int riskPercent;
  final String riskLevel;
  final List<String> factors;
}

class DisciplineRepository {
  DisciplineRepository(this._client);

  final SupabaseClient _client;

  static const _studentEmbed = '''
student_number,
profiles ( first_name, last_name ),
sections ( name, program, year_level )
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
archived_at,
incident_notes,
students ( $_studentEmbed ),
handbook_offenses ( description, category, penalty_info ),
profiles ( first_name, last_name )
''';

  /// How long an archived ("deleted") violation report stays viewable before
  /// it's permanently purged — see [archiveViolation] / [fetchArchivedViolations].
  static const archiveRetention = Duration(days: 7);

  Future<ViolationStatusCounts> fetchStatusCounts() async {
    final rows = await _client
        .from('student_violations')
        .select('status, is_escalated, updated_at')
        .filter('archived_at', 'is', null);

    var pending = 0,
        underInvestigation = 0,
        resolved = 0,
        escalatedActive = 0,
        resolvedToday = 0;
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
        .eq('status', 'Resolved')
        .filter('archived_at', 'is', null);
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
        .select('handbook_offenses ( category )')
        .filter('archived_at', 'is', null);

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

  /// Every calendar day in the trailing [days]-day window (oldest first,
  /// today last), each initialized to a zero count — callers fill in real
  /// counts by date so a day with no activity still appears as a bar/point
  /// rather than being silently skipped.
  List<DateTime> _trailingDays(int days) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return [
      for (var i = days - 1; i >= 0; i--) todayDate.subtract(Duration(days: i)),
    ];
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// `attendance_records` recorded per day over the trailing [days] days —
  /// backs the Overview page's "Today's Active Scans" sparkline. Counts
  /// every status (Present/Late/Absent all involve a recorded scan/entry).
  Future<List<DailyCount>> fetchDailyAttendanceCounts({int days = 7}) async {
    final trailing = _trailingDays(days);
    final cutoff = trailing.first;
    final rows = await _client
        .from('attendance_records')
        .select('session_date')
        .gte('session_date', cutoff.toIso8601String().split('T').first);

    final byDate = <String, int>{};
    for (final raw in rows as List<dynamic>) {
      final dateStr = (raw as Map<String, dynamic>)['session_date'] as String;
      byDate[dateStr] = (byDate[dateStr] ?? 0) + 1;
    }

    return [
      for (final day in trailing)
        DailyCount(
          date: day,
          count: byDate[day.toIso8601String().split('T').first] ?? 0,
        ),
    ];
  }

  /// New (non-archived) `student_violations` per day over the trailing
  /// [days] days, bucketed by local calendar date — backs the Overview
  /// page's "Discipline Alerts" sparkline and the weekly trend chart.
  Future<List<DailyCount>> fetchDailyNewViolationCounts({int days = 7}) async {
    final trailing = _trailingDays(days);
    final cutoff = trailing.first;
    final rows = await _client
        .from('student_violations')
        .select('created_at')
        .filter('archived_at', 'is', null)
        .gte('created_at', cutoff.toIso8601String());

    final counts = List<int>.filled(trailing.length, 0);
    for (final raw in rows as List<dynamic>) {
      final createdAt =
          DateTime.tryParse((raw as Map<String, dynamic>)['created_at'] as String? ?? '');
      if (createdAt == null) continue;
      final local = createdAt.toLocal();
      for (var i = 0; i < trailing.length; i++) {
        if (_isSameDate(trailing[i], local)) {
          counts[i]++;
          break;
        }
      }
    }

    return [
      for (var i = 0; i < trailing.length; i++)
        DailyCount(date: trailing[i], count: counts[i]),
    ];
  }

  /// `risk_assessments` rows at CRITICAL or HIGH risk, bucketed by the local
  /// calendar date they were last (re)computed — backs the Overview page's
  /// "High-Risk Students" sparkline. This tracks recompute activity, not a
  /// true historical snapshot of risk levels (the table only stores each
  /// student's *current* assessment, not a per-day history) — the closest
  /// honest proxy for a trend this schema supports.
  Future<List<DailyCount>> fetchDailyHighRiskCounts({int days = 7}) async {
    final trailing = _trailingDays(days);
    final cutoff = trailing.first;
    final rows = await _client
        .from('risk_assessments')
        .select('risk_level, computed_at')
        .gte('computed_at', cutoff.toIso8601String());

    final counts = List<int>.filled(trailing.length, 0);
    for (final raw in rows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final level = (row['risk_level'] as String? ?? '').toUpperCase();
      if (level != 'CRITICAL' && level != 'HIGH') continue;
      final computedAt =
          DateTime.tryParse(row['computed_at'] as String? ?? '');
      if (computedAt == null) continue;
      final local = computedAt.toLocal();
      for (var i = 0; i < trailing.length; i++) {
        if (_isSameDate(trailing[i], local)) {
          counts[i]++;
          break;
        }
      }
    }

    return [
      for (var i = 0; i < trailing.length; i++)
        DailyCount(date: trailing[i], count: counts[i]),
    ];
  }

  /// Count of `risk_assessments` rows at CRITICAL or HIGH risk — matches
  /// `GuidanceCounselorRepository.fetchOverview`'s definition of "at risk"
  /// so the Admin Overview's figure doesn't silently drift from the
  /// Guidance Counselor dashboard's.
  Future<int> fetchHighRiskCount() async {
    final rows =
        await _client.from('risk_assessments').select('risk_level');
    var count = 0;
    for (final raw in rows as List<dynamic>) {
      final level =
          ((raw as Map<String, dynamic>)['risk_level'] as String? ?? '')
              .toUpperCase();
      if (level == 'CRITICAL' || level == 'HIGH') count++;
    }
    return count;
  }

  /// Most recent attendance check-ins (Present/Late only — Absent has no
  /// scan event to show) — backs the Overview page's "Recent Attendance
  /// Activity" feed.
  Future<List<AttendanceActivityEntry>> fetchRecentAttendanceActivity({
    int limit = 10,
  }) async {
    final rows = await _client
        .from('attendance_records')
        .select('status, recorded_at, students ( $_studentEmbed )')
        .inFilter('status', ['Present', 'Late'])
        .order('recorded_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final profile = student?['profiles'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;
      return AttendanceActivityEntry(
        studentName: _fullName(
          profile?['first_name'] as String?,
          profile?['last_name'] as String?,
        ),
        studentNumber: student?['student_number'] as String? ?? '',
        sectionName: section?['name'] as String? ?? 'Unknown section',
        isLate: row['status'] == 'Late',
        recordedAt: DateTime.parse(row['recorded_at'] as String),
      );
    }).toList();
  }

  /// `risk_assessments` rows flagged for a 30-day early warning — backs the
  /// Overview page's "Early Warning Triggers" panel.
  Future<List<EarlyWarningEntry>> fetchEarlyWarningStudents({
    int limit = 8,
  }) async {
    final rows = await _client
        .from('risk_assessments')
        .select(
            'dropout_probability, risk_level, key_factors, students ( $_studentEmbed )')
        .eq('early_warning_30d', true)
        .order('dropout_probability', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final profile = student?['profiles'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;
      final keyFactors = row['key_factors'] as List<dynamic>? ?? const [];
      return EarlyWarningEntry(
        studentName: _fullName(
          profile?['first_name'] as String?,
          profile?['last_name'] as String?,
        ),
        studentNumber: student?['student_number'] as String? ?? '',
        sectionName: section?['name'] as String? ?? 'Unknown section',
        riskPercent:
            (((row['dropout_probability'] as num?)?.toDouble() ?? 0) * 100)
                .round(),
        riskLevel:
            (row['risk_level'] as String? ?? 'MODERATE').toUpperCase(),
        factors: keyFactors
            .whereType<Map<String, dynamic>>()
            .map((f) => f['factor'] as String?)
            .whereType<String>()
            .take(2)
            .toList(),
      );
    }).toList();
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
        .filter('archived_at', 'is', null)
        .order('created_at', ascending: false);

    final parsed = (rows as List<dynamic>)
        .map((e) => _toCaseModel(e as Map<String, dynamic>))
        .toList();

    // Prior-violations count per student — a second lightweight query
    // (student_id only, every status) rather than a per-row round trip.
    final tally = await fetchViolationCountsByStudent();

    return parsed.map((entry) {
      final total = tally[entry.studentId] ?? 1;
      return entry.caseModel.copyWith(
        priorViolationsCount: total > 0 ? total - 1 : 0,
      );
    }).toList();
  }

  /// `student_id` -> count of non-archived `student_violations` rows (every
  /// status). Backs both [fetchActiveViolations]'s "prior violations" figure
  /// and the Good Moral Student List's "Previous violations" field.
  Future<Map<String, int>> fetchViolationCountsByStudent() async {
    final rows = await _client
        .from('student_violations')
        .select('student_id')
        .filter('archived_at', 'is', null);
    final tally = <String, int>{};
    for (final raw in rows as List<dynamic>) {
      final id = (raw as Map<String, dynamic>)['student_id'] as String;
      tally[id] = (tally[id] ?? 0) + 1;
    }
    return tally;
  }

  /// Student ids with at least one active (`Pending`/`Under_Investigation`,
  /// non-archived) violation — a student is "Not Clear" for Good Moral
  /// purposes exactly when they appear in this set.
  Future<Set<String>> fetchActiveViolationStudentIds() async {
    final rows = await _client
        .from('student_violations')
        .select('student_id')
        .inFilter('status', ['Pending', 'Under_Investigation'])
        .filter('archived_at', 'is', null);
    return {
      for (final raw in rows as List<dynamic>)
        (raw as Map<String, dynamic>)['student_id'] as String
    };
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
      violationType:
          offense?['description'] as String? ?? 'Unspecified offense',
      isEscalated: row['is_escalated'] as bool? ?? false,
      slaRemaining: _formatSlaRemaining(row['sla_due_at'] as String?),
      submittedBy: reporterName.isEmpty ? 'Unknown' : reporterName,
      // TODO(supabase): populate once `profiles` exposes a role/title
      // column (e.g. `role_title`) to select alongside first/last name.
      submitterRole: '',
      incidentDateTime: DateTime.parse(row['created_at'] as String),
      // Prefers the reporter's own incident notes (e.g. a professor's
      // Conduct Report submission) over the offense's generic boilerplate,
      // when present.
      description: (row['incident_notes'] as String?)?.trim().isNotEmpty ==
              true
          ? (row['incident_notes'] as String).trim()
          : (offense?['penalty_info'] as String?) ?? '',
      offenseId: row['offense_id'] as String?,
      penaltyImposed: row['penalty_imposed'] as String?,
      archivedAt: row['archived_at'] == null
          ? null
          : DateTime.parse(row['archived_at'] as String),
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
    final rows = await _client.from('good_moral_requests').select('''
id,
student_id,
document_type,
purpose,
requested_by,
request_date,
remarks,
students ( $_studentEmbed )
''').order('request_date', ascending: false);

    final activeIds = await fetchActiveViolationStudentIds();

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
        hasActiveViolation: activeIds.contains(row['student_id'] as String?),
      );
    }).toList();
  }

  Future<List<StudentDirectoryEntryModel>> fetchStudentDirectory() async {
    final rows = await _client
        .from('students')
        .select('id, $_studentEmbed')
        .order('student_number');

    final counts = await fetchViolationCountsByStudent();
    final activeIds = await fetchActiveViolationStudentIds();
    return (rows as List<dynamic>)
        .map((e) => _toStudentDirectoryEntry(e, counts, activeIds))
        .toList();
  }

  /// One page of the student directory (1-indexed) plus the total row
  /// count — backs the Good Moral Management "Students List" so it doesn't
  /// have to load every enrolled student just to show one screenful.
  Future<({List<StudentDirectoryEntryModel> items, int totalCount})>
      fetchStudentDirectoryPage({required int page, int pageSize = 25}) async {
    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;

    // Ordered by program/year level first (then section name, then student
    // number) so consecutive rows naturally cluster into the same
    // program/year group — the UI (GoodMoralQueueCard) renders a header
    // whenever that group changes, rather than needing a separate grouping
    // query or pass.
    final response = await _client
        .from('students')
        .select('id, $_studentEmbed')
        .order('program', referencedTable: 'sections')
        .order('year_level', referencedTable: 'sections')
        .order('name', referencedTable: 'sections')
        .order('student_number')
        .range(from, to)
        .count(CountOption.exact);

    final counts = await fetchViolationCountsByStudent();
    final activeIds = await fetchActiveViolationStudentIds();
    final rows = response.data as List<dynamic>;
    return (
      items: rows
          .map((e) => _toStudentDirectoryEntry(e, counts, activeIds))
          .toList(),
      totalCount: response.count,
    );
  }

  StudentDirectoryEntryModel _toStudentDirectoryEntry(
    dynamic e,
    Map<String, int> violationCounts,
    Set<String> activeViolationStudentIds,
  ) {
    final row = e as Map<String, dynamic>;
    final studentProfile = row['profiles'] as Map<String, dynamic>?;
    final section = row['sections'] as Map<String, dynamic>?;
    final studentId = row['id'] as String;

    return StudentDirectoryEntryModel(
      id: studentId,
      studentName: _fullName(
        studentProfile?['first_name'] as String?,
        studentProfile?['last_name'] as String?,
      ),
      studentNumber: row['student_number'] as String? ?? '',
      programGradeSection: section?['name'] as String? ?? '',
      program: section?['program'] as String? ?? '',
      yearLevel: (section?['year_level'] as num?)?.toInt() ?? 0,
      previousViolationsCount: violationCounts[studentId] ?? 0,
      hasActiveViolation: activeViolationStudentIds.contains(studentId),
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
      await _client
          .from('student_violations')
          .update(patch)
          .eq('id', violationId);
    } on PostgrestException catch (e) {
      throw DisciplineRepositoryException(e.message);
    }
  }

  /// "Delete" on [ViolationPreviewPanel] — soft-deletes by stamping
  /// `archived_at` rather than removing the row outright, so the report
  /// stays available (read-only) in [fetchArchivedViolations] for
  /// [archiveRetention] before [_purgeExpiredArchives] removes it for good.
  Future<void> archiveViolation(String violationId) async {
    try {
      await _client.from('student_violations').update({
        'archived_at': DateTime.now().toIso8601String(),
      }).eq('id', violationId);
    } on PostgrestException catch (e) {
      throw DisciplineRepositoryException(e.message);
    }
  }

  /// Permanently deletes every archived report past [archiveRetention].
  /// Best-effort/lazy — run at the start of [fetchArchivedViolations]
  /// instead of on a schedule, so it needs no cron/background-job support
  /// beyond what the app's own Supabase access already has. A failure here
  /// is logged and swallowed rather than surfaced, since it shouldn't block
  /// the officer from viewing the (still valid) archive list.
  Future<void> _purgeExpiredArchives() async {
    final cutoff = DateTime.now().subtract(archiveRetention).toIso8601String();
    try {
      await _client.from('student_violations').delete().lt('archived_at', cutoff);
    } on PostgrestException catch (e) {
      debugPrint('Could not purge expired archived violations: ${e.message}');
    }
  }

  /// Archived reports still inside their [archiveRetention] viewing window,
  /// newest-archived first. Read-only — the UI offers no action on these
  /// besides viewing.
  Future<List<DisciplineCaseModel>> fetchArchivedViolations() async {
    await _purgeExpiredArchives();
    final rows = await _client
        .from('student_violations')
        .select(_violationSelect)
        .not('archived_at', 'is', null)
        .order('archived_at', ascending: false);

    return (rows as List<dynamic>)
        .map((e) => _toCaseModel(e as Map<String, dynamic>).caseModel)
        .toList();
  }
}
