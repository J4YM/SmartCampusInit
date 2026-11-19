import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case() => DisciplineCaseModel(
      id: 'v1',
      studentId: 's1',
      studentName: 'Juan Dela Cruz',
      studentNumber: '2026-0001',
      programGradeSection: 'BSIT-3A',
      violationType: 'Tardiness',
      submittedBy: 'Prof. Reyes',
      submitterRole: 'Professor',
      incidentDateTime: DateTime(2026, 11, 18, 8),
      description: 'Late',
    );

void main() {
  testWidgets('the history sheet offers Sanction history when it can load it',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentViolationHistorySheet(
          group: groupCasesByStudent([_case()]).single,
          onViewSanctions: () => opened++,
        ),
      ),
    ));
    await tester.tap(find.text('Sanction history'));
    expect(opened, 1);
  });

  testWidgets('without a loader the sheet has no Sanction history button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentViolationHistorySheet(
          group: groupCasesByStudent([_case()]).single,
        ),
      ),
    ));
    expect(find.text('Sanction history'), findsNothing);
  });

  test('a case carries the student id it was created with', () {
    expect(_case().studentId, 's1');
    expect(_case().copyWith(status: 'Resolved').studentId, 's1');
  });
}
