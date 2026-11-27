// lib/documents/parent_conference_report_pdf.dart
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

String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// What the Parent Conference Report prints.
class ParentConferenceData {
  const ParentConferenceData({
    required this.studentName,
    required this.studentNumber,
    required this.scheduledAt,
    required this.invitee,
    required this.status,
    this.section = '',
    this.location,
    this.parentAttended,
    this.summary,
    this.issuedBy = 'Student Affairs and Guidance Offices',
    this.schoolName = 'STI College Baliuag',
  });

  final String studentName;
  final String studentNumber;
  final String section;
  final DateTime scheduledAt;
  final String? location;

  /// `parent` or `both`.
  final String invitee;

  /// The meeting status; `Completed` prints as "Finished".
  final String status;

  /// Whether staff confirmed the parent attended (null: not yet confirmed).
  final bool? parentAttended;
  final String? summary;
  final String issuedBy;
  final String schoolName;

  String get statusLabel => switch (status) {
        'Completed' => 'Finished',
        'Reschedule_Requested' => 'Reschedule requested',
        _ => status,
      };

  String get inviteeLabel =>
      invitee == 'both' ? 'Parent / guardian and student' : 'Parent / guardian';

  String get attendanceLabel => parentAttended == null
      ? 'Not yet confirmed'
      : (parentAttended! ? 'Yes, the parent attended' : 'No, the parent did not attend');
}

/// Builds the printable confirmation of a meeting with a parent: who, when,
/// whether the parent attended, and what was discussed, with signature lines
/// for the parent and the staff member who held the meeting.
Future<Uint8List> buildParentConferenceReportPdf(ParentConferenceData d) async {
  pw.MemoryImage? logo;
  try {
    final bytes = await rootBundle.load(_kLogoAsset);
    logo = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    // No logo: the letterhead text still identifies the school.
  }

  final summary = (d.summary ?? '').trim();
  final pdf = pw.Document(title: 'Parent Conference Report');
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 40),
      footer: (_) => pw.Center(
        child: pw.Text(
          'Confidential: student record',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null)
              pw.SizedBox(width: 56, height: 56, child: pw.Image(logo)),
            if (logo != null) pw.SizedBox(width: 12),
            pw.Column(children: [
              pw.Text(d.schoolName.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('Baliuag, Bulacan, Philippines',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
              pw.Text(d.issuedBy, style: const pw.TextStyle(fontSize: 10)),
            ]),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 1.2),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text('PARENT CONFERENCE REPORT',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Center(
          child: pw.Text('Meeting confirmation',
              style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.SizedBox(height: 14),
        _table([
          ('Student', d.studentName),
          ('Student number', d.studentNumber),
          if (d.section.isNotEmpty) ('Section', d.section),
          ('Date', _longDate(d.scheduledAt)),
          ('Time', _time(d.scheduledAt)),
          if ((d.location ?? '').isNotEmpty) ('Place', d.location!),
          ('Invited', d.inviteeLabel),
          ('Meeting status', d.statusLabel),
          ('Parent attended', d.attendanceLabel),
        ]),
        pw.SizedBox(height: 12),
        pw.Text('Summary of the meeting',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          constraints: const pw.BoxConstraints(minHeight: 110),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
          ),
          child: pw.Text(
            summary.isEmpty ? 'No summary was recorded.' : summary,
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
          ),
        ),
        pw.SizedBox(height: 30),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: _signature('Parent / Guardian (printed name and signature)')),
            pw.SizedBox(width: 24),
            pw.Expanded(child: _signature('Date')),
          ],
        ),
        pw.SizedBox(height: 26),
        pw.Row(
          children: [
            pw.Expanded(
                child: _signature('Staff who held the meeting (name and signature)')),
            pw.SizedBox(width: 24),
            pw.Expanded(child: _signature('Date')),
          ],
        ),
      ],
    ),
  );
  return pdf.save();
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
