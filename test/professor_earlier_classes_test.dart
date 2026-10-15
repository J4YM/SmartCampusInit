import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

void main() {
  test('ProfessorSectionModel round-trips classSectionId', () {
    const model = ProfessorSectionModel(
      id: 's1',
      name: 'BSIT 3A',
      studentCount: 30,
      classSectionId: 'c1',
    );
    final back = ProfessorSectionModel.fromJson(model.toJson());
    expect(back.classSectionId, 'c1');
  });
}
