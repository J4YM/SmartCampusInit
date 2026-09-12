// lib/documents/student_id_card_pdf.dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// CR-80 card size (3.375in x 2.125in — standard ID/credit card),
/// landscape. Matches [idCardWidthPt]/[idCardHeightPt] exactly — the same
/// canonical point space every IdCardTemplateElement's x/y/width/height
/// is stored in, so this renderer needs no unit conversion beyond
/// wrapping in a PdfPageFormat.
final _cardFormat = PdfPageFormat(idCardWidthPt, idCardHeightPt, marginAll: 0);

/// The real, per-student values an `idData` element's [IdDataFieldKey]
/// resolves to at print time.
class IdCardPrintData {
  const IdCardPrintData({
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.studentNumber,
    required this.course,
    required this.section,
    required this.yearLevel,
    required this.guardianName,
    required this.guardianContactNo,
    required this.photoBytes,
    this.signatureBytes,
  });

  final String firstName;
  final String middleInitial;
  final String lastName;
  final String studentNumber;
  final String course;
  final String section;
  final String yearLevel;
  final String guardianName;
  final String guardianContactNo;
  final Uint8List photoBytes;

  /// Null when the student hasn't had a signature captured yet — a
  /// `signature`-type element then renders as a blank box.
  final Uint8List? signatureBytes;

  String valueFor(IdDataFieldKey key) {
    switch (key) {
      case IdDataFieldKey.firstName:
        return firstName;
      case IdDataFieldKey.middleInitial:
        return middleInitial;
      case IdDataFieldKey.lastName:
        return lastName;
      case IdDataFieldKey.studentNumber:
        return studentNumber;
      case IdDataFieldKey.course:
        return course;
      case IdDataFieldKey.section:
        return section;
      case IdDataFieldKey.yearLevel:
        return yearLevel;
      case IdDataFieldKey.guardianName:
        return guardianName;
      case IdDataFieldKey.guardianContactNo:
        return guardianContactNo;
    }
  }
}

pw.Widget _renderElement(
  IdCardTemplateElement element,
  IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath,
) {
  switch (element.type) {
    case IdCardElementType.staticText:
      return pw.Text(
        element.textContent ?? '',
        style: pw.TextStyle(fontSize: element.fontSize ?? 10),
      );
    case IdCardElementType.idData:
      final key = element.fieldKey;
      return pw.Text(
        key == null ? '' : data.valueFor(key),
        style: pw.TextStyle(fontSize: element.fontSize ?? 10),
      );
    case IdCardElementType.image:
      final bytes =
          element.imagePath == null ? null : imageBytesByPath[element.imagePath];
      if (bytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    case IdCardElementType.idPicture:
      return pw.Image(pw.MemoryImage(data.photoBytes), fit: pw.BoxFit.cover);
    case IdCardElementType.signature:
      final bytes = data.signatureBytes;
      if (bytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    case IdCardElementType.rectangle:
    case IdCardElementType.roundedRect:
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: element.fillColor == null
              ? null
              : PdfColor.fromInt(element.fillColor!),
          border: element.strokeColor == null
              ? null
              : pw.Border.all(
                  color: PdfColor.fromInt(element.strokeColor!),
                  width: element.strokeWidth ?? 1,
                ),
          borderRadius: element.type == IdCardElementType.roundedRect
              ? pw.BorderRadius.circular(element.cornerRadius ?? 0)
              : null,
        ),
      );
    case IdCardElementType.ellipse:
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: element.fillColor == null
              ? null
              : PdfColor.fromInt(element.fillColor!),
          border: element.strokeColor == null
              ? null
              : pw.Border.all(
                  color: PdfColor.fromInt(element.strokeColor!),
                  width: element.strokeWidth ?? 1,
                ),
          shape: pw.BoxShape.circle,
        ),
      );
    case IdCardElementType.line:
      return pw.Container(
        color:
            element.strokeColor == null ? null : PdfColor.fromInt(element.strokeColor!),
      );
  }
}

pw.Widget _buildSide(
  List<IdCardTemplateElement> elements,
  IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath,
) {
  return pw.Stack(
    children: [
      for (final element in elements)
        pw.Positioned(
          left: element.x,
          top: element.y,
          child: pw.SizedBox(
            width: element.width,
            height: element.height,
            child: _renderElement(element, data, imageBytesByPath),
          ),
        ),
    ],
  );
}

/// Renders [frontLayout]/[backLayout] (a template's two element lists —
/// see [IdCardTemplateElement]) with [data]'s real per-student values
/// into a two-page PDF (front, then back), ready for print or preview.
/// [imageBytesByPath] supplies the already-downloaded bytes for every
/// `image`-type element's `imagePath` — this renderer does no network
/// fetching of its own.
Future<Uint8List> buildIdCardPdf({
  required List<IdCardTemplateElement> frontLayout,
  required List<IdCardTemplateElement> backLayout,
  required IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath = const {},
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: _cardFormat,
      build: (context) => _buildSide(frontLayout, data, imageBytesByPath),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: _cardFormat,
      build: (context) => _buildSide(backLayout, data, imageBytesByPath),
    ),
  );
  return doc.save();
}

/// Opens the OS print dialog for the rendered card — unlike the kiosk's
/// silent receipt printing, an IT Technician needs to consciously
/// pick/confirm the Fargo card printer (a specialized printer among
/// whatever else is installed), so this always shows the dialog rather
/// than printing straight to the default printer.
Future<void> printIdCard({
  required List<IdCardTemplateElement> frontLayout,
  required List<IdCardTemplateElement> backLayout,
  required IdCardPrintData data,
  required String studentName,
  Map<String, Uint8List> imageBytesByPath = const {},
}) async {
  final bytes = await buildIdCardPdf(
    frontLayout: frontLayout,
    backLayout: backLayout,
    data: data,
    imageBytesByPath: imageBytesByPath,
  );
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Student ID - $studentName',
    format: _cardFormat,
  );
}
