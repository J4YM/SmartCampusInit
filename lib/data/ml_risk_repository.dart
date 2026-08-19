import 'dart:convert';

import 'package:guidance_counselor_module/pages/batch_student_analysis/batch_student_analysis_view.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';
import 'package:http/http.dart' as http;

/// `logistic_regression` -> "Logistic Regression", with SVM/XGBoost's own
/// display casing — shared by every dashboard that renders
/// [MlModelInfo.metrics] (Guidance Counselor's Overview tab, Admin's ML &
/// Thresholds page).
String titleCaseMlModelName(String key) {
  switch (key) {
    case 'svm':
      return 'SVM';
    case 'xgboost':
      return 'XG Boost';
    default:
      return key
          .split('_')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
  }
}

class MlRiskRepositoryException implements Exception {
  MlRiskRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Per-model metrics from the deployed model's training manifest (`GET
/// /model-info` — see `Behavioral AI Model/models/trained/model_manifest.json`).
/// Backs the Guidance Counselor Overview's "Trained Model Comparison" chart.
class MlModelInfo {
  const MlModelInfo({required this.bestModel, required this.metrics});

  final String? bestModel;

  /// model name (e.g. "logistic_regression") -> {roc_auc, pr_auc, recall, f1, ...}.
  final Map<String, Map<String, double>> metrics;
}

/// Talks to the standalone dropout-risk FastAPI service documented in
/// `Behavioral AI Model/API_CONTRACT.md`. That service holds no Supabase
/// credentials of its own — this repository is the caller responsible for
/// supplying per-student aggregates and (separately, see
/// `GuidanceCounselorConnectedPage`) persisting whatever it returns.
class MlRiskRepository {
  MlRiskRepository(String baseUrl, {http.Client? client})
      : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<RiskAnalysisResultModel> predictSingle(
    StudentRiskInputModel input,
  ) async {
    final body =
        await _post('/predict', _singleToPayload(input)) as Map<String, dynamic>;
    return _toRiskAnalysis(input: input, body: body);
  }

  Future<List<BatchAnalysisResultModel>> predictBatch(
    List<BatchStudentRecordModel> records,
  ) async {
    if (records.isEmpty) return const [];
    final body = await _post(
      '/predict/batch',
      records.map(_batchRecordToPayload).toList(),
    ) as List<dynamic>;

    return [
      for (var i = 0; i < body.length && i < records.length; i++)
        _toBatchResult(
          record: records[i],
          body: body[i] as Map<String, dynamic>,
        ),
    ];
  }

  Future<MlModelInfo> fetchModelInfo() async {
    final body = await _get('/model-info') as Map<String, dynamic>;
    final rawMetrics = body['metrics'] as Map<String, dynamic>? ?? const {};
    return MlModelInfo(
      bestModel: body['best_model'] as String?,
      metrics: {
        for (final entry in rawMetrics.entries)
          entry.key: (entry.value as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
      },
    );
  }

  // ---------------------------------------------------------------------
  // Request payloads — field mapping documented in API_CONTRACT.md.
  // ---------------------------------------------------------------------

  Map<String, dynamic> _singleToPayload(StudentRiskInputModel input) {
    return {
      'student_id': input.studentId.isEmpty ? 'UNKNOWN' : input.studentId,
      'total_classes': input.totalClasses,
      'total_absences': input.totalAbsences,
      'max_streak': input.maxConsecutiveAbsences,
      'recovery_score': input.recoveryScore,
      'current_gwa': input.currentGpa,
      'previous_gwa': input.previousGpa,
      'failing_count': input.failingCourses,
      'minor_violation_count': input.minorCount,
      'major_a_violation_count': input.majorACount,
      'major_b_violation_count': input.majorBCount,
      'major_c_violation_count': input.majorCCount,
      'major_d_violation_count': input.majorDCount,
      'days_since_last_violation': input.daysSinceLastViolation,
    };
  }

  /// The uploaded roster CSV has no GWA/violation columns and only a
  /// single-week absence count (not the API's full-semester weekly series
  /// or 30-day daily array) — those fields go unsent, matching the CSV
  /// format's own limits rather than fabricating data it doesn't have.
  Map<String, dynamic> _batchRecordToPayload(BatchStudentRecordModel record) {
    return {
      'student_id': record.studentId.isEmpty ? 'UNKNOWN' : record.studentId,
      'total_classes': record.totalClasses,
      'total_absences': record.totalAbsences,
      'max_streak': record.maxStreak,
      'recovery_score': record.recoveryScore,
    };
  }

  // ---------------------------------------------------------------------
  // Response mapping.
  // ---------------------------------------------------------------------

  RiskAnalysisResultModel _toRiskAnalysis({
    required StudentRiskInputModel input,
    required Map<String, dynamic> body,
  }) {
    final probabilityPercent =
        ((body['dropout_probability'] as num).toDouble()) * 100;
    final confidencePercent =
        ((body['confidence'] as num?)?.toDouble() ?? 0) * 100;
    final trend = body['attendance_trend_30d'] as Map<String, dynamic>?;
    final thirtyDayAbsenceRatePercent =
        ((trend?['absence_rate_30d'] as num?)?.toDouble() ?? 0) * 100;

    // Computed from the known request input rather than the response — the
    // API doesn't echo these back, but they're exact from what was sent.
    final absenceRatePercent = input.totalClasses > 0
        ? (input.totalAbsences / input.totalClasses * 100).clamp(0.0, 100.0)
        : 0.0;
    final gpaDeclinePercent = input.previousGpa > 0
        ? ((input.previousGpa - input.currentGpa) / input.previousGpa * 100)
            .clamp(0.0, 100.0)
        : 0.0;

    return RiskAnalysisResultModel(
      dropoutRiskPercentage: probabilityPercent,
      riskStatus: body['risk_level'] as String? ?? 'Invalid',
      riskProbabilityPercent: probabilityPercent,
      confidencePercent: confidencePercent,
      absenceRatePercent: absenceRatePercent,
      thirtyDayAbsenceRatePercent: thirtyDayAbsenceRatePercent,
      gpaDeclinePercent: gpaDeclinePercent,
      riskReasoningFactors: _keyFactorsToReasoning(body['key_factors']),
      recommendedInterventions:
          (body['recommendations'] as List<dynamic>? ?? const [])
              .map((e) => e as String)
              .toList(),
    );
  }

  List<RiskReasoningFactorModel> _keyFactorsToReasoning(dynamic raw) {
    final list = raw as List<dynamic>? ?? const [];
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      final value = (map['value'] as num).toDouble();
      return RiskReasoningFactorModel(
        factor: map['factor'] as String,
        value: value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(3),
        severity: map['severity'] as String,
      );
    }).toList();
  }

  BatchAnalysisResultModel _toBatchResult({
    required BatchStudentRecordModel record,
    required Map<String, dynamic> body,
  }) {
    final probabilityPercent =
        ((body['dropout_probability'] as num).toDouble()) * 100;
    final keyFactorLabels = (body['key_factors'] as List<dynamic>? ?? const [])
        .map((e) => (e as Map<String, dynamic>)['factor'] as String)
        .toList();
    final reasoning = keyFactorLabels.isNotEmpty
        ? keyFactorLabels.join(', ')
        : (body['risk_reasoning'] as String? ?? '');

    return BatchAnalysisResultModel(
      studentId: record.studentId,
      dropoutProbabilityPercent: probabilityPercent,
      riskLevel: _titleCase(body['risk_level'] as String? ?? 'LOW'),
      riskReasoning: reasoning,
      earlyWarning30D: body['early_warning_30d'] == true ? 'Flagged' : 'None',
    );
  }

  /// The API returns CRITICAL/HIGH/MODERATE/LOW; [BatchAnalysisResultModel]
  /// (unlike the single-analysis model) expects Critical/High/Moderate/Low
  /// — see `_riskLevelTint` in batch_student_analysis_view.dart.
  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  // ---------------------------------------------------------------------
  // HTTP plumbing.
  // ---------------------------------------------------------------------

  Future<dynamic> _get(String path) async {
    final http.Response response;
    try {
      response = await _client.get(_uri(path));
    } catch (e) {
      throw MlRiskRepositoryException('Could not reach the ML service: $e');
    }
    return _decode(response);
  }

  Future<dynamic> _post(String path, Object body) async {
    final http.Response response;
    try {
      response = await _client.post(
        _uri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw MlRiskRepositoryException('Could not reach the ML service: $e');
    }
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MlRiskRepositoryException(
        'ML service returned ${response.statusCode}: ${response.body}',
      );
    }
    return jsonDecode(response.body);
  }
}
