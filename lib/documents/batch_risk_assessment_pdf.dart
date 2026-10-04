import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:guidance_counselor_module/pages/batch_student_analysis/batch_student_analysis_view.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// No `intl` dependency in this project — formats "September 30, 2026 at
/// 2:07 PM" by hand, matching risk_assessment_pdf.dart's own convention.
String _formatGeneratedAt(DateTime now) {
  final month = _months[now.month - 1];
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final period = now.hour < 12 ? 'AM' : 'PM';
  final minute = now.minute.toString().padLeft(2, '0');
  return '$month ${now.day}, ${now.year} at $hour12:$minute $period';
}

PdfColor _riskColor(String riskLevel) => switch (riskLevel) {
      'Critical' => const PdfColor.fromInt(0xFFDC2626),
      'High' => const PdfColor.fromInt(0xFFD97706),
      'Moderate' => const PdfColor.fromInt(0xFFCA8A04),
      'Low' => const PdfColor.fromInt(0xFF16A34A),
      _ => const PdfColor.fromInt(0xFF64748B),
    };

/// Renders the Batch Student Analysis tab's current "Analysis Result" table
/// into a printable record — backs the "Download Results" button
/// (BatchStudentAnalysisView.onDownloadResults). One row per analyzed
/// student, same columns as the on-screen table.
Future<Uint8List> buildBatchRiskAssessmentPdf({
  required List<BatchStudentRecordModel> records,
  required List<BatchAnalysisResultModel> results,
}) async {
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white);
  const cellStyle = pw.TextStyle(fontSize: 8);

  final totalStudents = results.length;
  final criticalCount = results.where((r) => r.riskLevel == 'Critical').length;
  final highCount = results.where((r) => r.riskLevel == 'High').length;
  final averageRisk = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (sum, r) => sum + r.dropoutProbabilityPercent) /
          results.length;

  pw.Widget summaryStat(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      );

  pw.Widget cellText(String text, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(text, style: style ?? cellStyle),
      );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
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
            'Batch Student Dropout-Risk Analysis',
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
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            summaryStat('Total Students', '$totalStudents'),
            summaryStat('Critical Risk', '$criticalCount'),
            summaryStat('High Risk', '$highCount'),
            summaryStat('Average Risk', '${averageRisk.toStringAsFixed(1)}%'),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5, color: const PdfColor.fromInt(0xFFCBD5E1)),
          columnWidths: const {
            0: pw.FixedColumnWidth(24),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1),
            4: pw.FlexColumnWidth(3),
            5: pw.FlexColumnWidth(1.1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF15253F)),
              children: [
                cellText('#', style: headerStyle),
                cellText('Student ID', style: headerStyle),
                cellText('Dropout Probability', style: headerStyle),
                cellText('Risk Level', style: headerStyle),
                cellText('Risk Reasoning', style: headerStyle),
                cellText('Early Warning 30D', style: headerStyle),
              ],
            ),
            for (var i = 0; i < results.length; i++)
              pw.TableRow(children: [
                cellText('${i + 1}'),
                cellText(results[i].studentId),
                cellText('${results[i].dropoutProbabilityPercent.toStringAsFixed(1)}%'),
                cellText(
                  results[i].riskLevel,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _riskColor(results[i].riskLevel),
                  ),
                ),
                cellText(results[i].riskReasoning),
                cellText(results[i].earlyWarning30D),
              ]),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// Saves [buildBatchRiskAssessmentPdf]'s output straight to a file the
/// counselor picks — matches exportRiskAssessmentPdf's own convention
/// (lib/documents/risk_assessment_pdf.dart).
Future<void> exportBatchRiskAssessmentPdf({
  required List<BatchStudentRecordModel> records,
  required List<BatchAnalysisResultModel> results,
}) async {
  final bytes = await buildBatchRiskAssessmentPdf(records: records, results: results);
  await FilePicker.saveFile(
    fileName: 'Batch_Risk_Analysis_${DateTime.now().millisecondsSinceEpoch}.pdf',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
}
