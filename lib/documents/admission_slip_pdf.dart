import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

/// Sized for a 58mm thermal roll printer (e.g. the kiosk's Y-58 label
/// printer). NOT `PdfPageFormat.roll57` (57mm wide, 5mm margins — 47mm
/// usable): a real print against the Y-58 came back with the right edge
/// clipped (the title's last letter, the Slip ID UUID wrapping early),
/// meaning this specific driver's actual printable area is narrower than
/// the nominal 57mm roll57 assumes. Deliberately narrower than the
/// generic "48mm printable" industry figure too, with generous margins —
/// there's no way to query this driver's exact printable width from here,
/// so this trades a bit of unused paper for margin against whatever this
/// driver's real constraint turns out to be. Auto/infinite height so the
/// driver cuts wherever the content ends. A single narrow column, not the
/// two-column label/value rows an A5 sheet had room for.
const _kSlipPageFormat = PdfPageFormat(
  44 * PdfPageFormat.mm,
  double.infinity,
  marginAll: 3 * PdfPageFormat.mm,
);

Future<Uint8List> buildAdmissionSlipPdf(AdmissionSlipData data) async {
  pw.MemoryImage? qrImage;
  if (data.qrUrl.isNotEmpty) {
    final qrBytes = await _qrImageBytes(data.qrUrl);
    if (qrBytes != null) qrImage = pw.MemoryImage(qrBytes);
  }

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: _kSlipPageFormat,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'VIRTUAL ADMISSION SLIP',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Disciplinary Office',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            _field('Student Name', data.studentName),
            _field('Student Number', data.studentNumber),
            _field('Grade & Section', data.gradeSection),
            _field('Slip ID', data.slipId),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Text(
              'ACKNOWLEDGED VIOLATION',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${data.violationCode}: ${data.violationDescription}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            _field('Issued', data.issueDateTime),
            _field('Valid Until', data.validUntil),
            if (qrImage != null) ...[
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Image(qrImage, width: 90, height: 90)),
            ],
            pw.SizedBox(height: 8),
            pw.Text(
              'Valid for 72 hours only. Present this to your teacher before '
              'entering class. Duplicating or forging this slip will result '
              'in additional disciplinary action.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
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

/// Label above value, not side-by-side — a 38mm-wide receipt has no room
/// for the two-column layout the old A5 slip used.
pw.Widget _field(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}
