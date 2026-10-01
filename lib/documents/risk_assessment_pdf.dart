import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// No `intl` dependency in this project — formats "September 30, 2026 at
/// 2:07 PM" by hand, matching the plain-Dart date formatting already used
/// elsewhere in this codebase.
String _formatGeneratedAt(DateTime now) {
  final month = _months[now.month - 1];
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final period = now.hour < 12 ? 'AM' : 'PM';
  final minute = now.minute.toString().padLeft(2, '0');
  return '$month ${now.day}, ${now.year} at $hour12:$minute $period';
}

/// Renders the Single Student Analysis tab's current gauge/reasoning/
/// interventions into a one-page printable record — backs the "Download
/// Assessment" button (SingleStudentAnalysisView.onDownloadAssessment).
Future<Uint8List> buildRiskAssessmentPdf({
  required StudentRiskInputModel input,
  required RiskAnalysisResultModel result,
}) async {
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11);
  const labelStyle = pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B));
  const valueStyle = pw.TextStyle(fontSize: 10.5);

  pw.Widget field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8, right: 16),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: labelStyle),
            pw.SizedBox(height: 2),
            pw.Text(value, style: valueStyle),
          ],
        ),
      );

  pw.Widget fieldRow(List<pw.Widget> fields) => pw.Wrap(children: fields);

  final statusColor = switch (result.riskStatus) {
    'CRITICAL' => const PdfColor.fromInt(0xFFDC2626),
    'HIGH' => const PdfColor.fromInt(0xFFD97706),
    'MODERATE' => const PdfColor.fromInt(0xFFCA8A04),
    'LOW' => const PdfColor.fromInt(0xFF16A34A),
    _ => const PdfColor.fromInt(0xFF64748B),
  };

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Center(
          child: pw.Text(
            'STI COLLEGE BALIUAG',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Guidance Office',
            style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B)),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'Student Dropout-Risk Assessment',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'Generated ${_formatGeneratedAt(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B)),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.75),
        pw.SizedBox(height: 12),

        pw.Text('Student Risk Parameters', style: headerStyle),
        pw.SizedBox(height: 8),
        fieldRow([
          field('Student ID', input.studentId.isEmpty ? '-' : input.studentId),
          field('Current GPA', input.currentGpa.toStringAsFixed(2)),
          field('Previous GPA', input.previousGpa.toStringAsFixed(2)),
          field('Total Classes', '${input.totalClasses}'),
        ]),
        fieldRow([
          field('Total Absences', '${input.totalAbsences}'),
          field('Failing Courses', '${input.failingCourses}'),
          field('Max Consecutive Absences', '${input.maxConsecutiveAbsences}'),
          field('Days Since Last Violation', '${input.daysSinceLastViolation}'),
        ]),
        fieldRow([
          field('Recovery Score', input.recoveryScore.toStringAsFixed(2)),
          field('Recent Attendance Trend', input.recentAttendanceTrend.label),
        ]),
        pw.SizedBox(height: 4),
        pw.Text('Violations', style: headerStyle),
        pw.SizedBox(height: 8),
        fieldRow([
          field('Minor', '${input.minorCount}'),
          field('Major A', '${input.majorACount}'),
          field('Major B', '${input.majorBCount}'),
          field('Major C', '${input.majorCCount}'),
          field('Major D', '${input.majorDCount}'),
        ]),

        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.75),
        pw.SizedBox(height: 12),

        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: statusColor, width: 1.2),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Dropout Risk: ${result.dropoutRiskPercentage.toStringAsFixed(0)}%  -  ${result.riskStatus}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: statusColor),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Risk Probability: ${result.riskProbabilityPercent.toStringAsFixed(0)}%   '
                'Confidence: ${result.confidencePercent.toStringAsFixed(0)}%',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Absence Rate: ${result.absenceRatePercent.toStringAsFixed(1)}%   '
                '30-Day Absence Rate: ${result.thirtyDayAbsenceRatePercent.toStringAsFixed(1)}%   '
                'GPA Decline: ${result.gpaDeclinePercent.toStringAsFixed(1)}%',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 16),
        pw.Text('Risk Reasoning', style: headerStyle),
        pw.SizedBox(height: 8),
        if (result.riskReasoningFactors.isEmpty)
          pw.Text('No contributing factors recorded.', style: const pw.TextStyle(fontSize: 9.5))
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: const PdfColor.fromInt(0xFFCBD5E1)),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.5), 2: pw.FlexColumnWidth(1.5)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF15253F)),
                children: [
                  _headerCell('Factor'),
                  _headerCell('Value'),
                  _headerCell('Severity'),
                ],
              ),
              for (final factor in result.riskReasoningFactors)
                pw.TableRow(children: [
                  _bodyCell(factor.factor),
                  _bodyCell(factor.value, align: pw.TextAlign.center),
                  _bodyCell(factor.severity, align: pw.TextAlign.center),
                ]),
            ],
          ),

        pw.SizedBox(height: 16),
        pw.Text('Recommended Interventions', style: headerStyle),
        pw.SizedBox(height: 8),
        if (result.recommendedInterventions.isEmpty)
          pw.Text('None recorded.', style: const pw.TextStyle(fontSize: 9.5))
        else
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final item in result.recommendedInterventions)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text('-  $item', style: const pw.TextStyle(fontSize: 9.5)),
                ),
            ],
          ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _headerCell(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );

pw.Widget _bodyCell(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(text, textAlign: align, style: const pw.TextStyle(fontSize: 9)),
    );

/// Saves [buildRiskAssessmentPdf]'s output straight to a file the counselor
/// picks — a real download, matching exportSectionSchedulePdf's own
/// convention (lib/documents/section_schedule_pdf.dart).
Future<void> exportRiskAssessmentPdf({
  required StudentRiskInputModel input,
  required RiskAnalysisResultModel result,
}) async {
  final bytes = await buildRiskAssessmentPdf(input: input, result: result);
  final studentLabel = input.studentId.isEmpty ? 'Student' : input.studentId;
  await FilePicker.saveFile(
    fileName: 'Risk_Assessment_${studentLabel.replaceAll(RegExp(r'[^\w-]'), '_')}.pdf',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
}
