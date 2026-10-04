// lib/documents/student_id_card_pdf.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// CR-80 card size (3.375in x 2.125in — standard ID/credit card) in
/// [orientation]. Matches [cardWidthPtFor]/[cardHeightPtFor] exactly — the
/// same canonical point space every IdCardTemplateElement's x/y/width/
/// height is stored in, so this renderer needs no unit conversion beyond
/// wrapping in a PdfPageFormat.
PdfPageFormat _cardFormatFor(IdCardOrientation orientation) => PdfPageFormat(
      cardWidthPtFor(orientation),
      cardHeightPtFor(orientation),
      marginAll: 0,
    );

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

  /// Lastname / First name, M.I. / Course — omits the trailing ", M.I."
  /// when the student has no middle initial on file, matching the
  /// editor's own _fullNameBlock (id_card_template_editor_page.dart).
  String get _fullNameBlock {
    final mi = middleInitial.trim();
    final firstLine = mi.isEmpty ? firstName : '$firstName, $mi.';
    return '$lastName\n$firstLine\n$course';
  }

  String valueFor(IdDataFieldKey key) {
    switch (key) {
      case IdDataFieldKey.fullName:
        return _fullNameBlock;
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

/// Treats a zero-alpha color the same as null — "no fill/stroke" — since
/// the pdf package's BoxDecoration/PdfGraphics never consult alpha
/// themselves; any non-null PdfColor paints fully opaque regardless of
/// its alpha byte.
PdfColor? _pdfColorOrNull(int? value) {
  if (value == null || (value >> 24) & 0xFF == 0) return null;
  return PdfColor.fromInt(value);
}

pw.TextAlign _pdfTextAlign(String? value) {
  switch (value) {
    case 'center':
      return pw.TextAlign.center;
    case 'right':
      return pw.TextAlign.right;
    default:
      return pw.TextAlign.left;
  }
}

/// The PDF only has the regular and bold Helvetica faces, so the editor's six
/// weights collapse to those two: Semi Bold (600) and heavier print bold.
pw.FontWeight _pdfFontWeight(int? weight) =>
    (weight ?? 400) >= 600 ? pw.FontWeight.bold : pw.FontWeight.normal;

/// An Image / ID Picture element: [image] in its frame with the element's crop
/// (zoom and which part shows), corner radius and opacity applied. Mirrors how
/// the editor's canvas draws it. An uncropped picture keeps [uncroppedFit].
pw.Widget _pictureWidget(
  IdCardTemplateElement element,
  pw.ImageProvider image, {
  required pw.BoxFit uncroppedFit,
}) {
  final zoom = (element.cropZoom ?? 1).clamp(1.0, 4.0).toDouble();
  final cropX = (element.cropX ?? 0).clamp(-1.0, 1.0).toDouble();
  final cropY = (element.cropY ?? 0).clamp(-1.0, 1.0).toDouble();
  final cropped = zoom > 1 || cropX != 0 || cropY != 0;

  pw.Widget picture;
  if (!cropped) {
    picture = pw.Image(image, fit: uncroppedFit);
  } else {
    final alignment = pw.Alignment(cropX, cropY);
    picture = pw.ClipRect(
      child: pw.OverflowBox(
        alignment: alignment,
        minWidth: 0,
        minHeight: 0,
        maxWidth: element.width * zoom,
        maxHeight: element.height * zoom,
        child: pw.SizedBox(
          width: element.width * zoom,
          height: element.height * zoom,
          child: pw.Image(image, fit: pw.BoxFit.cover, alignment: alignment),
        ),
      ),
    );
  }

  final radius = (element.cornerRadius ?? 0)
      .clamp(0.0, math.min(element.width, element.height) / 2)
      .toDouble();
  if (radius > 0) {
    picture = pw.ClipRRect(
      horizontalRadius: radius,
      verticalRadius: radius,
      child: picture,
    );
  }

  final opacity = (element.opacity ?? 1).clamp(0.0, 1.0).toDouble();
  return opacity >= 1 ? picture : pw.Opacity(opacity: opacity, child: picture);
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
        textAlign: _pdfTextAlign(element.textAlign),
        style: pw.TextStyle(
          fontSize: element.fontSize ?? 10,
          fontWeight: _pdfFontWeight(element.fontWeight),
          color: _pdfColorOrNull(element.color),
        ),
      );
    case IdCardElementType.idData:
      final key = element.fieldKey;
      return pw.Text(
        key == null ? '' : data.valueFor(key),
        textAlign: _pdfTextAlign(element.textAlign),
        style: pw.TextStyle(
          fontSize: element.fontSize ?? 10,
          fontWeight: _pdfFontWeight(element.fontWeight),
          color: _pdfColorOrNull(element.color),
        ),
      );
    case IdCardElementType.image:
      final bytes =
          element.imagePath == null ? null : imageBytesByPath[element.imagePath];
      if (bytes == null) return pw.SizedBox();
      return _pictureWidget(element, pw.MemoryImage(bytes),
          uncroppedFit: pw.BoxFit.contain);
    case IdCardElementType.idPicture:
      return _pictureWidget(element, pw.MemoryImage(data.photoBytes),
          uncroppedFit: pw.BoxFit.cover);
    case IdCardElementType.signature:
      final bytes = data.signatureBytes;
      if (bytes == null) return pw.SizedBox();
      return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    case IdCardElementType.rectangle:
    case IdCardElementType.roundedRect:
      final strokeColor = _pdfColorOrNull(element.strokeColor);
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: _pdfColorOrNull(element.fillColor),
          border: strokeColor == null
              ? null
              : pw.Border.all(
                  color: strokeColor,
                  width: element.strokeWidth ?? 1,
                ),
          borderRadius: (element.cornerRadius ?? 0) > 0
              ? pw.BorderRadius.circular((element.cornerRadius ?? 0)
                  .clamp(0.0, math.min(element.width, element.height) / 2)
                  .toDouble())
              : null,
        ),
      );
    case IdCardElementType.ellipse:
      final strokeColor = _pdfColorOrNull(element.strokeColor);
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: _pdfColorOrNull(element.fillColor),
          border: strokeColor == null
              ? null
              : pw.Border.all(
                  color: strokeColor,
                  width: element.strokeWidth ?? 1,
                ),
          shape: pw.BoxShape.circle,
        ),
      );
    case IdCardElementType.line:
      return pw.Container(
        color: _pdfColorOrNull(element.strokeColor),
      );
  }
}

pw.Widget _buildSide(
  List<IdCardTemplateElement> elements,
  IdCardPrintData data,
  Map<String, Uint8List> imageBytesByPath,
  int backgroundColor,
) {
  return pw.Container(
    color: PdfColor.fromInt(backgroundColor),
    child: pw.Stack(
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
    ),
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
  IdCardOrientation orientation = IdCardOrientation.landscape,
  int backgroundColor = 0xFFFFFFFF,
}) async {
  final cardFormat = _cardFormatFor(orientation);
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: cardFormat,
      build: (context) => _buildSide(frontLayout, data, imageBytesByPath, backgroundColor),
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: cardFormat,
      build: (context) => _buildSide(backLayout, data, imageBytesByPath, backgroundColor),
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
  IdCardOrientation orientation = IdCardOrientation.landscape,
  int backgroundColor = 0xFFFFFFFF,
}) async {
  final bytes = await buildIdCardPdf(
    frontLayout: frontLayout,
    backLayout: backLayout,
    data: data,
    imageBytesByPath: imageBytesByPath,
    orientation: orientation,
    backgroundColor: backgroundColor,
  );
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Student ID - $studentName',
    format: _cardFormatFor(orientation),
  );
}
