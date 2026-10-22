import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case(String? status) => DisciplineCaseModel(
      id: 'c',
      studentName: 'Jane Doe',
      studentNumber: '24-0001',
      programGradeSection: 'BSIT-3A',
      violationType: 'Major – Fighting',
      submittedBy: 'Guard',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 1, 1),
      description: '',
      status: status,
    );

void main() {
  test('each stage of a case has its own label', () {
    expect(caseProgress(_case('Under_Investigation')).label,
        'Under investigation');
    expect(caseProgress(_case('Investigation_Complete')).label,
        'Investigation complete');
    expect(caseProgress(_case('Resolved')).label, 'Sanctioned');
    expect(caseProgress(_case('Pending')).label, 'Awaiting action');
  });

  testWidgets('the badge shows the case stage', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: CaseProgressBadge.forCase(_case('Under_Investigation'))),
    ));
    expect(find.text('Under investigation'), findsOneWidget);
  });
}
