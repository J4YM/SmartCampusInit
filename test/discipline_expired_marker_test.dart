import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case(String id, {DateTime? expiredAt}) =>
    DisciplineCaseModel(
      id: id,
      studentName: 'Student $id',
      studentNumber: '2024-$id',
      programGradeSection: 'BSIT 1A',
      violationType: 'Smoking',
      submittedBy: 'Prof Cruz',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 10, 15),
      description: '',
      status: 'Pending',
      expiredAt: expiredAt,
    );

Future<void> _pump(WidgetTester tester, List<DisciplineCaseModel> cases) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: ValidationQueueCard(
          cases: cases,
          selectedCaseId: null,
          onSelect: (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an expired case carries a red Expired marker in the queue',
      (tester) async {
    await _pump(tester, [_case('1', expiredAt: DateTime(2026, 10, 20))]);
    expect(find.byKey(const Key('queue-expired-badge')), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('a case that has not expired has no marker', (tester) async {
    await _pump(tester, [_case('1')]);
    expect(find.byKey(const Key('queue-expired-badge')), findsNothing);
  });

  testWidgets(
      "the Expired marker sits in the row's top-right corner, level with the "
      "student's name and not below the student info", (tester) async {
    await _pump(tester, [_case('1', expiredAt: DateTime(2026, 10, 20))]);
    final badge = tester.getRect(find.byKey(const Key('queue-expired-badge')));
    final name = tester.getRect(find.text('Student 1'));
    final number = tester.getRect(find.text('2024-1'));

    // Same top line as the name (not under the section / number lines)...
    expect(badge.top, lessThan(name.bottom));
    expect(badge.bottom, lessThan(number.top));
    // ...and out at the right edge of the row, well right of the name.
    expect(badge.left, greaterThan(name.right));
    final row = tester.getRect(find.byKey(const ValueKey('queue-row-1')));
    expect(row.right - badge.right, lessThan(30));
  });

  testWidgets('with several cases only the expired one is marked',
      (tester) async {
    await _pump(tester, [
      _case('1'),
      _case('2', expiredAt: DateTime(2026, 10, 20)),
    ]);
    expect(find.byKey(const Key('queue-expired-badge')), findsOneWidget);
  });
}
