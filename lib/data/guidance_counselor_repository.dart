import 'package:guidance_counselor_module/pages/batch_student_analysis/batch_student_analysis_view.dart';
import 'package:guidance_counselor_module/pages/dashboard/guidance_counselor_dashboard_page.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        case 'MODERATE':
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
        'risk_level': result.riskStatus,
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
        'risk_level': result.riskLevel.toUpperCase(),
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
}
