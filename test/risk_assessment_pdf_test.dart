import 'package:capstone_dashboard/documents/risk_assessment_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';

void main() {
  test('buildRiskAssessmentPdf renders a non-empty PDF for a full result', () async {
    const input = StudentRiskInputModel(
      studentId: '2026-0001',
      currentGpa: 88,
      previousGpa: 94,
      totalClasses: 30,
      totalAbsences: 6,
      failingCourses: 1,
      maxConsecutiveAbsences: 3,
      daysSinceLastViolation: 10,
      recoveryScore: 0.4,
      recentAttendanceTrend: AttendanceTrend.increasing,
      minorCount: 2,
      majorACount: 1,
      majorBCount: 0,
      majorCCount: 0,
      majorDCount: 0,
    );
    const result = RiskAnalysisResultModel(
      dropoutRiskPercentage: 62,
      riskStatus: 'HIGH',
      riskProbabilityPercent: 55,
      confidencePercent: 80,
      absenceRatePercent: 20,
      thirtyDayAbsenceRatePercent: 25,
      gpaDeclinePercent: 6.4,
      riskReasoningFactors: [
        RiskReasoningFactorModel(factor: 'Declining GPA', value: '6.4', severity: 'MODERATE'),
      ],
      recommendedInterventions: ['Schedule counseling session'],
    );

    final bytes = await buildRiskAssessmentPdf(input: input, result: result);

    expect(bytes, isNotEmpty);
    // PDF magic header.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('buildRiskAssessmentPdf renders the neutral "Invalid" pre-analysis state '
      'without crashing (empty reasoning/interventions)', () async {
    const input = StudentRiskInputModel(
      studentId: '',
      currentGpa: 0,
      previousGpa: 0,
      totalClasses: 0,
      totalAbsences: 0,
      failingCourses: 0,
      maxConsecutiveAbsences: 0,
      daysSinceLastViolation: 0,
      recoveryScore: 0,
      recentAttendanceTrend: AttendanceTrend.stable,
      minorCount: 0,
      majorACount: 0,
      majorBCount: 0,
      majorCCount: 0,
      majorDCount: 0,
    );
    final result = RiskAnalysisResultModel.initial();

    final bytes = await buildRiskAssessmentPdf(input: input, result: result);

    expect(bytes, isNotEmpty);
  });
}
