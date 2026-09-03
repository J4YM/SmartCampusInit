import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// CR-80 card size (3.375in x 2.125in — standard ID/credit card), landscape.
const _cardFormat = PdfPageFormat(
  3.375 * PdfPageFormat.inch,
  2.125 * PdfPageFormat.inch,
  marginAll: 10,
);

/// Everything printed on a student ID card — the "common fields already in
/// the system" (no photo/layout spec from ID Assist to replicate yet, per
/// the app owner).
class StudentIdCardData {
  const StudentIdCardData({
    required this.name,
    required this.studentNumber,
    required this.program,
    required this.section,
    required this.photoBytes,
  });

  final String name;
  final String studentNumber;
  final String program;
  final String section;
  final Uint8List photoBytes;
}

Future<Uint8List> buildStudentIdCardPdf(StudentIdCardData data) async {
  final photo = pw.MemoryImage(data.photoBytes);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: _cardFormat,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'STI COLLEGE BALIUAG',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 60,
                    height: 60,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Image(photo, fit: pw.BoxFit.cover),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          data.name,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          data.studentNumber,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          data.program,
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.Text(
                          data.section,
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.Divider(height: 1, thickness: 0.5),
            pw.Text(
              'This card is property of STI College Baliuag. If found, please '
              'return to the school.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

/// Opens the OS print dialog for [data]'s card — unlike the kiosk's silent
/// receipt printing, an IT Technician needs to consciously pick/confirm the
/// Fargo card printer (a specialized printer among whatever else is
/// installed), so this always shows the dialog rather than printing
/// straight to the default printer.
Future<void> printStudentIdCard(StudentIdCardData data) async {
  final bytes = await buildStudentIdCardPdf(data);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Student ID - ${data.name}',
    format: _cardFormat,
  );
}
