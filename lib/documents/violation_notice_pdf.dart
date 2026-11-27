// lib/documents/violation_notice_pdf.dart
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _kLogoAsset = 'packages/dashboard_layout/assets/images/STI_Baliuag_Logo.png';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _longDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// What the Parent Acknowledgment notice prints: the student, the violation
/// (with its offense tier), the sanction and, for a suspension, its dates.
class ViolationNoticeData {
  const ViolationNoticeData({
    required this.studentName,
    required this.studentNumber,
    required this.offenseTitle,
    required this.severity,
    required this.offenseLabel,
    required this.incidentDate,
    required this.sanctionType,
    required this.sanctionDescription,
    required this.effectiveOn,
    this.section = '',
    this.behaviorCategory,
    this.incidentNotes = '',
    this.endsOn,
    this.issuedBy = 'Office of Student Affairs and Discipline',
    this.schoolName = 'STI College Baliuag',
  });

  final String studentName;
  final String studentNumber;
  final String section;
  final String offenseTitle;

  /// `Minor` or `Major A`..`Major D`.
  final String severity;

  /// "1st Offense", "2nd Offense"...
  final String offenseLabel;
  final String? behaviorCategory;
  final DateTime incidentDate;
  final String incidentNotes;
  final String sanctionType;
  final String sanctionDescription;
  final DateTime effectiveOn;
  final DateTime? endsOn;
  final String issuedBy;
  final String schoolName;

  bool get isSuspension => sanctionType.toLowerCase() == 'suspension';

  /// "March 10, 2026 to March 12, 2026" or "Effective March 10, 2026".
  String get sanctionPeriodText => endsOn == null
      ? 'Effective ${_longDate(effectiveOn)}'
      : '${_longDate(effectiveOn)} to ${_longDate(endsOn!)}';
}

/// Builds the printable Notice of Violation and Sanction that a parent or
/// guardian signs to acknowledge the student's offense and sanction. The
/// school supplied no template, so this is a plain one-page formal notice
/// with a signature block for the parent and for the office.
Future<Uint8List> buildViolationNoticePdf(ViolationNoticeData d) async {
  pw.MemoryImage? logo;
  try {
    final bytes = await rootBundle.load(_kLogoAsset);
    logo = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    // No logo: the letterhead text still identifies the school.
  }

  final pdf = pw.Document(title: 'Notice of Violation and Sanction');
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 40),
      footer: (_) => pw.Center(
        child: pw.Text(
          'Confidential: student disciplinary record',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        _letterhead(logo, d),
        pw.SizedBox(height: 14),
        pw.Center(
          child: pw.Text(
            'NOTICE OF VIOLATION AND SANCTION',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text('Parent / Guardian Acknowledgment',
              style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.SizedBox(height: 14),
        pw.Text('Date issued: ${_longDate(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        pw.Text('Dear Parent / Guardian,',
            style: const pw.TextStyle(fontSize: 10.5)),
        pw.SizedBox(height: 6),
        pw.Text(
          'This is to inform you that your child, ${d.studentName}, has been '
          'recorded for a violation of the ${d.schoolName} Student Handbook. '
          'The details of the violation and the sanction imposed are as follows.',
          style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
        ),
        pw.SizedBox(height: 10),
        _table([
          ('Student', d.studentName),
          ('Student number', d.studentNumber),
          if (d.section.isNotEmpty) ('Section', d.section),
          ('Violation', d.offenseTitle),
          ('Severity', d.severity),
          ('Offense count', d.offenseLabel),
          if ((d.behaviorCategory ?? '').isNotEmpty)
            ('Behavior category', d.behaviorCategory!),
          ('Date of incident', _longDate(d.incidentDate)),
          if (d.incidentNotes.trim().isNotEmpty)
            ('Incident details', d.incidentNotes.trim()),
        ]),
        pw.SizedBox(height: 10),
        pw.Text('Sanction imposed',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _table([
          ('Sanction', d.sanctionType),
          ('Details', d.sanctionDescription),
          (
            d.isSuspension ? 'Suspension period' : 'Effective',
            d.sanctionPeriodText
          ),
        ]),
        pw.SizedBox(height: 14),
        pw.Text(
          'Please read this notice, sign below to acknowledge that you have been '
          'informed of the violation and the sanction, and return the signed '
          'copy to the ${d.issuedBy}. Your signature confirms that you have '
          'received this notice; it does not waive your right to raise a '
          'concern with the school.',
          style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
        ),
        pw.SizedBox(height: 26),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: _signature(
                    'Parent / Guardian (printed name and signature)')),
            pw.SizedBox(width: 24),
            pw.Expanded(child: _signature('Relationship to student')),
            pw.SizedBox(width: 24),
            pw.Expanded(child: _signature('Date signed')),
          ],
        ),
        pw.SizedBox(height: 26),
        pw.Row(
          children: [
            pw.Expanded(child: _signature('Issued by: ${d.issuedBy}')),
            pw.SizedBox(width: 24),
            pw.Expanded(child: _signature('Date received by the office')),
          ],
        ),
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _letterhead(pw.MemoryImage? logo, ViolationNoticeData d) {
  return pw.Column(children: [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null)
          pw.SizedBox(width: 56, height: 56, child: pw.Image(logo)),
        if (logo != null) pw.SizedBox(width: 12),
        pw.Column(children: [
          pw.Text(d.schoolName.toUpperCase(),
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Baliuag, Bulacan, Philippines',
              style:
                  const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Text(d.issuedBy, style: const pw.TextStyle(fontSize: 10)),
        ]),
      ],
    ),
    pw.SizedBox(height: 8),
    pw.Divider(thickness: 1.2),
  ]);
}

pw.Widget _table(List<(String, String)> rows) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(2),
      1: pw.FlexColumnWidth(5),
    },
    children: [
      for (final (label, value) in rows)
        pw.TableRow(children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ]),
    ],
  );
}

pw.Widget _signature(String label) {
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Container(
      height: 1,
      color: PdfColors.black,
      margin: const pw.EdgeInsets.only(top: 22),
    ),
    pw.SizedBox(height: 3),
    pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
  ]);
}
