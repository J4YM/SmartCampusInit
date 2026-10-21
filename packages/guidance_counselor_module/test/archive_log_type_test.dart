import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_models.dart';

void main() {
  test('a sanction log written by the database reads as a Sanction', () {
    expect(ArchiveLogType.fromDb('sanction'), ArchiveLogType.sanction);
    expect(ArchiveLogType.sanction.label, 'Sanction');
  });

  test('the counselor cannot pick Sanction when adding a log by hand', () {
    expect(ArchiveLogType.manualChoices, isNot(contains(ArchiveLogType.sanction)));
    expect(ArchiveLogType.manualChoices, contains(ArchiveLogType.counseling));
  });
}
