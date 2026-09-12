import 'dart:convert';
import 'dart:typed_data';

import 'package:capstone_dashboard/documents/student_id_card_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// A minimal valid 1x1 transparent PNG — `pw.MemoryImage` (used for the
/// idPicture/signature/image elements) decodes real image magic bytes, so
/// arbitrary filler bytes won't do; this is the smallest input that is
/// actually a valid, decodable image.
final _minimalPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

void main() {
  test('buildIdCardPdf renders a template containing every element type '
      'without throwing, and produces non-empty PDF bytes', () async {
    final photoBytes = Uint8List.fromList(_minimalPngBytes);
    final signatureBytes = Uint8List.fromList(_minimalPngBytes);

    final layout = <IdCardTemplateElement>[
      const IdCardTemplateElement(
        id: 'text',
        type: IdCardElementType.staticText,
        x: 5,
        y: 5,
        width: 60,
        height: 12,
        textContent: 'STI Baliuag',
        fontSize: 8,
        color: 0xFF000000,
        textAlign: 'center',
      ),
      const IdCardTemplateElement(
        id: 'idData',
        type: IdCardElementType.idData,
        x: 5,
        y: 20,
        width: 60,
        height: 12,
        fieldKey: IdDataFieldKey.firstName,
        fontSize: 8,
      ),
      const IdCardTemplateElement(
        id: 'image',
        type: IdCardElementType.image,
        x: 5,
        y: 35,
        width: 20,
        height: 20,
        imagePath: 'unused/path.png',
      ),
      const IdCardTemplateElement(
        id: 'photo',
        type: IdCardElementType.idPicture,
        x: 30,
        y: 35,
        width: 20,
        height: 20,
      ),
      const IdCardTemplateElement(
        id: 'signature',
        type: IdCardElementType.signature,
        x: 55,
        y: 35,
        width: 20,
        height: 20,
      ),
      const IdCardTemplateElement(
        id: 'rect',
        type: IdCardElementType.rectangle,
        x: 5,
        y: 60,
        width: 30,
        height: 15,
        fillColor: 0x00000000,
        strokeColor: 0xFF000000,
        strokeWidth: 1,
      ),
      const IdCardTemplateElement(
        id: 'roundedRect',
        type: IdCardElementType.roundedRect,
        x: 40,
        y: 60,
        width: 30,
        height: 15,
        fillColor: 0xFFCD4855,
        strokeColor: 0xFF000000,
        strokeWidth: 1,
        cornerRadius: 4,
      ),
      const IdCardTemplateElement(
        id: 'ellipse',
        type: IdCardElementType.ellipse,
        x: 5,
        y: 80,
        width: 20,
        height: 20,
        fillColor: 0xFF137333,
      ),
      const IdCardTemplateElement(
        id: 'line',
        type: IdCardElementType.line,
        x: 5,
        y: 105,
        width: 80,
        height: 1,
        strokeColor: 0xFF000000,
      ),
    ];

    final data = IdCardPrintData(
      firstName: 'Juan',
      middleInitial: 'D',
      lastName: 'Dela Cruz',
      studentNumber: '02000123456',
      course: 'BSIT',
      section: 'IT-101',
      yearLevel: '1st Year',
      guardianName: 'Maria Dela Cruz',
      guardianContactNo: '09171234567',
      photoBytes: photoBytes,
      signatureBytes: signatureBytes,
    );

    final bytes = await buildIdCardPdf(
      frontLayout: layout,
      backLayout: layout,
      data: data,
      imageBytesByPath: {'unused/path.png': photoBytes},
    );

    expect(bytes, isNotEmpty);
  });

  test('buildIdCardPdf handles an empty layout without throwing', () async {
    final data = IdCardPrintData(
      firstName: 'Juan',
      middleInitial: '',
      lastName: 'Dela Cruz',
      studentNumber: '02000123456',
      course: 'BSIT',
      section: 'IT-101',
      yearLevel: '1st Year',
      guardianName: '',
      guardianContactNo: '',
      photoBytes: Uint8List.fromList(List.filled(16, 0)),
    );

    final bytes = await buildIdCardPdf(
      frontLayout: const [],
      backLayout: const [],
      data: data,
    );

    expect(bytes, isNotEmpty);
  });
}
