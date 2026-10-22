import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_models.dart';

void main() {
  test('Guidance logs hold only what the counselor records by hand', () {
    expect(ArchiveLogType.values.map((t) => t.dbValue),
        isNot(contains('sanction')));
    expect(ArchiveLogType.fromDb('sanction'), ArchiveLogType.other);
  });

  test('every log type can be picked when adding a log', () {
    expect(ArchiveLogType.values.map((t) => t.dbValue), [
      'counseling',
      'parent_conference',
      'intervention',
      'referral',
      'other',
    ]);
  });
}
