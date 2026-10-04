import 'package:guidance_counselor_module/pages/batch_student_analysis/batch_student_analysis_view.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts a Philippine 1.00-5.00 numeric grade (1.00 = best) — what
/// `student_gpa_records.cumulative_gpa` actually stores — to its standard
/// percentage equivalent (higher = better), because that's what the ML
/// service's `current_gwa`/`previous_gwa` fields were actually trained on:
/// confirmed against `Behavioral AI Model/data/features/
/// engineered_features.csv`, whose GWA values are plain percentages like
/// 90.0/88.0, not 1.00-5.00. Sending the raw 1.00-5.00 value through
/// unconverted doesn't just score wrong — every real GPA clusters into the
/// same tiny slice of the model's `pd.cut(current_gwa, bins=[0, 75, 85,
/// 100])` binning (feature_pipeline.py), which is what actually produced
/// the "'<' not supported between instances of 'NoneType' and 'NoneType'"
/// crash on `/predict/batch`.
///
/// Uses the standard Philippine-college numeric-to-percentage table
/// (1.00->100, 1.25->97, ... 3.00->76 — the widely-used STI/private-college
/// convention), linearly interpolated between its breakpoints and
/// extrapolated at the last segment's slope beyond 3.00 (a cumulative GPA
/// can exceed 3.00 once failed subjects are averaged in, even though no
/// single subject grade does), clamped to [0, 100].
double gwaToPercentage(double gpa) {
  const breakpoints = <({double gpa, double percent})>[
    (gpa: 1.00, percent: 100),
    (gpa: 1.25, percent: 97),
    (gpa: 1.50, percent: 94),
    (gpa: 1.75, percent: 91),
    (gpa: 2.00, percent: 88),
    (gpa: 2.25, percent: 85),
    (gpa: 2.50, percent: 82),
    (gpa: 2.75, percent: 79),
    (gpa: 3.00, percent: 76),
  ];

  if (gpa <= breakpoints.first.gpa) return breakpoints.first.percent;

  for (var i = 0; i < breakpoints.length - 1; i++) {
    final a = breakpoints[i];
    final b = breakpoints[i + 1];
    if (gpa <= b.gpa) {
      final t = (gpa - a.gpa) / (b.gpa - a.gpa);
      return a.percent + (b.percent - a.percent) * t;
    }
  }

  final secondLast = breakpoints[breakpoints.length - 2];
  final last = breakpoints.last;
  final slope = (last.percent - secondLast.percent) / (last.gpa - secondLast.gpa);
  return (last.percent + slope * (gpa - last.gpa)).clamp(0.0, 100.0);
}

/// Maps the ML service's own risk-level wording (CRITICAL/HIGH/MODERATE/LOW,
/// in whatever casing a caller has it) to `risk_assessments.risk_level`'s
/// actual Postgres enum labels. That enum predates this repo's own tracked
/// migrations (there's no `create type` for it anywhere in supabase/*.sql)
/// and was confirmed empirically — by probing real inserts against the
/// live database — to be Title Case with "Medium" instead of "Moderate":
/// Critical/High/Medium/Low. Inserting the ML API's own raw casing
/// ("CRITICAL", "MODERATE", …) fails with Postgres error 22P02 ("invalid
/// input value for enum risk_level") — which is why `risk_assessments` was
/// completely empty despite every analysis appearing to succeed on screen:
/// `_persistSingle`/`_persistBatch` in GuidanceCounselorConnectedPage catch
/// and only `debugPrint` this failure, so it never surfaced as a visible
/// error, and every Overview/Early-Warning/ML-Overview stat reading from
/// an empty table correctly showed zero.
String _toDbRiskLevel(String raw) {
  final upper = raw.trim().toUpperCase();
  return switch (upper) {
    'CRITICAL' => 'Critical',
    'HIGH' => 'High',
    'MODERATE' || 'MEDIUM' => 'Medium',
    'LOW' => 'Low',
    _ => 'Low',
  };
}

class GuidanceCounselorRepositoryException implements Exception {
  GuidanceCounselorRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GuidanceCounselorOverviewData {
  const GuidanceCounselorOverviewData({
    required this.metrics,
    required this.riskDistribution,
    required this.approvalQueue,
  });

  final GuidanceCounselorMetricsModel metrics;
  final RiskDistributionModel riskDistribution;
  final List<StudentRiskQueueItemModel> approvalQueue;
}

/// Reads/writes `public.risk_assessments` — the write-through store for
/// results from the standalone ML service (see `lib/data/ml_risk_repository.dart`
/// and `Behavioral AI Model/API_CONTRACT.md`) that backs the Guidance
/// Counselor dashboard's Overview tab.
class GuidanceCounselorRepository {
  GuidanceCounselorRepository(this._client);

  final SupabaseClient _client;

  static const _studentEmbed = '''
student_number,
profiles ( first_name, last_name ),
sections ( name )
''';

  /// `students.student_number` -> `students.id`, for resolving a
  /// counselor-typed or roster-uploaded Student ID to the FK
  /// `risk_assessments.student_id` expects. Loaded once per dashboard
  /// session rather than per analysis.
  Future<Map<String, String>> fetchStudentIdsByNumber() async {
    final rows =
        await _client.from('students').select('id, student_number');
    final map = <String, String>{};
    for (final raw in rows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final number = row['student_number'] as String?;
      final id = row['id'] as String?;
      if (number != null && id != null) map[number] = id;
    }
    return map;
  }

  /// Every currently enrolled student, each with the same real attendance/
  /// GPA/violation aggregates [fetchStudentRiskAutofill] computes for one
  /// student at a time — backs the Batch Student Analysis tab's "Load Live
  /// Roster" action (an alternative to uploading an external CSV; see
  /// [BatchStudentRecordModel]'s own doc comment on why its GPA/violation
  /// fields are only ever populated from this path).
  ///
  /// Skips a student with zero attendance records on file entirely (not as
  /// an error): `/predict/batch` rejects the *whole* batch if any one
  /// record's `total_classes` is 0, and there's nothing to score yet for a
  /// student with no attendance history regardless.
  ///
  /// Runs 4 bulk queries (students, attendance, GPA, violations) and
  /// aggregates client-side rather than one round-trip per student —
  /// there's no per-student filtering support worth adding here just to
  /// avoid it, and this matches how every other multi-student report in
  /// this codebase (e.g. RegistrarRepository.fetchGradeRecords) already
  /// merges related tables.
  Future<List<BatchStudentRecordModel>> fetchAllStudentsForBatchAnalysis() async {
    final studentRows = await _client
        .from('students')
        .select('id, student_number, course');
    final students = studentRows as List<dynamic>;
    if (students.isEmpty) return const [];

    final attendanceRows = await _client
        .from('attendance_records')
        .select('student_id, status, session_date')
        .order('session_date', ascending: true);
    final attendanceByStudent = <String, List<Map<String, dynamic>>>{};
    for (final raw in attendanceRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final id = row['student_id'] as String;
      (attendanceByStudent[id] ??= []).add(row);
    }

    final gpaRows = await _client
        .from('student_gpa_records')
        .select('student_id, cumulative_gpa, failed_courses_count, created_at')
        .order('created_at', ascending: false);
    final gpaByStudent = <String, List<Map<String, dynamic>>>{};
    for (final raw in gpaRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final id = row['student_id'] as String;
      // Already ordered newest-first by the query above, so index 0/1 per
      // student below are current/previous without re-sorting per group.
      (gpaByStudent[id] ??= []).add(row);
    }

    final violationRows = await _client
        .from('student_violations')
        .select('student_id, created_at, handbook_offenses ( category )')
        .filter('archived_at', 'is', null);
    final violationsByStudent = <String, List<Map<String, dynamic>>>{};
    for (final raw in violationRows as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      final id = row['student_id'] as String;
      (violationsByStudent[id] ??= []).add(row);
    }

    final records = <BatchStudentRecordModel>[];
    for (final raw in students) {
      final row = raw as Map<String, dynamic>;
      final id = row['id'] as String;
      final number = row['student_number'] as String?;
      if (number == null || number.isEmpty) continue;

      final attendanceForStudent = attendanceByStudent[id] ?? const [];
      final attendance = _summarizeAttendance(attendanceForStudent);
      if (attendance.totalClasses == 0) continue;

      final gpaList = gpaByStudent[id] ?? const [];
      final rawCurrentGpa =
          gpaList.isEmpty ? null : (gpaList[0]['cumulative_gpa'] as num?)?.toDouble();
      final rawPreviousGpa = gpaList.length < 2
          ? rawCurrentGpa
          : (gpaList[1]['cumulative_gpa'] as num?)?.toDouble();
      // See gwaToPercentage's own doc comment — converts the stored
      // Philippine 1.00-5.00 scale to the 0-100 percentage the ML service
      // was actually trained on. Null (no GPA on file yet) stays
      // unconverted/unsent — see BatchStudentRecordModel's own doc comment.
      final currentGpa =
          rawCurrentGpa == null ? null : gwaToPercentage(rawCurrentGpa);
      final previousGpa =
          rawPreviousGpa == null ? null : gwaToPercentage(rawPreviousGpa);
      final failingCourses = gpaList.isEmpty
          ? null
          : (gpaList[0]['failed_courses_count'] as num?)?.toInt();

      final violations = _summarizeViolations(violationsByStudent[id] ?? const []);

      records.add(BatchStudentRecordModel(
        studentId: number,
        program: row['course'] as String? ?? '',
        totalClasses: attendance.totalClasses,
        totalAbsences: attendance.totalAbsences,
        maxStreak: attendance.maxConsecutiveAbsences,
        weeklyAbsences: _weeklyAbsenceCount(attendanceForStudent),
        dailyAttendance30D: _dailyAttendance30D(attendanceForStudent),
        absenceTrend: attendance.trend,
        recoveryScore: attendance.recoveryScore,
        currentGpa: currentGpa,
        previousGpa: previousGpa,
        failingCourses: failingCourses,
        minorCount: violations.minor,
        majorACount: violations.majorA,
        majorBCount: violations.majorB,
        majorCCount: violations.majorC,
        majorDCount: violations.majorD,
        daysSinceLastViolation: violations.daysSinceLastViolation,
      ));
    }
    return records;
  }

  int _weeklyAbsenceCount(List<Map<String, dynamic>> rows) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return rows.where((row) {
      final date = DateTime.tryParse(row['session_date'] as String? ?? '');
      return date != null &&
          date.isAfter(cutoff) &&
          row['status'] == 'Absent';
    }).length;
  }

  /// e.g. "27/30" — matches [BatchStudentRecordModel.dailyAttendance30D]'s
  /// own "days present out of the last 30" format, computed here instead of
  /// trusting an uploaded roster column since there is none on this path.
  String _dailyAttendance30D(List<Map<String, dynamic>> rows) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recent = rows.where((row) {
      final date = DateTime.tryParse(row['session_date'] as String? ?? '');
      return date != null && date.isAfter(cutoff);
    }).toList();
    if (recent.isEmpty) return '0/0';
    final present = recent.where((row) => row['status'] != 'Absent').length;
    return '$present/${recent.length}';
  }

  Future<GuidanceCounselorOverviewData> fetchOverview() async {
    final totalStudentsResponse =
        await _client.from('students').select('id').count(CountOption.exact);
    final totalStudents = totalStudentsResponse.count;

    final levelRows =
        await _client.from('risk_assessments').select('risk_level');

    var critical = 0, high = 0, moderate = 0, low = 0;
    for (final raw in levelRows as List<dynamic>) {
      final level =
          ((raw as Map<String, dynamic>)['risk_level'] as String? ?? '')
              .toUpperCase();
      switch (level) {
        case 'CRITICAL':
          critical++;
        case 'HIGH':
          high++;
        case 'MEDIUM':
          moderate++;
        default:
          low++;
      }
    }
    final atRisk = critical + high;

    final queueRows = await _client
        .from('risk_assessments')
        .select('''
id,
dropout_probability,
students ( $_studentEmbed )
''')
        .eq('reviewed', false)
        .order('computed_at', ascending: true);

    final approvalQueue = (queueRows as List<dynamic>).map((raw) {
      final row = raw as Map<String, dynamic>;
      final student = row['students'] as Map<String, dynamic>?;
      final studentProfile = student?['profiles'] as Map<String, dynamic>?;
      final section = student?['sections'] as Map<String, dynamic>?;
      final name = _fullName(
        studentProfile?['first_name'] as String?,
        studentProfile?['last_name'] as String?,
      );

      return StudentRiskQueueItemModel(
        id: row['id'] as String,
        studentName: name.isEmpty ? 'Unknown student' : name,
        courseSection: section?['name'] as String? ?? '',
        studentId: student?['student_number'] as String? ?? '',
        riskPercent: ((row['dropout_probability'] as num?)?.toDouble() ?? 0) * 100,
      );
    }).toList();

    return GuidanceCounselorOverviewData(
      metrics: GuidanceCounselorMetricsModel(
        totalStudents: totalStudents,
        atRiskTrainingDataCount: atRisk,
        dropoutRatePercent:
            totalStudents == 0 ? 0.0 : (atRisk / totalStudents * 100),
      ),
      // The donut's own labels (No decline/Severe/Moderate/Mild) are a
      // separate 4-tier scheme from risk_level's CRITICAL/HIGH/MODERATE/LOW
      // — this is the most literal reading of that pre-existing mismatch,
      // not a new inconsistency introduced here.
      riskDistribution: RiskDistributionModel(
        noDecline: low,
        severe: critical,
        moderate: high,
        mild: moderate,
      ),
      approvalQueue: approvalQueue,
    );
  }

  Future<void> insertRiskAssessment({
    required String studentId,
    required RiskAnalysisResultModel result,
  }) async {
    try {
      await _client.from('risk_assessments').insert({
        'student_id': studentId,
        'dropout_probability': result.dropoutRiskPercentage / 100,
        'risk_level': _toDbRiskLevel(result.riskStatus),
        'confidence': result.confidencePercent / 100,
        'risk_reasoning': result.riskReasoningFactors.isEmpty
            ? null
            : result.riskReasoningFactors.map((f) => f.factor).join(' + '),
        'key_factors': result.riskReasoningFactors
            .map((f) => {
                  'factor': f.factor,
                  'value': f.value,
                  'severity': f.severity,
                })
            .toList(),
        'recommendations': result.recommendedInterventions,
      });
    } on PostgrestException catch (e) {
      throw GuidanceCounselorRepositoryException(e.message);
    }
  }

  Future<void> insertBatchRiskAssessment({
    required String studentId,
    required BatchAnalysisResultModel result,
  }) async {
    try {
      await _client.from('risk_assessments').insert({
        'student_id': studentId,
        'dropout_probability': result.dropoutProbabilityPercent / 100,
        'risk_level': _toDbRiskLevel(result.riskLevel),
        'risk_reasoning': result.riskReasoning,
        'early_warning_30d': result.earlyWarning30D == 'Flagged',
      });
    } on PostgrestException catch (e) {
      throw GuidanceCounselorRepositoryException(e.message);
    }
  }

  /// Called when a queue slip is tapped in the Approval Queue — marks it
  /// reviewed so it drops out of the (`reviewed = false`) queue query.
  Future<void> markReviewed(String assessmentId) async {
    try {
      await _client
          .from('risk_assessments')
          .update({'reviewed': true}).eq('id', assessmentId);
    } on PostgrestException catch (e) {
      throw GuidanceCounselorRepositoryException(e.message);
    }
  }

  String _fullName(String? first, String? last) {
    return '${(first ?? '').trim()} ${(last ?? '').trim()}'.trim();
  }

  /// Real attendance/GPA/violation aggregates for one student, backing the
  /// Single Student Analysis form's "look up by Student ID" auto-fill —
  /// see StudentRiskAutofillModel's own doc comment for what each field
  /// maps to. [studentId] is the resolved `students.id` (uuid), not the
  /// human-readable student number — callers resolve that first via
  /// [fetchStudentIdsByNumber].
  Future<StudentRiskAutofillModel> fetchStudentRiskAutofill(
    String studentId,
  ) async {
    final gpaRows = await _client
        .from('student_gpa_records')
        .select('cumulative_gpa, failed_courses_count')
        .eq('student_id', studentId)
        .order('created_at', ascending: false)
        .limit(2);
    final gpaList = gpaRows as List<dynamic>;
    final latestGpa =
        gpaList.isEmpty ? null : gpaList[0] as Map<String, dynamic>;
    final previousGpaRow =
        gpaList.length < 2 ? null : gpaList[1] as Map<String, dynamic>;
    final rawCurrentGpa = (latestGpa?['cumulative_gpa'] as num?)?.toDouble();
    // No older term on file yet — treat as "no change" (0% decline) rather
    // than comparing against a fabricated 0.0, which would read as a huge,
    // fictitious GPA collapse.
    final rawPreviousGpa =
        (previousGpaRow?['cumulative_gpa'] as num?)?.toDouble() ?? rawCurrentGpa;
    // See gwaToPercentage's own doc comment — the ML service expects a
    // 0-100 percentage, not the Philippine 1.00-5.00 scale these are
    // stored on. "No GPA on file yet" stays 0.0 (this feature's existing
    // "no data" sentinel), not a converted value.
    final currentGpa =
        rawCurrentGpa == null ? 0.0 : gwaToPercentage(rawCurrentGpa);
    final previousGpa =
        rawPreviousGpa == null ? 0.0 : gwaToPercentage(rawPreviousGpa);
    final failingCourses =
        (latestGpa?['failed_courses_count'] as num?)?.toInt() ?? 0;

    final attendanceRows = await _client
        .from('attendance_records')
        .select('status, session_date')
        .eq('student_id', studentId)
        .order('session_date', ascending: true);
    final attendance = _summarizeAttendance(attendanceRows as List<dynamic>);

    final violationRows = await _client
        .from('student_violations')
        .select('created_at, handbook_offenses ( category )')
        .eq('student_id', studentId)
        .filter('archived_at', 'is', null);
    final violations = _summarizeViolations(violationRows as List<dynamic>);

    return StudentRiskAutofillModel(
      currentGpa: currentGpa,
      previousGpa: previousGpa,
      totalClasses: attendance.totalClasses,
      totalAbsences: attendance.totalAbsences,
      failingCourses: failingCourses,
      maxConsecutiveAbsences: attendance.maxConsecutiveAbsences,
      daysSinceLastViolation: violations.daysSinceLastViolation,
      recoveryScore: attendance.recoveryScore,
      recentAttendanceTrend: attendance.trend,
      minorCount: violations.minor,
      majorACount: violations.majorA,
      majorBCount: violations.majorB,
      majorCCount: violations.majorC,
      majorDCount: violations.majorD,
    );
  }

  ({
    int totalClasses,
    int totalAbsences,
    int maxConsecutiveAbsences,
    double recoveryScore,
    AttendanceTrend trend,
  }) _summarizeAttendance(List<dynamic> rows) {
    final statuses = [
      for (final raw in rows) (raw as Map<String, dynamic>)['status'] as String,
    ];
    final totalClasses = statuses.length;
    final totalAbsences = statuses.where((s) => s == 'Absent').length;

    var maxStreak = 0;
    var currentStreak = 0;
    var streakEndIndex = -1;
    for (var i = 0; i < statuses.length; i++) {
      if (statuses[i] == 'Absent') {
        currentStreak++;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
          streakEndIndex = i;
        }
      } else {
        currentStreak = 0;
      }
    }

    // How well the student rebounds right after their longest absence
    // streak — the fraction of the next few sessions actually attended.
    // Defaults to a neutral 0.5 (matching the ML API's own default for
    // this field) when there's no streak, or no sessions recorded after
    // one, to score from.
    var recoveryScore = 0.5;
    if (maxStreak > 0 && streakEndIndex < statuses.length - 1) {
      final followUp = statuses.sublist(
        streakEndIndex + 1,
        (streakEndIndex + 1 + 5).clamp(0, statuses.length),
      );
      if (followUp.isNotEmpty) {
        final attended = followUp.where((s) => s != 'Absent').length;
        recoveryScore = attended / followUp.length;
      }
    }

    // Compares the most recent ~15 sessions' absence rate against the ~15
    // before that. "Increasing"/"decreasing" describe the ABSENCE trend
    // (matching this file's own demo calculator, where an "increasing"
    // trend raises computed risk) — not attendance quality improving.
    var trend = AttendanceTrend.stable;
    if (statuses.length >= 4) {
      const window = 15;
      final recent = statuses.sublist(
        (statuses.length - window).clamp(0, statuses.length),
      );
      final priorEnd = (statuses.length - window).clamp(0, statuses.length);
      final priorStart = (priorEnd - window).clamp(0, priorEnd);
      final prior = statuses.sublist(priorStart, priorEnd);

      if (prior.isNotEmpty) {
        final recentRate =
            recent.where((s) => s == 'Absent').length / recent.length;
        final priorRate =
            prior.where((s) => s == 'Absent').length / prior.length;
        const threshold = 0.1;
        if (recentRate - priorRate > threshold) {
          trend = AttendanceTrend.increasing;
        } else if (priorRate - recentRate > threshold) {
          trend = AttendanceTrend.decreasing;
        }
      }
    }

    return (
      totalClasses: totalClasses,
      totalAbsences: totalAbsences,
      maxConsecutiveAbsences: maxStreak,
      recoveryScore: recoveryScore,
      trend: trend,
    );
  }

  ({
    int minor,
    int majorA,
    int majorB,
    int majorC,
    int majorD,
    int daysSinceLastViolation,
  }) _summarizeViolations(List<dynamic> rows) {
    var minor = 0, majorA = 0, majorB = 0, majorC = 0, majorD = 0;
    DateTime? mostRecent;

    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final offense = row['handbook_offenses'] as Map<String, dynamic>?;
      switch (offense?['category'] as String?) {
        case 'Minor':
          minor++;
        case 'Major_A':
          majorA++;
        case 'Major_B':
          majorB++;
        case 'Major_C':
          majorC++;
        case 'Major_D':
          majorD++;
      }
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (createdAt != null &&
          (mostRecent == null || createdAt.isAfter(mostRecent))) {
        mostRecent = createdAt;
      }
    }

    // Matches the ML API's own default (999) for "no violations on file" —
    // effectively "not a recent factor" rather than a fabricated recency.
    final daysSince =
        mostRecent == null ? 999 : DateTime.now().difference(mostRecent).inDays;

    return (
      minor: minor,
      majorA: majorA,
      majorB: majorB,
      majorC: majorC,
      majorD: majorD,
      daysSinceLastViolation: daysSince,
    );
  }

  /// What the "Request Parent Intervention" dialog needs to suggest a
  /// message: the student's name, recent conduct record and whether their
  /// guardian can actually be texted. Null when no student has this number.
  Future<ParentInterventionContext?> fetchParentInterventionContext(
    String studentNumber, {
    int windowDays = 30,
  }) async {
    try {
      final student = await _client
          .from('students')
          .select('id, guardian_contact_no, profiles ( first_name, last_name )')
          .eq('student_number', studentNumber.trim())
          .maybeSingle();
      if (student == null) return null;

      final studentId = student['id'] as String;
      final profile = student['profiles'] as Map<String, dynamic>?;
      final since = DateTime.now()
          .toUtc()
          .subtract(Duration(days: windowDays))
          .toIso8601String();
      final rows = await _client
          .from('student_violations')
          .select('handbook_offenses ( category )')
          .eq('student_id', studentId)
          .filter('archived_at', 'is', null)
          .gte('created_at', since);

      var count = 0;
      var hasMajor = false;
      for (final raw in rows as List<dynamic>) {
        count++;
        final offense =
            (raw as Map<String, dynamic>)['handbook_offenses'] as Map<String, dynamic>?;
        final category = offense?['category'] as String?;
        if (category != null && category != 'Minor') hasMajor = true;
      }

      final name =
          _fullName(profile?['first_name'] as String?, profile?['last_name'] as String?);
      return ParentInterventionContext(
        studentId: studentId,
        studentName: name.isEmpty ? 'Your child' : name,
        violationCount: count,
        hasMajorViolation: hasMajor,
        windowDays: windowDays,
        guardianReachable:
            isValidPhMobile(student['guardian_contact_no'] as String?),
      );
    } on PostgrestException catch (e) {
      throw GuidanceCounselorRepositoryException(e.message);
    }
  }

  /// Writes the `parent_interventions` row. A database trigger
  /// (`supabase/add_sms_alerts_schema.sql`) queues the SMS from it, so the
  /// Parent Portal message and the text always carry the same wording.
  Future<void> insertParentIntervention({
    required String studentId,
    required String message,
    required String sentBy,
  }) async {
    try {
      await _client.from('parent_interventions').insert({
        'student_id': studentId,
        'title': 'Parent conference requested',
        'message': message,
        'kind': 'conduct',
        'sent_by': sentBy,
        'action_required': true,
      });
    } on PostgrestException catch (e) {
      throw GuidanceCounselorRepositoryException(e.message);
    }
  }
}

class ParentInterventionContext {
  const ParentInterventionContext({
    required this.studentId,
    required this.studentName,
    required this.violationCount,
    required this.hasMajorViolation,
    required this.windowDays,
    required this.guardianReachable,
  });

  final String studentId;
  final String studentName;
  final int violationCount;
  final bool hasMajorViolation;
  final int windowDays;

  /// False when `students.guardian_contact_no` is empty or not a PH mobile
  /// number — the intervention still reaches the Parent Portal, but no SMS
  /// can be sent.
  final bool guardianReachable;
}

/// Same acceptance rule as `normalize_ph_mobile` in
/// `supabase/add_sms_alerts_schema.sql`: 09XXXXXXXXX, 9XXXXXXXXX or
/// 639XXXXXXXXX, ignoring spaces, dashes and a leading '+'.
bool isValidPhMobile(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return RegExp(r'^(639\d{9}|09\d{9}|9\d{9})$').hasMatch(digits);
}
