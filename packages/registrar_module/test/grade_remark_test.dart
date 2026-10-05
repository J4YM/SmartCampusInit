import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

void main() {
  test('GradeRemark.fromGrade maps all four bands correctly on the '
      'Philippine 1.00-5.00 scale (1.00 = best, lower is better)', () {
    expect(GradeRemark.fromGrade(1.00), GradeRemark.outstanding);
    expect(GradeRemark.fromGrade(1.50), GradeRemark.outstanding);
    expect(GradeRemark.fromGrade(1.75), GradeRemark.verySatisfactory);
    expect(GradeRemark.fromGrade(2.00), GradeRemark.verySatisfactory);
    expect(GradeRemark.fromGrade(2.25), GradeRemark.satisfactory);
    expect(GradeRemark.fromGrade(3.00), GradeRemark.satisfactory);
    // Above the passing threshold (3.00, matching GradesView's own
    // passingRate calculation and gwaToPercentage's own breakpoint
    // ceiling) must be Failing, never silently fall through to
    // Outstanding.
    expect(GradeRemark.fromGrade(3.25), GradeRemark.failing);
    expect(GradeRemark.fromGrade(5.00), GradeRemark.failing);
  });
}
