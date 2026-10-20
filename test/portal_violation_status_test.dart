import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart' as parent;
import 'package:student_portal_module/student_portal_module.dart' as student;

/// A case is "Recorded" for a student or parent only once the officer has
/// sanctioned it. Anything still being handled, including a case whose
/// investigation is done but not yet sanctioned, is "Pending".
void main() {
  const open = [
    'Pending',
    'Under_Investigation',
    'Investigation_Complete',
    'investigation_complete',
  ];

  test('student portal: open statuses read as pending, Resolved as recorded', () {
    for (final s in open) {
      expect(student.ViolationStatusX.fromDbValue(s),
          student.ViolationStatus.pending,
          reason: s);
    }
    expect(student.ViolationStatusX.fromDbValue('Resolved'),
        student.ViolationStatus.recorded);
  });

  test('parent portal: open statuses read as pending, Resolved as recorded', () {
    for (final s in open) {
      expect(parent.ViolationStatusX.fromDbValue(s),
          parent.ViolationStatus.pending,
          reason: s);
    }
    expect(parent.ViolationStatusX.fromDbValue('Resolved'),
        parent.ViolationStatus.recorded);
  });
}
