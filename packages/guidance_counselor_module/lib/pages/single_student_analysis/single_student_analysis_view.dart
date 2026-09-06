import 'dart:math' as math;

import 'package:dashboard_layout/dashboard_layout.dart';
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
  static const primaryAction = Color(0xFF345892);

  // Brand accent (navy header row) — stays constant across themes.
  static const tableHeaderBg = Color(0xFF15253F); // navy-blue
  // Semantic accents (plain colored text, not a tinted surface) — stay
  // constant across themes.
  static const severityHigh = Color(0xFFDC2626);
  static const severityModerate = Color(0xFFD97706);
  static const severityLow = Color(0xFF16A34A);

  // The gauge's unfilled track sits directly on the card surface, so it
  // follows the card-surface swap the same way chart gridlines do.
  static Color gaugeTrack(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF2E313A) : const Color(0xFFE0F2FE);
  // Brand accent (dark bezel ring) — stays constant across themes.
  static const gaugeRim = Color(0xFF0F172A);

  // Dropout Risk gauge arc — sweeps from Low (blue) to Critical (red) across
  // the full 0-100 range, so the color at the arc's tip always reflects the
  // current value's own severity rather than one flat "active" color. Brand
  // accents — stay constant across themes.
  static const gaugeLow = Color(0xFF38BDF8);
  static const gaugeCritical = Color(0xFFDC2626);

  // Soft-tint risk-status badges — richer/darker tints with brighter text in
  // dark mode so they stay legible against the dark card, keeping each
  // status's hue family (red/orange/yellow/green) recognizable.
  static Color criticalBg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2);
  static Color criticalBorder(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFEF4444) : const Color(0xFFDC2626);
  static Color criticalText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
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

  /// True once "Analyze Risk" has completed successfully at least once.
  bool hasAnalyzed = false;

  RiskAnalysisResultModel result = RiskAnalysisResultModel.initial();
  String? errorMessage;

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
    this.onDownloadAssessment,
    this.isMobile = false,
  });

  /// Scores [StudentRiskInputModel] against the real ML pipeline. Omit to
  /// use the built-in demo calculator (no backend required).
  final Future<RiskAnalysisResultModel> Function(StudentRiskInputModel input)?
      onAnalyze;

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
  });

  final SingleStudentAnalysisController controller;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final reasoningCard =
        _RiskReasoningCard(factors: controller.result.riskReasoningFactors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudentRiskParametersCard(
            controller: controller, onAnalyze: onAnalyze),
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
  const _SectionCard(
      {required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _Colors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Colors.cardBorder(context)),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Student Risk Parameters card
// ---------------------------------------------------------------------------

class _StudentRiskParametersCard extends StatelessWidget {
  const _StudentRiskParametersCard(
      {required this.controller, required this.onAnalyze});

  final SingleStudentAnalysisController controller;
  final VoidCallback onAnalyze;

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
              _TextEntryField(
                label: 'Student ID',
                value: controller.studentId,
                onChanged: controller.setStudentId,
              ),
              _StepperField(
                label: 'Current GPA',
                value: controller.currentGpa,
                step: 1,
                decimals: 2,
                onChanged: controller.setCurrentGpa,
              ),
              _StepperField(
                label: 'Previous GPA',
                value: controller.previousGpa,
                step: 1,
                decimals: 2,
                onChanged: controller.setPreviousGpa,
              ),
              _StepperField(
                label: 'Total Classes',
                value: controller.totalClasses.toDouble(),
                step: 1,
                onChanged: (v) => controller.setTotalClasses(v.round()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FieldRow(
            children: [
              _StepperField(
                label: 'Total Absences (Semester)',
                value: controller.totalAbsences.toDouble(),
                step: 1,
                onChanged: (v) => controller.setTotalAbsences(v.round()),
              ),
              _StepperField(
                label: 'Failing Courses',
                value: controller.failingCourses.toDouble(),
                step: 1,
                onChanged: (v) => controller.setFailingCourses(v.round()),
              ),
              _StepperField(
                label: 'Max Consecutive Absences',
                value: controller.maxConsecutiveAbsences.toDouble(),
                step: 1,
                onChanged: (v) =>
                    controller.setMaxConsecutiveAbsences(v.round()),
              ),
              _StepperField(
                label: 'Days Since Last Violation',
                value: controller.daysSinceLastViolation.toDouble(),
                step: 1,
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
              _StepperField(
                label: 'Minor',
                value: controller.minorCount.toDouble(),
                step: 1,
                onChanged: (v) => controller.setMinorCount(v.round()),
              ),
              _StepperField(
                label: 'Major A',
                value: controller.majorACount.toDouble(),
                step: 1,
                onChanged: (v) => controller.setMajorACount(v.round()),
              ),
              _StepperField(
                label: 'Major B',
                value: controller.majorBCount.toDouble(),
                step: 1,
                onChanged: (v) => controller.setMajorBCount(v.round()),
              ),
              _StepperField(
                label: 'Major C',
                value: controller.majorCCount.toDouble(),
                step: 1,
                onChanged: (v) => controller.setMajorCCount(v.round()),
              ),
              _StepperField(
                label: 'Major D',
                value: controller.majorDCount.toDouble(),
                step: 1,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                      fontSize: context.isMobileWidth ? 11 : 13,
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
            controller: _controller,
            onChanged: widget.onChanged,
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 11 : 13,
              fontWeight: FontWeight.w500,
              color: _Colors.inputText(context),
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Numeric field with a grey input box plus right-aligned "-"/"+" steppers.
/// Direct text entry and the steppers both feed [onChanged].
class _StepperField extends StatefulWidget {
  const _StepperField({
    required this.label,
    required this.value,
    required this.step,
    required this.onChanged,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final double step;
  final ValueChanged<double> onChanged;
  final int decimals;

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> {
  late final _controller = TextEditingController(text: _format(widget.value));

  String _format(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(_StepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (double.tryParse(_controller.text) != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(double delta) {
    widget.onChanged((widget.value + delta).clamp(0, double.infinity));
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
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: _Colors.inputFill(context),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
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
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: InputBorder.none,
                  ),
                ),
              ),
              _StepButton(icon: Icons.remove, onTap: () => _step(-widget.step)),
              Container(
                  width: 1, height: 20, color: _Colors.cardBorder(context)),
              _StepButton(icon: Icons.add, onTap: () => _step(widget.step)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 40,
        child: Icon(icon, size: 14, color: _Colors.secondaryText(context)),
      ),
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
          const SizedBox(height: 16),
          if (factors.isNotEmpty) _RiskReasoningTable(factors: factors),
        ],
      ),
    );
  }
}

class _RiskReasoningTable extends StatelessWidget {
  const _RiskReasoningTable({required this.factors});

  final List<RiskReasoningFactorModel> factors;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Table(
        border: TableBorder.all(color: _Colors.cardBorder(context)),
        columnWidths: const {
          0: FixedColumnWidth(40),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(2),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(color: _Colors.tableHeaderBg),
            children: [
              _TableHeaderCell('#'),
              _TableHeaderCell('Factor'),
              _TableHeaderCell('Value'),
              _TableHeaderCell('Severity'),
            ],
          ),
          for (var i = 0; i < factors.length; i++)
            TableRow(
              decoration: BoxDecoration(color: _Colors.card(context)),
              children: [
                _TableBodyCell('${i + 1}', textAlign: TextAlign.center),
                _TableBodyCell(factors[i].factor),
                _TableBodyCell(factors[i].value, textAlign: TextAlign.center),
                _TableBodyCell(
                  factors[i].severity,
                  textAlign: TextAlign.center,
                  color: _severityColor(factors[i].severity),
                  fontWeight: FontWeight.w700,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 10 : 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TableBodyCell extends StatelessWidget {
  const _TableBodyCell(
    this.text, {
    this.textAlign = TextAlign.left,
    this.color,
    this.fontWeight = FontWeight.w500,
  });

  final String text;
  final TextAlign textAlign;
  final Color? color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        textAlign: textAlign,
        style: GoogleFonts.poppins(
          fontSize: context.isMobileWidth ? 11 : 13,
          fontWeight: fontWeight,
          color: color ?? _Colors.primaryText(context),
        ),
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
    // value's own severity — e.g. a Moderate reading ends in an
    // orange-leaning blend, not the flat Low blue.
    final activePaint = Paint()
      ..shader = const SweepGradient(
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: [_Colors.gaugeLow, _Colors.gaugeCritical],
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

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.5),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                // flex 3:4:3 — the middle column's label ("30-Day Absence
                // Rate") is the longest, so it gets extra width to stay on
                // one line instead of wrapping.
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDownloadAssessment == null || downloading
                  ? null
                  : onDownloadAssessment,
              style: FilledButton.styleFrom(
                backgroundColor: _Colors.primaryAction,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                      fontSize: context.isMobileWidth ? 11 : 13,
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
