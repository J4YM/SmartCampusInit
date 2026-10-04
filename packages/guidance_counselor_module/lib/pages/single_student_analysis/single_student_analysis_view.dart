import 'dart:async';
import 'dart:math' as math;

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase-ready. fromJson()/toJson() map onto snake_case
// Postgres columns so a real ML scoring service can be swapped in for
// [SingleStudentAnalysisView.onAnalyze] without touching the UI.
// ---------------------------------------------------------------------------

enum AttendanceTrend { increasing, decreasing, stable }

extension AttendanceTrendLabel on AttendanceTrend {
  String get label => switch (this) {
        AttendanceTrend.increasing => 'Increasing',
        AttendanceTrend.decreasing => 'Decreasing',
        AttendanceTrend.stable => 'Stable',
      };

  static AttendanceTrend fromLabel(String label) {
    return AttendanceTrend.values.firstWhere(
      (t) => t.label == label,
      orElse: () => AttendanceTrend.stable,
    );
  }
}

/// Every input on the "Student Risk Parameters" form, snapshotted when
/// "Analyze Risk" is pressed.
class StudentRiskInputModel {
  const StudentRiskInputModel({
    required this.studentId,
    required this.currentGpa,
    required this.previousGpa,
    required this.totalClasses,
    required this.totalAbsences,
    required this.failingCourses,
    required this.maxConsecutiveAbsences,
    required this.daysSinceLastViolation,
    required this.recoveryScore,
    required this.recentAttendanceTrend,
    required this.minorCount,
    required this.majorACount,
    required this.majorBCount,
    required this.majorCCount,
    required this.majorDCount,
  });

  final String studentId;
  final double currentGpa;
  final double previousGpa;
  final int totalClasses;
  final int totalAbsences;
  final int failingCourses;
  final int maxConsecutiveAbsences;
  final int daysSinceLastViolation;

  /// 0.0–1.0.
  final double recoveryScore;
  final AttendanceTrend recentAttendanceTrend;

  final int minorCount;
  final int majorACount;
  final int majorBCount;
  final int majorCCount;
  final int majorDCount;

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'current_gpa': currentGpa,
      'previous_gpa': previousGpa,
      'total_classes': totalClasses,
      'total_absences': totalAbsences,
      'failing_courses': failingCourses,
      'max_consecutive_absences': maxConsecutiveAbsences,
      'days_since_last_violation': daysSinceLastViolation,
      'recovery_score': recoveryScore,
      'recent_attendance_trend': recentAttendanceTrend.name,
      'minor_count': minorCount,
      'major_a_count': majorACount,
      'major_b_count': majorBCount,
      'major_c_count': majorCCount,
      'major_d_count': majorDCount,
    };
  }
}

/// Real per-student aggregates fetched when the counselor enters a Student
/// ID and submits it — see [SingleStudentAnalysisView.onLookupStudent].
/// Prefills every field on the form except [StudentRiskInputModel.studentId]
/// itself (already known — it's what was just looked up).
class StudentRiskAutofillModel {
  const StudentRiskAutofillModel({
    required this.currentGpa,
    required this.previousGpa,
    required this.totalClasses,
    required this.totalAbsences,
    required this.failingCourses,
    required this.maxConsecutiveAbsences,
    required this.daysSinceLastViolation,
    required this.recoveryScore,
    required this.recentAttendanceTrend,
    required this.minorCount,
    required this.majorACount,
    required this.majorBCount,
    required this.majorCCount,
    required this.majorDCount,
  });

  final double currentGpa;
  final double previousGpa;
  final int totalClasses;
  final int totalAbsences;
  final int failingCourses;
  final int maxConsecutiveAbsences;
  final int daysSinceLastViolation;
  final double recoveryScore;
  final AttendanceTrend recentAttendanceTrend;
  final int minorCount;
  final int majorACount;
  final int majorBCount;
  final int majorCCount;
  final int majorDCount;
}

/// One row in the "Risk Reasoning" table.
class RiskReasoningFactorModel {
  const RiskReasoningFactorModel({
    required this.factor,
    required this.value,
    required this.severity,
  });

  final String factor;
  final String value;

  /// "HIGH", "MODERATE", or "LOW".
  final String severity;

  factory RiskReasoningFactorModel.fromJson(Map<String, dynamic> json) {
    return RiskReasoningFactorModel(
      factor: json['factor'] as String,
      value: json['value'] as String,
      severity: json['severity'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'factor': factor, 'value': value, 'severity': severity};
  }
}

/// Everything the right-hand gauge/assessment panel renders, returned by
/// [SingleStudentAnalysisView.onAnalyze] (or the built-in demo calculator
/// when that's omitted).
class RiskAnalysisResultModel {
  const RiskAnalysisResultModel({
    required this.dropoutRiskPercentage,
    required this.riskStatus,
    required this.riskProbabilityPercent,
    required this.confidencePercent,
    required this.absenceRatePercent,
    required this.thirtyDayAbsenceRatePercent,
    required this.gpaDeclinePercent,
    required this.riskReasoningFactors,
    required this.recommendedInterventions,
  });

  /// The neutral, pre-analysis state — shown until "Analyze Risk" runs once.
  factory RiskAnalysisResultModel.initial() {
    return const RiskAnalysisResultModel(
      dropoutRiskPercentage: 0,
      riskStatus: 'Invalid',
      riskProbabilityPercent: 0,
      confidencePercent: 0,
      absenceRatePercent: 0,
      thirtyDayAbsenceRatePercent: 0,
      gpaDeclinePercent: 0,
      riskReasoningFactors: [],
      recommendedInterventions: [],
    );
  }

  /// 0–100, drives the gauge.
  final double dropoutRiskPercentage;

  /// "CRITICAL", "HIGH", "MODERATE", "LOW", or "Invalid" (untested/pending).
  final String riskStatus;

  final double riskProbabilityPercent;
  final double confidencePercent;
  final double absenceRatePercent;
  final double thirtyDayAbsenceRatePercent;
  final double gpaDeclinePercent;

  final List<RiskReasoningFactorModel> riskReasoningFactors;
  final List<String> recommendedInterventions;

  factory RiskAnalysisResultModel.fromJson(Map<String, dynamic> json) {
    return RiskAnalysisResultModel(
      dropoutRiskPercentage:
          (json['dropout_risk_percentage'] as num?)?.toDouble() ?? 0.0,
      riskStatus: json['risk_status'] as String? ?? 'Invalid',
      riskProbabilityPercent:
          (json['risk_probability_percent'] as num?)?.toDouble() ?? 0.0,
      confidencePercent:
          (json['confidence_percent'] as num?)?.toDouble() ?? 0.0,
      absenceRatePercent:
          (json['absence_rate_percent'] as num?)?.toDouble() ?? 0.0,
      thirtyDayAbsenceRatePercent:
          (json['thirty_day_absence_rate_percent'] as num?)?.toDouble() ?? 0.0,
      gpaDeclinePercent:
          (json['gpa_decline_percent'] as num?)?.toDouble() ?? 0.0,
      riskReasoningFactors:
          (json['risk_reasoning_factors'] as List? ?? const [])
              .map((e) =>
                  RiskReasoningFactorModel.fromJson(e as Map<String, dynamic>))
              .toList(),
      recommendedInterventions:
          (json['recommended_interventions'] as List? ?? const [])
              .map((e) => e as String)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dropout_risk_percentage': dropoutRiskPercentage,
      'risk_status': riskStatus,
      'risk_probability_percent': riskProbabilityPercent,
      'confidence_percent': confidencePercent,
      'absence_rate_percent': absenceRatePercent,
      'thirty_day_absence_rate_percent': thirtyDayAbsenceRatePercent,
      'gpa_decline_percent': gpaDeclinePercent,
      'risk_reasoning_factors':
          riskReasoningFactors.map((f) => f.toJson()).toList(),
      'recommended_interventions': recommendedInterventions,
    };
  }
}

// ---------------------------------------------------------------------------
// Demo scoring — a placeholder used whenever the host app doesn't supply
// `onAnalyze`. The real dropout-risk model (weights, thresholds, STI
// Handbook violation scoring) lives in the ML service this eventually calls;
// nothing here should be treated as the source of truth for those numbers.
// ---------------------------------------------------------------------------

/// Placeholder escalation weights standing in for the real STI Handbook
/// violation-severity scoring until that service is wired up.
const _violationWeights = {
  'minor': 1.0,
  'majorA': 3.0,
  'majorB': 5.0,
  'majorC': 7.0,
  'majorD': 10.0,
};

double _clampPercent(double value) => value.clamp(0, 100);

RiskAnalysisResultModel _computeDemoAnalysis(StudentRiskInputModel input) {
  final absenceRate = input.totalClasses > 0
      ? _clampPercent(input.totalAbsences / input.totalClasses * 100)
      : 0.0;
  final gpaDecline = input.previousGpa > 0
      ? _clampPercent(
          (input.previousGpa - input.currentGpa) / input.previousGpa * 100)
      : 0.0;
  final thirtyDayAbsenceRate =
      _clampPercent(input.maxConsecutiveAbsences / 30 * 100);

  final violationSeverity = input.minorCount * _violationWeights['minor']! +
      input.majorACount * _violationWeights['majorA']! +
      input.majorBCount * _violationWeights['majorB']! +
      input.majorCCount * _violationWeights['majorC']! +
      input.majorDCount * _violationWeights['majorD']!;

  final trendAdjustment = switch (input.recentAttendanceTrend) {
    AttendanceTrend.increasing => 15.0,
    AttendanceTrend.decreasing => -15.0,
    AttendanceTrend.stable => 0.0,
  };
  final recoveryAdjustment = -(input.recoveryScore * 20);
  final recencyAdjustment = input.daysSinceLastViolation < 14
      ? (14 - input.daysSinceLastViolation)
      : 0;

  final dropoutRisk = _clampPercent(
    absenceRate * 0.8 +
        gpaDecline * 0.8 +
        thirtyDayAbsenceRate * 0.3 +
        violationSeverity * 2 +
        input.failingCourses * 8 +
        trendAdjustment +
        recoveryAdjustment +
        recencyAdjustment,
  );

  final riskStatus = switch (dropoutRisk) {
    >= 80 => 'CRITICAL',
    >= 60 => 'HIGH',
    >= 35 => 'MODERATE',
    _ => 'LOW',
  };

  final riskProbability =
      _clampPercent(violationSeverity * 3 + input.failingCourses * 6);
  final confidence = _clampPercent(
    100 - input.daysSinceLastViolation * 1.5 - input.recoveryScore * 15,
  );

  final interventions = switch (riskStatus) {
    'CRITICAL' => const [
        'Immediate parent notification',
        'Schedule emergency counseling',
        'Implement daily attendance monitoring',
        'Academic intervention program',
      ],
    'HIGH' => const [
        'Schedule counseling session',
        'Weekly attendance check-ins',
        'Academic support referral',
      ],
    'MODERATE' => const [
        'Monitor attendance trends',
        'Encourage academic support resources',
      ],
    _ => const ['Continue routine monitoring'],
  };

  return RiskAnalysisResultModel(
    dropoutRiskPercentage: dropoutRisk,
    riskStatus: riskStatus,
    riskProbabilityPercent: riskProbability,
    confidencePercent: confidence,
    absenceRatePercent: absenceRate,
    thirtyDayAbsenceRatePercent: thirtyDayAbsenceRate,
    gpaDeclinePercent: gpaDecline,
    riskReasoningFactors: [
      RiskReasoningFactorModel(
        factor: 'Declining GPA',
        value: _formatFactorValue(gpaDecline),
        severity: _severityFor(gpaDecline),
      ),
      RiskReasoningFactorModel(
        factor: 'Violation Severity (STI Handbook weighted)',
        value: _formatFactorValue(violationSeverity),
        severity: _severityFor(violationSeverity),
      ),
      RiskReasoningFactorModel(
        factor: 'Failing Courses',
        value: _formatFactorValue(input.failingCourses.toDouble()),
        severity: _severityFor(input.failingCourses * 4),
      ),
    ],
    recommendedInterventions: interventions,
  );
}

String _severityFor(double contribution) {
  if (contribution >= 15) return 'HIGH';
  if (contribution >= 7) return 'MODERATE';
  return 'LOW';
}

String _formatFactorValue(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3);
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _Colors {
  static const primaryAction = Color(0xFF345892);
  // Dark-mode values below use the app-wide neutral near-black palette
  // (0E0E0E background, 191A1F cards, 22242B/2E313A borders, F5F5F5/
  // A1A1AA/71717A text) — light mode is untouched.
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF191A1F) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0xFF22242B)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);
  static Color inputFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9);
  static Color inputText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF5F5F5) : const Color(0xFF1F2937);

  // Brand accent — stays constant across themes.

  // Brand accent (navy header row) — stays constant across themes.
  // Semantic accents (plain colored text, not a tinted surface) — stay
  // constant across themes.
  static const severityHigh = kDangerTextColor;
  static const severityModerate = Color(0xFFD97706);
  static const severityLow = Color(0xFF16A34A);

  // The gauge's unfilled track sits directly on the card surface, so it
  // follows the card-surface swap the same way chart gridlines do.
  static Color gaugeTrack(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF2E313A) : const Color(0xFFE0F2FE);
  // Brand accent (dark bezel ring) — stays constant across themes.
  static const gaugeRim = Color(0xFF0F172A);

  // Dropout Risk gauge arc — blends green -> yellow -> orange -> red across
  // the full 0-100 range (evenly spaced stops, so every transition is a
  // smooth blend), so the color at the arc's tip always reflects the current
  // value's own severity rather than one flat "active" color. Brand accents —
  // stay constant across themes.
  static const gaugeLow = Color(0xFF22C55E);
  static const gaugeModerate = Color(0xFFFACC15);
  static const gaugeHigh = Color(0xFFF97316);
  static const gaugeCritical = Color(0xFFDC2626);

  // Soft-tint risk-status badges — richer/darker tints with brighter text in
  // dark mode so they stay legible against the dark card, keeping each
  // status's hue family (red/orange/yellow/green) recognizable.
  static Color criticalBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2);
  static Color criticalBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFEF4444) : const Color(0xFFDC2626);
  static Color criticalText(BuildContext context) =>
      context.isDarkMode ? kDangerTextColor : const Color(0xFF991B1B);
  static Color highBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF431407) : const Color(0xFFFFEDD5);
  static Color highBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFB923C) : const Color(0xFFD97706);
  static Color highText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFDBA74) : const Color(0xFF9A3412);
  static Color moderateBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF422006) : const Color(0xFFFEF9C3);
  static Color moderateBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFACC15) : const Color(0xFFCA8A04);
  static Color moderateText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFDE68A) : const Color(0xFF854D0E);
  static Color lowBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF052E1B) : const Color(0xFFDCFCE7);
  static Color lowBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  static Color lowText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF86EFAC) : const Color(0xFF166534);

  /// Untested / "Invalid" pending-analysis tint.
  static Color neutralBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF0E0E0E) : const Color(0xFFF8FAFC);
  static Color neutralBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF22242B) : const Color(0xFFE2E8F0);
}

Color _severityColor(String severity) {
  return switch (severity) {
    'HIGH' => _Colors.severityHigh,
    'MODERATE' => _Colors.severityModerate,
    _ => _Colors.severityLow,
  };
}

(Color bg, Color border, Color text) _statusTint(
  BuildContext context,
  String status,
) {
  return switch (status) {
    'CRITICAL' => (
        _Colors.criticalBg(context),
        _Colors.criticalBorder(context),
        _Colors.criticalText(context)
      ),
    'HIGH' => (
        _Colors.highBg(context),
        _Colors.highBorder(context),
        _Colors.highText(context)
      ),
    'MODERATE' => (
        _Colors.moderateBg(context),
        _Colors.moderateBorder(context),
        _Colors.moderateText(context)
      ),
    'LOW' => (
        _Colors.lowBg(context),
        _Colors.lowBorder(context),
        _Colors.lowText(context)
      ),
    _ => (
        _Colors.neutralBg(context),
        _Colors.neutralBorder(context),
        _Colors.secondaryText(context)
      ),
  };
}

// ---------------------------------------------------------------------------
// State engine
// ---------------------------------------------------------------------------

/// Owns every field on the "Student Risk Parameters" form plus the most
/// recent [RiskAnalysisResultModel]. Plain mutable fields (rather than an
/// immutable model + copyWith) so each input widget can call one setter
/// directly, matching this module's other `ChangeNotifier` controllers.
///
/// [result] is never null — it starts as [RiskAnalysisResultModel.initial]
/// (the neutral "Invalid"/untested state) so every card can render
/// unconditionally instead of branching on a nullable result.
class SingleStudentAnalysisController extends ChangeNotifier {
  String studentId = '';
  double currentGpa = 0.0;
  double previousGpa = 0.0;
  int totalClasses = 0;
  int totalAbsences = 0;
  int failingCourses = 0;
  int maxConsecutiveAbsences = 0;
  int daysSinceLastViolation = 0;
  double recoveryScore = 0.0;
  AttendanceTrend recentAttendanceTrend = AttendanceTrend.stable;

  int minorCount = 0;
  int majorACount = 0;
  int majorBCount = 0;
  int majorCCount = 0;
  int majorDCount = 0;

  bool isAnalyzing = false;
  bool isLookingUp = false;

  /// True once "Analyze Risk" has completed successfully at least once.
  bool hasAnalyzed = false;

  RiskAnalysisResultModel result = RiskAnalysisResultModel.initial();
  String? errorMessage;
  String? lookupError;

  StudentRiskInputModel get currentInput => StudentRiskInputModel(
        studentId: studentId,
        currentGpa: currentGpa,
        previousGpa: previousGpa,
        totalClasses: totalClasses,
        totalAbsences: totalAbsences,
        failingCourses: failingCourses,
        maxConsecutiveAbsences: maxConsecutiveAbsences,
        daysSinceLastViolation: daysSinceLastViolation,
        recoveryScore: recoveryScore,
        recentAttendanceTrend: recentAttendanceTrend,
        minorCount: minorCount,
        majorACount: majorACount,
        majorBCount: majorBCount,
        majorCCount: majorCCount,
        majorDCount: majorDCount,
      );

  void setStudentId(String value) {
    studentId = value;
    notifyListeners();
  }

  void setCurrentGpa(double value) {
    currentGpa = value;
    notifyListeners();
  }

  void setPreviousGpa(double value) {
    previousGpa = value;
    notifyListeners();
  }

  void setTotalClasses(int value) {
    totalClasses = value;
    notifyListeners();
  }

  void setTotalAbsences(int value) {
    totalAbsences = value;
    notifyListeners();
  }

  void setFailingCourses(int value) {
    failingCourses = value;
    notifyListeners();
  }

  void setMaxConsecutiveAbsences(int value) {
    maxConsecutiveAbsences = value;
    notifyListeners();
  }

  void setDaysSinceLastViolation(int value) {
    daysSinceLastViolation = value;
    notifyListeners();
  }

  void setRecoveryScore(double value) {
    recoveryScore = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setRecentAttendanceTrend(AttendanceTrend value) {
    recentAttendanceTrend = value;
    notifyListeners();
  }

  void setMinorCount(int value) {
    minorCount = value;
    notifyListeners();
  }

  void setMajorACount(int value) {
    majorACount = value;
    notifyListeners();
  }

  void setMajorBCount(int value) {
    majorBCount = value;
    notifyListeners();
  }

  void setMajorCCount(int value) {
    majorCCount = value;
    notifyListeners();
  }

  void setMajorDCount(int value) {
    majorDCount = value;
    notifyListeners();
  }

  /// Fetches real attendance/GPA/violation aggregates for the currently
  /// entered [studentId] and prefills every other field with them — see
  /// [StudentRiskAutofillModel]'s own doc comment. A student ID that
  /// resolves to nothing sets [lookupError] rather than touching any field,
  /// so a mistyped/unenrolled ID never silently zeroes out a form the
  /// counselor may have already been filling in by hand.
  Future<void> lookupStudent({
    required Future<StudentRiskAutofillModel?> Function(String studentId)
        onLookup,
  }) async {
    final id = studentId.trim();
    if (id.isEmpty || isLookingUp) return;
    isLookingUp = true;
    lookupError = null;
    notifyListeners();

    try {
      final data = await onLookup(id);
      if (data == null) {
        lookupError = 'No student found with ID "$id".';
      } else {
        currentGpa = data.currentGpa;
        previousGpa = data.previousGpa;
        totalClasses = data.totalClasses;
        totalAbsences = data.totalAbsences;
        failingCourses = data.failingCourses;
        maxConsecutiveAbsences = data.maxConsecutiveAbsences;
        daysSinceLastViolation = data.daysSinceLastViolation;
        recoveryScore = data.recoveryScore;
        recentAttendanceTrend = data.recentAttendanceTrend;
        minorCount = data.minorCount;
        majorACount = data.majorACount;
        majorBCount = data.majorBCount;
        majorCCount = data.majorCCount;
        majorDCount = data.majorDCount;
      }
    } catch (e) {
      lookupError = 'Could not look up this student: $e';
    } finally {
      isLookingUp = false;
      notifyListeners();
    }
  }

  Future<void> analyze({
    required Future<RiskAnalysisResultModel> Function(
            StudentRiskInputModel input)?
        onAnalyze,
  }) async {
    if (isAnalyzing) return;
    isAnalyzing = true;
    errorMessage = null;
    notifyListeners();

    try {
      final input = currentInput;
      result = onAnalyze != null
          ? await onAnalyze(input)
          : _computeDemoAnalysis(input);
      hasAnalyzed = true;
    } catch (e) {
      errorMessage = 'Could not analyze this student: $e';
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }
}

/// Runs the Student ID lookup.
typedef _LookupCallback = Future<void> Function({bool silent});

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

/// "Single Student Analysis" tab: a risk-parameter form on the left feeding
/// a dropout-risk gauge, a standalone risk-assessment card, and recommended
/// interventions on the right.
class SingleStudentAnalysisView extends StatefulWidget {
  const SingleStudentAnalysisView({
    super.key,
    this.onAnalyze,
    this.onLookupStudent,
    this.onDownloadAssessment,
    this.isMobile = false,
  });

  /// Scores [StudentRiskInputModel] against the real ML pipeline. Omit to
  /// use the built-in demo calculator (no backend required).
  final Future<RiskAnalysisResultModel> Function(StudentRiskInputModel input)?
      onAnalyze;

  /// Fetches real attendance/GPA/violation aggregates for a Student ID,
  /// prefilling the rest of the form — triggered by pressing Enter in the
  /// Student ID field or tapping its lookup button. Returns null for an ID
  /// that doesn't resolve to an enrolled student. Omit to hide the lookup
  /// button entirely and require every field to be typed in by hand (demo
  /// behavior — no backend to look anything up from).
  final Future<StudentRiskAutofillModel?> Function(String studentId)?
      onLookupStudent;

  /// Exports the current assessment. Omitted: just a confirmation snackbar.
  final Future<void> Function(
          StudentRiskInputModel input, RiskAnalysisResultModel result)?
      onDownloadAssessment;

  /// True when the page has no bounded height to hand this view (it
  /// scrolls instead) — sizes to its own content rather than wrapping
  /// itself in another `SingleChildScrollView`, which would be nested
  /// inside the page's own and need bounded height it won't have.
  final bool isMobile;

  @override
  State<SingleStudentAnalysisView> createState() =>
      _SingleStudentAnalysisViewState();
}

class _SingleStudentAnalysisViewState extends State<SingleStudentAnalysisView> {
  final _controller = SingleStudentAnalysisController();
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleAnalyze() async {
    await _controller.analyze(onAnalyze: widget.onAnalyze);
    if (_controller.errorMessage != null) {
      _showSnackBar(_controller.errorMessage!);
    }
  }

  /// [silent] is for the Student ID field's automatic lookup while the
  /// counselor is still typing — a half-typed ID that matches nobody must
  /// not pop an error; Enter and the search button are never silent.
  Future<void> _handleLookup({bool silent = false}) async {
    final onLookupStudent = widget.onLookupStudent;
    if (onLookupStudent == null) return;
    await _controller.lookupStudent(onLookup: onLookupStudent);
    if (!silent && _controller.lookupError != null) {
      _showSnackBar(_controller.lookupError!);
    }
  }

  Future<void> _handleDownloadAssessment() async {
    if (!_controller.hasAnalyzed || _downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownloadAssessment
          ?.call(_controller.currentInput, _controller.result);
      _showSnackBar('Assessment downloaded.');
    } catch (e) {
      _showSnackBar('Could not download assessment: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leftColumn = _InputAndReasoningColumn(
      controller: _controller,
      onAnalyze: _handleAnalyze,
      onLookup: widget.onLookupStudent == null ? null : _handleLookup,
    );
    final rightColumn = _GaugeAndInterventionsColumn(
      result: _controller.result,
      hasAnalyzed: _controller.hasAnalyzed,
      downloading: _downloading,
      onDownloadAssessment: _handleDownloadAssessment,
    );

    if (widget.isMobile) {
      // The whole page (including the header) scrolls on mobile, so this
      // sizes to its own content instead of wrapping itself in another
      // SingleChildScrollView, which would need bounded height it won't
      // have nested inside the page's own scroll.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          leftColumn,
          const SizedBox(height: 20),
          rightColumn,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 1000;

        // Every card renders its own full/natural height (no internal
        // per-card scrolling) — the dashboard page's own outer scroll view
        // handles the whole tab instead, matching
        // `BatchStudentAnalysisView`'s convention.
        if (stackColumns) {
          return Column(
            children: [
              leftColumn,
              const SizedBox(height: 20),
              rightColumn,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leftColumn),
            const SizedBox(width: 18),
            SizedBox(width: 430, child: rightColumn),
          ],
        );
      },
    );
  }
}

class _InputAndReasoningColumn extends StatelessWidget {
  const _InputAndReasoningColumn({
    required this.controller,
    required this.onAnalyze,
    required this.onLookup,
  });

  final SingleStudentAnalysisController controller;
  final VoidCallback onAnalyze;
  final _LookupCallback? onLookup;

  @override
  Widget build(BuildContext context) {
    final reasoningCard =
        _RiskReasoningCard(factors: controller.result.riskReasoningFactors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudentRiskParametersCard(
          controller: controller,
          onAnalyze: onAnalyze,
          onLookup: onLookup,
        ),
        const SizedBox(height: 20),
        reasoningCard,
      ],
    );
  }
}

class _GaugeAndInterventionsColumn extends StatelessWidget {
  const _GaugeAndInterventionsColumn({
    required this.result,
    required this.hasAnalyzed,
    required this.downloading,
    required this.onDownloadAssessment,
  });

  final RiskAnalysisResultModel result;
  final bool hasAnalyzed;
  final bool downloading;
  final VoidCallback onDownloadAssessment;

  @override
  Widget build(BuildContext context) {
    final interventionsCard = _RecommendedInterventionsCard(
      interventions: result.recommendedInterventions,
      downloading: downloading,
      onDownloadAssessment: hasAnalyzed ? onDownloadAssessment : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DropoutRiskGaugeCard(value: result.dropoutRiskPercentage),
        const SizedBox(height: 20),
        _RiskAssessmentCard(result: result),
        const SizedBox(height: 20),
        interventionsCard,
      ],
    );
  }
}

/// Shared white/rounded/bordered wrapper for every card in this view.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.flush = false,
  });

  final Widget child;
  final EdgeInsets padding;

  /// For a card whose table runs edge to edge (the app-wide table standard):
  /// no card padding — the child pads its own header — and the card clips,
  /// so the table's header band follows the rounded corners.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: _Colors.card(context),
        borderColor: _Colors.cardBorder(context),
        padding: flush ? EdgeInsets.zero : padding,
        clipBehavior: flush ? Clip.antiAlias : Clip.none,
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Student Risk Parameters card
// ---------------------------------------------------------------------------

class _StudentRiskParametersCard extends StatelessWidget {
  const _StudentRiskParametersCard({
    required this.controller,
    required this.onAnalyze,
    required this.onLookup,
  });

  final SingleStudentAnalysisController controller;
  final VoidCallback onAnalyze;
  final _LookupCallback? onLookup;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Risk Parameters',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
            ),
          ),
          const SizedBox(height: 20),
          _FieldRow(
            children: [
              _StudentIdField(
                value: controller.studentId,
                onChanged: controller.setStudentId,
                onLookup: onLookup,
                isLookingUp: controller.isLookingUp,
              ),
              _NumberField(
                label: 'Current GPA',
                value: controller.currentGpa,
                decimals: 2,
                onChanged: controller.setCurrentGpa,
              ),
              _NumberField(
                label: 'Previous GPA',
                value: controller.previousGpa,
                decimals: 2,
                onChanged: controller.setPreviousGpa,
              ),
              _NumberField(
                label: 'Total Classes',
                value: controller.totalClasses.toDouble(),
                onChanged: (v) => controller.setTotalClasses(v.round()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FieldRow(
            children: [
              _NumberField(
                label: 'Total Absences (Semester)',
                value: controller.totalAbsences.toDouble(),
                onChanged: (v) => controller.setTotalAbsences(v.round()),
              ),
              _NumberField(
                label: 'Failing Courses',
                value: controller.failingCourses.toDouble(),
                onChanged: (v) => controller.setFailingCourses(v.round()),
              ),
              _NumberField(
                label: 'Max Consecutive Absences',
                value: controller.maxConsecutiveAbsences.toDouble(),
                onChanged: (v) =>
                    controller.setMaxConsecutiveAbsences(v.round()),
              ),
              _NumberField(
                label: 'Days Since Last Violation',
                value: controller.daysSinceLastViolation.toDouble(),
                onChanged: (v) =>
                    controller.setDaysSinceLastViolation(v.round()),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _RecoveryScoreRow(
            value: controller.recoveryScore,
            onChanged: controller.setRecoveryScore,
          ),
          const SizedBox(height: 20),
          _AttendanceTrendRow(
            value: controller.recentAttendanceTrend,
            onChanged: controller.setRecentAttendanceTrend,
          ),
          const SizedBox(height: 24),
          Text(
            'Violations',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          _FieldRow(
            children: [
              _NumberField(
                label: 'Minor',
                value: controller.minorCount.toDouble(),
                onChanged: (v) => controller.setMinorCount(v.round()),
              ),
              _NumberField(
                label: 'Major A',
                value: controller.majorACount.toDouble(),
                onChanged: (v) => controller.setMajorACount(v.round()),
              ),
              _NumberField(
                label: 'Major B',
                value: controller.majorBCount.toDouble(),
                onChanged: (v) => controller.setMajorBCount(v.round()),
              ),
              _NumberField(
                label: 'Major C',
                value: controller.majorCCount.toDouble(),
                onChanged: (v) => controller.setMajorCCount(v.round()),
              ),
              _NumberField(
                label: 'Major D',
                value: controller.majorDCount.toDouble(),
                onChanged: (v) => controller.setMajorDCount(v.round()),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: controller.isAnalyzing ? null : onAnalyze,
              style: FilledButton.styleFrom(
                backgroundColor: _Colors.primaryAction,
                foregroundColor: Colors.white,
                // The app's standard primary-button size (12x8 padding /
                // 12px label, no 40px Material minimum).
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, kDashboardControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.isAnalyzing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  else
                    const Icon(Icons.menu_book_outlined,
                        size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Analyze Risk',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Evenly spaces its children across a row, wrapping to the next line on
/// narrow viewports rather than overflowing.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columnWidth =
            (constraints.maxWidth - spacing * (children.length - 1)) /
                children.length;
        const minColumnWidth = 150.0;

        if (columnWidth >= minColumnWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i != children.length - 1) const SizedBox(width: spacing),
              ],
            ],
          );
        }

        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: [
            for (final child in children) SizedBox(width: 220, child: child),
          ],
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: context.isMobileWidth ? 10 : 12,
        fontWeight: FontWeight.w500,
        color: _Colors.secondaryText(context),
      ),
    );
  }
}

class _TextEntryField extends StatefulWidget {
  const _TextEntryField(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextEntryField> createState() => _TextEntryFieldState();
}

class _TextEntryFieldState extends State<_TextEntryField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_TextEntryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label: widget.label),
        const SizedBox(height: 6),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: _Colors.inputFill(context),
            borderRadius: BorderRadius.circular(5),
          ),
          child: TextField(
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.center,
            controller: _controller,
            onChanged: widget.onChanged,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 11 : 13,
              fontWeight: FontWeight.w500,
              color: _Colors.inputText(context),
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Student ID field plus its lookup control — the lookup runs on Enter, on
/// the trailing button, and automatically shortly after typing stops; it calls
/// [onLookup], which fetches real attendance/
/// GPA/violation data for this ID and prefills every other field (see
/// [SingleStudentAnalysisView.onLookupStudent]). A plain [_TextEntryField]
/// when [onLookup] is omitted (demo behavior — nothing to look up from).
class _StudentIdField extends StatefulWidget {
  const _StudentIdField({
    required this.value,
    required this.onChanged,
    required this.onLookup,
    required this.isLookingUp,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final _LookupCallback? onLookup;
  final bool isLookingUp;

  @override
  State<_StudentIdField> createState() => _StudentIdFieldState();
}

const _autoLookupDelay = Duration(milliseconds: 700);

class _StudentIdFieldState extends State<_StudentIdField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  Timer? _debounce;

  /// The last ID a lookup was started for, so the automatic lookup doesn't
  /// re-fetch (and re-overwrite the form) for an ID it already loaded.
  String? _lastLookedUp;

  void _onChanged(String value) {
    widget.onChanged(value);
    _debounce?.cancel();
    if (widget.onLookup == null || value.trim().isEmpty) return;
    _debounce = Timer(_autoLookupDelay, _autoLookup);
  }

  /// Looks the ID up once typing pauses, so neither Enter nor the search
  /// button is needed. Silent: see [SingleStudentAnalysisView]'s
  /// `_handleLookup`.
  void _autoLookup() {
    final onLookup = widget.onLookup;
    final id = _controller.text.trim();
    if (!mounted || onLookup == null || id.isEmpty || id == _lastLookedUp) {
      return;
    }
    if (widget.isLookingUp) {
      _debounce = Timer(_autoLookupDelay, _autoLookup);
      return;
    }
    _lastLookedUp = id;
    onLookup(silent: true);
  }

  /// Enter or the search button: look up right now, with error feedback.
  void _lookupNow() {
    final onLookup = widget.onLookup;
    if (onLookup == null || widget.isLookingUp) return;
    _debounce?.cancel();
    _lastLookedUp = _controller.text.trim();
    onLookup();
  }

  @override
  void didUpdateWidget(_StudentIdField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onLookup = widget.onLookup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel(label: 'Student ID'),
        const SizedBox(height: 6),
        _InputBox(
          focusNode: _focus,
          trailing: onLookup == null
              ? null
              : Tooltip(
                  message: 'Look up student',
                  child: InkWell(
                    onTap: widget.isLookingUp ? null : _lookupNow,
                    child: SizedBox(
                      width: 32,
                      height: 40,
                      child: widget.isLookingUp
                          ? Padding(
                              padding: const EdgeInsets.all(11),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _Colors.secondaryText(context),
                              ),
                            )
                          : Icon(Icons.search_rounded,
                              size: 18, color: _Colors.secondaryText(context)),
                    ),
                  ),
                ),
          field: TextField(
                  focusNode: _focus,
                  // Single-line: a multiline field turns Enter into a newline
                  // and never fires onSubmitted.
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  textInputAction: TextInputAction.search,
                  controller: _controller,
                  onChanged: _onChanged,
                  onSubmitted: onLookup == null ? null : (_) => _lookupNow(),
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: _Colors.inputText(context),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: InputBorder.none,
                  ),
                ),
              ),
      ],
    );
  }
}

/// The grey 40px box shared by the risk-form text fields. The [field] is a
/// single-line, unpadded TextField that is centred in the box (the same way
/// a plain `Text` is); values stay left-aligned. Taps anywhere in the box
/// focus the field.
///
/// On web an editable field paints its text lower than a plain `Text` does
/// at the same position (measured on a 972px-wide Chrome screenshot, 13px
/// Poppins: 19px above the digits and 12px below, versus 16/15 for a
/// centred `Text`). Desktop renders it correctly, so only web gets the
/// compensating lift, scaled with the font size.
class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.focusNode,
    required this.field,
    this.trailing,
  });

  final FocusNode focusNode;
  final Widget field;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fontSize = context.isMobileWidth ? 11.0 : 13.0;
    final webLift = kIsWeb ? -fontSize * (3 / 13) : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: _Colors.inputFill(context),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, webLift),
                  child: field,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Plain numeric text-entry field on a grey input box (no increment/decrement
/// buttons) — typed values feed [onChanged] on Enter or when focus leaves.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final int decimals;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  String _format(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (double.tryParse(_controller.text) != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    widget.onChanged(parsed.clamp(0, double.infinity));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label: widget.label),
        const SizedBox(height: 6),
        _InputBox(
          focusNode: _focus,
          field: TextField(
                  focusNode: _focus,
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  controller: _controller,
                  keyboardType: TextInputType.numberWithOptions(
                      decimal: widget.decimals > 0),
                  onSubmitted: _submit,
                  onTapOutside: (_) => _submit(_controller.text),
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w500,
                    color: _Colors.inputText(context),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: InputBorder.none,
                  ),
                ),
        ),
      ],
    );
  }
}

class _RecoveryScoreRow extends StatelessWidget {
  const _RecoveryScoreRow({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Recovery Score'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: _Colors.primaryAction,
                  inactiveTrackColor: _Colors.cardBorder(context),
                  thumbColor: _Colors.primaryAction,
                  overlayColor: _Colors.primaryAction.withOpacity(0.12),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: value,
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _Colors.inputFill(context),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                value.toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w600,
                  color: _Colors.inputText(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AttendanceTrendRow extends StatelessWidget {
  const _AttendanceTrendRow({required this.value, required this.onChanged});

  final AttendanceTrend value;
  final ValueChanged<AttendanceTrend> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Recent Attendance Trend (Last 30 Days)'),
        const SizedBox(height: 6),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _Colors.inputFill(context),
            borderRadius: BorderRadius.circular(5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AttendanceTrend>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: _Colors.secondaryText(context)),
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w500,
                color: _Colors.inputText(context),
              ),
              items: [
                for (final trend in AttendanceTrend.values)
                  DropdownMenuItem(value: trend, child: Text(trend.label)),
              ],
              onChanged: (trend) {
                if (trend != null) onChanged(trend);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Risk Reasoning card
// ---------------------------------------------------------------------------

class _RiskReasoningCard extends StatelessWidget {
  const _RiskReasoningCard({required this.factors});

  final List<RiskReasoningFactorModel> factors;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // 16 above the table, 20 (the card's usual padding) when
            // there's no table below.
            padding: EdgeInsets.fromLTRB(20, 20, 20, factors.isEmpty ? 20 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Risk Reasoning',
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: _Colors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  factors.isEmpty
                      ? 'Run an analysis to see contributing factors'
                      : factors.map((f) => f.factor).join(' + '),
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w400,
                    color: _Colors.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          if (factors.isNotEmpty) _RiskReasoningTable(factors: factors),
        ],
      ),
    );
  }
}

class _RiskReasoningTable extends StatelessWidget {
  const _RiskReasoningTable({required this.factors});

  final List<RiskReasoningFactorModel> factors;

  static const _columns = <DashboardTableColumn>[
    DashboardTableColumn('#', width: 32),
    DashboardTableColumn('Factor', flex: 3),
    DashboardTableColumn('Value', flex: 2),
    DashboardTableColumn('Severity', flex: 2),
  ];

  @override
  Widget build(BuildContext context) {
    return DashboardTableScrollFrame(
      columns: _columns,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardTableHeader(columns: _columns, topBorder: true),
          for (var i = 0; i < factors.length; i++)
            DashboardTableRow(
              columns: _columns,
              showDivider: i < factors.length - 1,
              cells: [
                Text('${i + 1}', style: dashboardTableMetaStyle(context)),
                Text(
                  factors[i].factor,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTablePrimaryStyle(context),
                ),
                Text(
                  factors[i].value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardTableBodyStyle(context),
                ),
                Text(
                  factors[i].severity,
                  style: dashboardTableIdStyle(
                    context,
                    color: _severityColor(factors[i].severity),
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card 1 — Dropout Risk Gauge (title + gauge only)
// ---------------------------------------------------------------------------

class _DropoutRiskGaugeCard extends StatelessWidget {
  const _DropoutRiskGaugeCard({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        children: [
          Text(
            'Dropout Risk %',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          _DropoutRiskGauge(value: value),
        ],
      ),
    );
  }
}

class _DropoutRiskGauge extends StatelessWidget {
  const _DropoutRiskGauge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 172,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GaugePainter(
                value: value,
                trackColor: _Colors.gaugeTrack(context),
                tickTextColor: _Colors.secondaryText(context),
                isMobile: context.isMobileWidth,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: Text(
              value.round().toString(),
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 32 : 34,
                fontWeight: FontWeight.w800,
                color: _Colors.primaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.trackColor,
    required this.tickTextColor,
    required this.isMobile,
  });

  final double value;

  /// "Surface family" colors — sit on the card behind the gauge, so they're
  /// passed in from the widget layer rather than read directly by this
  /// custom painter.
  final Color trackColor;
  final Color tickTextColor;

  /// A [CustomPainter] has no [BuildContext], so `context.isMobileWidth`
  /// must be read by the widget layer and passed in.
  final bool isMobile;

  static const _ticks = [0, 20, 40, 60, 80, 100];

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 18.0;
    final center = Offset(size.width / 2, size.height - 20);
    final radius = (size.width - strokeWidth * 2) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final rimPaint = Paint()
      ..color = _Colors.gaugeRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, rimPaint);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    // Gradient spans the gauge's full 0-100 range (not just the drawn
    // sweep), so the color right at the arc's tip always matches that
    // value's own severity — e.g. a Moderate reading ends in a
    // yellow-to-orange blend, not the flat Low green.
    //
    // The gradient is laid over the full circle (0 = 3 o'clock), with the
    // arc itself on its top half (0.5 -> 1.0). The round end caps poke a
    // little past each end of the arc, so [cap] holds the end colors just
    // beyond it — otherwise the right cap would wrap around and show the
    // green start color.
    final cap = (strokeWidth / 2 / radius) / (2 * math.pi);
    final activePaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          _Colors.gaugeCritical,
          _Colors.gaugeCritical,
          _Colors.gaugeLow,
          _Colors.gaugeLow,
          _Colors.gaugeModerate,
          _Colors.gaugeHigh,
          _Colors.gaugeCritical,
        ],
        stops: [
          0.0,
          cap,
          0.5 - cap,
          0.5,
          0.5 + 1 / 6,
          0.5 + 2 / 6,
          1.0,
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = math.pi * (value.clamp(0, 100) / 100);
    if (sweep > 0) {
      canvas.drawArc(rect, math.pi, sweep, false, activePaint);
    }

    for (final tick in _ticks) {
      final angle = math.pi + math.pi * (tick / 100);
      final tickRadius = radius + strokeWidth / 2 + 14;
      final offset = Offset(
        center.dx + tickRadius * math.cos(angle),
        center.dy + tickRadius * math.sin(angle),
      );
      final painter = TextPainter(
        text: TextSpan(
          text: '$tick',
          style: TextStyle(
            fontSize: isMobile ? 9 : 11,
            fontWeight: FontWeight.w500,
            color: tickTextColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
          canvas, offset - Offset(painter.width / 2, painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.tickTextColor != tickTextColor ||
      oldDelegate.isMobile != isMobile;
}

// ---------------------------------------------------------------------------
// Card 2 — Risk Assessment (standalone; neutral tint until analyzed)
// ---------------------------------------------------------------------------

class _RiskAssessmentCard extends StatelessWidget {
  const _RiskAssessmentCard({required this.result});

  final RiskAnalysisResultModel result;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      // Horizontal padding trimmed from 16 -> 12 so the footer's middle
      // column ("30-Day Absence Rate") has enough width to stay on one line.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: _RiskAssessmentBox(result: result),
    );
  }
}

class _RiskAssessmentBox extends StatelessWidget {
  const _RiskAssessmentBox({required this.result});

  final RiskAnalysisResultModel result;

  @override
  Widget build(BuildContext context) {
    final (bg, border, text) = _statusTint(context, result.riskStatus);

    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: bg,
        borderColor: border,
        borderRadius: 14,
        elevated: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Column(
                children: [
                  Text(
                    result.riskStatus,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 20 : 22,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Risk Probability: ${result.riskProbabilityPercent.toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: text,
                    ),
                  ),
                  Text(
                    'Confidence: ${result.confidencePercent.toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: text,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: border.withOpacity(0.4)),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Row(
                children: [
                  // flex 3:4:3 — the middle column's label ("30-Day Absence
                  // Rate") is the longest, so it gets extra width to stay
                  // on one line instead of wrapping.
                  Expanded(
                    flex: 3,
                    child: _AlertMetric(
                      label: 'Absence Rate',
                      value: result.absenceRatePercent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: _AlertMetric(
                      label: '30-Day Absence Rate',
                      value: result.thirtyDayAbsenceRatePercent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: _AlertMetric(
                      label: 'GPA Decline',
                      value: result.gpaDeclinePercent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "label / value" pair in the Risk Assessment footer. Sized by its
/// caller's `Expanded(flex: ...)` rather than wrapping itself, so the three
/// columns can use uneven flex ratios (the middle "30-Day Absence Rate"
/// column needs more room than the outer two).
class _AlertMetric extends StatelessWidget {
  const _AlertMetric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 9 : 11,
            fontWeight: FontWeight.w500,
            color: _Colors.secondaryText(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(1)}%',
          style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 13 : 15,
            fontWeight: FontWeight.w700,
            color: _Colors.primaryText(context),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card 3 — Recommended Interventions
// ---------------------------------------------------------------------------

class _RecommendedInterventionsCard extends StatelessWidget {
  const _RecommendedInterventionsCard({
    required this.interventions,
    required this.downloading,
    required this.onDownloadAssessment,
  });

  final List<String> interventions;
  final bool downloading;
  final VoidCallback? onDownloadAssessment;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommended Interventions',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: _Colors.primaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          if (interventions.isEmpty)
            Text(
              'Run an analysis to see recommended interventions',
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w400,
                color: _Colors.secondaryText(context),
              ),
            )
          else
            for (final item in interventions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•  ',
                      style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 11 : 13, color: _Colors.primaryText(context)),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.poppins(
                          fontSize: context.isMobileWidth ? 11 : 13,
                          fontWeight: FontWeight.w400,
                          color: _Colors.primaryText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onDownloadAssessment == null || downloading
                  ? null
                  : onDownloadAssessment,
              style: FilledButton.styleFrom(
                backgroundColor: _Colors.primaryAction,
                foregroundColor: Colors.white,
                // Standard primary-button size, like "Analyze Risk".
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, kDashboardControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (downloading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  else
                    const Icon(Icons.download_rounded,
                        size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Download Assessment',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
