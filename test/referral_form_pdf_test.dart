import 'dart:convert';

import 'package:capstone_dashboard/documents/referral_form_pdf.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReferralFormDocument doc(ReferralFormData form, {String details = 'Help.'}) =>
      ReferralFormDocument(
        form: form,
        referredOn: DateTime(2026, 11, 6),
        concernLabel: 'Academic difficulties',
        details: details,
        urgent: true,
      );

  test('builds a PDF for a filled-in self referral', () async {
    final bytes = await buildReferralFormPdf(doc(const ReferralFormData(
      studentName: 'Juan Dela Cruz',
      studentNumber: '2023-0001',
      section: 'BSIT 3A',
      address: '12 Rizal St',
      referralTo: ['Guidance Counselor'],
      academic: ['Test anxiety'],
      personal: ['Anxiety'],
      otherCareer: 'Switching course',
    )));
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  test('builds a blank-ish form for an old referral with no form', () async {
    final bytes = await buildReferralFormPdf(
        doc(const ReferralFormData(referralTo: [])));
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('a very long history flows onto more pages instead of failing',
      () async {
    final short = await buildReferralFormPdf(doc(const ReferralFormData()));
    final long = await buildReferralFormPdf(doc(const ReferralFormData(),
        details: List.filled(400, 'I am struggling with everything.').join(' ')));
    expect(long.length, greaterThan(short.length));
  });
}
