import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

void main() {
  test('GradeRemark.fromGrade maps all four bands correctly', () {
    expect(GradeRemark.fromGrade(95), GradeRemark.outstanding);
    expect(GradeRemark.fromGrade(90), GradeRemark.outstanding);
    expect(GradeRemark.fromGrade(87), GradeRemark.verySatisfactory);
    expect(GradeRemark.fromGrade(85), GradeRemark.verySatisfactory);
    expect(GradeRemark.fromGrade(80), GradeRemark.satisfactory);
    expect(GradeRemark.fromGrade(75), GradeRemark.satisfactory);
    // The bug this task exists to fix: below the passing threshold (75,
    // matching GradesView's own passingRate calculation) must be Failing,
    // never silently fall through to Outstanding.
    expect(GradeRemark.fromGrade(74.9), GradeRemark.failing);
    expect(GradeRemark.fromGrade(0), GradeRemark.failing);
  });
}
