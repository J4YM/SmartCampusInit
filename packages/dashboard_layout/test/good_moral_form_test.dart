import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

GoodMoralFormData _form({
  String lastName = 'Cruz',
  String firstName = 'Ana',
  String studentNumber = '2024-0001',
  String section = 'BSIT 3-A',
  String contactNumber = '0917 123 4567',
  String ayStarted = '2024-2025',
}) =>
    GoodMoralFormData(
      lastName: lastName,
      firstName: firstName,
      middleName: 'Reyes',
      address: 'Baliuag, Bulacan',
      studentNumber: studentNumber,
      section: section,
      contactNumber: contactNumber,
      ayStarted: ayStarted,
      ayLastAttended: '2026-2027',
      schoolStatus: 'Enrolled',
      reason: 'Employment',
    );

const _record = GoodMoralRecord(
  firstName: 'Ana',
  lastName: 'Cruz',
  studentNumber: '2024-0001',
  section: 'BSIT 3-A',
  contactNumber: '+63 917 123 4567',
  enrollmentYear: 2024,
);

FieldMatch _match(List<GoodMoralFieldCheck> checks, String label) =>
    checks.firstWhere((c) => c.label == label).match;

void main() {
  group('compareGoodMoralForm', () {
    test('an identical slip matches every field that is on record', () {
      final checks = compareGoodMoralForm(_form(), _record);
      expect(checks.where((c) => c.match == FieldMatch.mismatch), isEmpty);
      expect(_match(checks, 'Last name'), FieldMatch.match);
      expect(_match(checks, 'Contact number'), FieldMatch.match);
      expect(_match(checks, 'A.Y./Term started'), FieldMatch.match);
    });

    test('case, extra spaces and punctuation in a name are not a mismatch', () {
      final checks = compareGoodMoralForm(
          _form(lastName: '  CRUZ.  ', firstName: 'ana '), _record);
      expect(_match(checks, 'Last name'), FieldMatch.match);
      expect(_match(checks, 'First name'), FieldMatch.match);
    });

    test('a different name or student number is a mismatch', () {
      final checks = compareGoodMoralForm(
          _form(lastName: 'Santos', studentNumber: '2024-0009'), _record);
      expect(_match(checks, 'Last name'), FieldMatch.mismatch);
      expect(_match(checks, 'Student number'), FieldMatch.mismatch);
    });

    test('3-A and 3A are the same section; 3-B is not', () {
      expect(_match(compareGoodMoralForm(_form(section: 'bsit 3a'), _record),
          'Course/Section'), FieldMatch.match);
      expect(_match(compareGoodMoralForm(_form(section: 'BSIT 3-B'), _record),
          'Course/Section'), FieldMatch.mismatch);
    });

    test('contact numbers compare on their last ten digits', () {
      expect(_match(compareGoodMoralForm(_form(contactNumber: '09171234567'), _record),
          'Contact number'), FieldMatch.match);
      expect(_match(compareGoodMoralForm(_form(contactNumber: '0917 999 0000'), _record),
          'Contact number'), FieldMatch.mismatch);
    });

    test('the A.Y. started is judged by the first year written', () {
      expect(_match(compareGoodMoralForm(_form(ayStarted: 'AY 2023-2024'), _record),
          'A.Y./Term started'), FieldMatch.mismatch);
    });

    test('a field the school has no record of is notOnRecord, never mismatch',
        () {
      const sparse = GoodMoralRecord(firstName: 'Ana', lastName: 'Cruz');
      final checks = compareGoodMoralForm(_form(), sparse);
      expect(_match(checks, 'Contact number'), FieldMatch.notOnRecord);
      expect(_match(checks, 'Course/Section'), FieldMatch.notOnRecord);
      expect(_match(checks, 'A.Y./Term started'), FieldMatch.notOnRecord);
      for (final label in ['Middle name', 'Address', 'A.Y./Term last attended', 'School status']) {
        expect(_match(checks, label), FieldMatch.notOnRecord);
      }
      expect(checks.where((c) => c.match == FieldMatch.mismatch), isEmpty);
    });
  });

  group('GoodMoralFormData', () {
    test('survives a JSON round trip', () {
      final back = GoodMoralFormData.fromJson(_form().toJson());
      expect(back.toJson(), _form().toJson());
      expect(back.lastName, 'Cruz');
      expect(back.schoolStatus, 'Enrolled');
    });

    test('missing keys read as empty, never throw', () {
      final empty = GoodMoralFormData.fromJson({'last_name': 'Cruz'});
      expect(empty.firstName, '');
      expect(empty.lastName, 'Cruz');
    });

    test('remarks text is the labelled block the certificate has always used',
        () {
      expect(_form().remarksText(), [
        'Name: Cruz, Ana Reyes',
        'Address: Baliuag, Bulacan',
        'Student Number: 2024-0001',
        'Strand/Course/Section: BSIT 3-A',
        'Contact Number: 0917 123 4567',
        'A.Y./TERM started in STI: 2024-2025',
        'A.Y./TERM last attended in STI: 2026-2027',
        'School Status: Enrolled',
      ].join('\n'));
    });
  });
}
