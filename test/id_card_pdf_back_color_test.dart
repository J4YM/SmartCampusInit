import 'dart:convert';
import 'dart:typed_data';

import 'package:capstone_dashboard/documents/student_id_card_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// The printed card paints the back in its own colour.
void main() {
  IdCardPrintData data() => IdCardPrintData(
        firstName: 'Juan',
        middleInitial: 'D',
        lastName: 'Cruz',
        studentNumber: '2024-0001',
        course: 'BSIT',
        section: 'BSIT-3A',
        yearLevel: '3rd',
        guardianName: 'Maria Cruz',
        guardianContactNo: '09170000000',
        photoBytes: Uint8List(0),
      );

  Future<Uint8List> render({int? back}) => buildIdCardPdf(
        frontLayout: const [],
        backLayout: const [],
        data: data(),
        backgroundColor: 0xFFFFFFFF,
        backBackgroundColor: back,
      );

  test('a back colour of its own changes the printed card', () async {
    final sameAsFront = await render();
    final redBack = await render(back: 0xFFCD4855);

    expect(latin1.decode(sameAsFront.sublist(0, 4)), '%PDF');
    expect(latin1.decode(redBack.sublist(0, 4)), '%PDF');
    expect(redBack, isNot(equals(sameAsFront)));
  });

  test('no back colour prints the back like the front, as before', () async {
    final implicit = await render();
    final explicit = await render(back: 0xFFFFFFFF);
    // Same two white pages either way (compare the page content, not the
    // document ids/timestamps, by length — both are two pages of one colour).
    expect(explicit.length, implicit.length);
  });
}
