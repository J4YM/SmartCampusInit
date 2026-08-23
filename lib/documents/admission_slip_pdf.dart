import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

Future<Uint8List> buildAdmissionSlipPdf(AdmissionSlipData data) async {
  pw.MemoryImage? qrImage;
  if (data.qrUrl.isNotEmpty) {
    final qrBytes = await _qrImageBytes(data.qrUrl);
    if (qrBytes != null) qrImage = pw.MemoryImage(qrBytes);
  }

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'VIRTUAL ADMISSION SLIP',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Disciplinary Office',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.SizedBox(height: 8),
            _row('Student Name', data.studentName),
            _row('Student Number', data.studentNumber),
            _row('Grade & Section', data.gradeSection),
            _row('Slip ID', data.slipId),
            pw.SizedBox(height: 8),
            pw.Text(
              'Acknowledged Violations',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${data.violationCode}: ${data.violationDescription}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            _row('Issue Date & Time', data.issueDateTime),
            _row('Valid Until', data.validUntil),
            pw.SizedBox(height: 16),
            if (qrImage != null)
              pw.Center(child: pw.Image(qrImage, width: 120, height: 120)),
            pw.SizedBox(height: 12),
            pw.Text(
              'This admission slip is valid for 72 hours only. Present this '
              'to your teacher before entering class. Any attempt to '
              'duplicate or forge this slip will result in additional '
              'disciplinary action.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

/// Prints [data] straight to the system's default printer with no dialog —
/// for the kiosk's "Confirm & Print" flow, where the printer is a dedicated
/// thermal printer and nobody is available to operate a print dialog.
/// Never throws: every failure (unsupported platform, no printers, a
/// printer error) is caught and only logged, since a failed print isn't
/// something the student at the kiosk can act on.
Future<void> silentPrintAdmissionSlip(AdmissionSlipData data) async {
  try {
    final info = await Printing.info();
    if (!info.canListPrinters || !info.directPrint) {
      debugPrint('Silent print unavailable on this platform.');
      return;
    }
    final printers = await Printing.listPrinters();
    if (printers.isEmpty) {
      debugPrint('Silent print failed: no printers found.');
      return;
    }
    final printer = printers.firstWhere(
      (p) => p.isDefault,
      orElse: () => printers.first,
    );
    final bytes = await buildAdmissionSlipPdf(data);
    await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => bytes,
      name: 'Admission Slip ${data.slipId}',
    );
  } catch (e) {
    debugPrint('Silent print failed: $e');
  }
}

Future<Uint8List?> _qrImageBytes(String data, {double size = 300}) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: true,
  );
  final imageData = await painter.toImageData(size);
  return imageData?.buffer.asUint8List();
}

pw.Widget _row(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 110,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ),
  );
}
