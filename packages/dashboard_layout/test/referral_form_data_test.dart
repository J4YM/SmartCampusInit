import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the form survives a round trip through its stored JSON', () {
    const form = ReferralFormData(
      studentName: 'Juan Dela Cruz',
      studentNumber: '2023-0001',
      section: 'BSIT 3A',
      contactNumber: '0917',
      address: '12 Rizal St',
      birthdate: '05/14/2004',
      program: 'BSIT',
      referralTo: ['Guidance Counselor', 'Psychologist'],
      referralToOther: 'Clinic',
      academic: ['Absenteeism'],
      personal: ['Anxiety', 'Loneliness'],
      career: ['Shifting'],
      otherAcademic: 'Group work',
      otherPersonal: 'Home',
      otherCareer: 'Plans',
    );
    final back = ReferralFormData.fromJson(form.toJson());
    expect(back.toJson(), form.toJson());
    expect(back.referralTo, ['Guidance Counselor', 'Psychologist']);
    expect(back.pickedConcerns, [
      'Absenteeism',
      'Group work',
      'Anxiety',
      'Loneliness',
      'Home',
      'Shifting',
      'Plans',
    ]);
  });

  test('a missing or malformed stored form reads as empty', () {
    for (final raw in [null, 'x', 3, <dynamic>[]]) {
      final form = ReferralFormData.fromJson(raw);
      expect(form.referralTo, isEmpty);
      expect(form.hasPickedConcerns, isFalse);
    }
    final partial = ReferralFormData.fromJson({'academic': [' Test anxiety ', '']});
    expect(partial.academic, ['Test anxiety']);
    expect(partial.address, '');
  });

  test('the school year runs June to May', () {
    ReferralFormDocument at(DateTime d) => ReferralFormDocument(
        form: const ReferralFormData(),
        referredOn: d,
        concernLabel: '',
        details: '');
    expect(at(DateTime(2026, 6, 1)).schoolYear, '2026 - 2027');
    expect(at(DateTime(2026, 11, 6)).schoolYear, '2026 - 2027');
    expect(at(DateTime(2027, 5, 31)).schoolYear, '2026 - 2027');
    expect(at(DateTime(2027, 1, 15)).schoolYear, '2026 - 2027');
  });
}
