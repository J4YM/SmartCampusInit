import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case({
  String? professorName = 'Ana Cruz',
  String? decision,
  String? note,
  bool filed = false,
}) =>
    DisciplineCaseModel(
      id: 'v1',
      studentName: 'Jane Doe',
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: 'Improper uniform',
      submittedBy: 'Kiosk',
      submitterRole: '',
      professorName: professorName,
      incidentDateTime: DateTime(2026, 1, 1),
      description: '',
      professorDecision: decision,
      professorDecisionNote: note,
      professorFiled: filed,
    );

Future<void> _pumpPanel(WidgetTester tester, DisciplineCaseModel c) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ViolationPreviewPanel(
          selectedCase: c,
          
          onModify: () {},
          onDelete: () {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a denial shows the badge and the professor\'s note',
      (tester) async {
    await _pumpPanel(
        tester, _case(decision: 'Denied', note: 'Student was in my class'));
    expect(find.text('Professor denied'), findsOneWidget);
    expect(find.text('"Student was in my class"'), findsOneWidget);
  });

  testWidgets('a confirmation shows the Confirmed badge', (tester) async {
    await _pumpPanel(tester, _case(decision: 'Confirmed'));
    expect(find.text('Professor confirmed'), findsOneWidget);
    expect(find.text('Professor denied'), findsNothing);
  });

  testWidgets('no answer yet reads as awaiting the professor', (tester) async {
    await _pumpPanel(tester, _case());
    expect(find.text('Awaiting professor'), findsOneWidget);
  });

  testWidgets('a report the professor filed is marked as theirs, not awaited',
      (tester) async {
    await _pumpPanel(tester, _case(filed: true));
    expect(find.text('Filed by the professor'), findsOneWidget);
    expect(find.text('Awaiting professor'), findsNothing);
  });

  testWidgets('a report with no professor named shows no badge',
      (tester) async {
    await _pumpPanel(tester, _case(professorName: null));
    expect(find.textContaining('rofessor'), findsNothing);
  });

  testWidgets('the badge appears in the queue row too and never blocks Validate',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var validated = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            SizedBox(
              height: 600,
              child: ValidationQueueCard(
                cases: [_case(decision: 'Denied')],
                selectedCaseId: null,
                onSelect: (_) {},
              ),
            ),
            ViolationPreviewPanel(
              selectedCase: _case(decision: 'Denied'),
              onSanction: () => validated++,
              onModify: () {},
              onDelete: () {},
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Professor denied'), findsNWidgets(2)); // queue row + panel

    await tester.tap(find.text('Sanction'));
    expect(validated, 1); // advisory only: a denial doesn't disable Sanction
  });

  testWidgets('a student with several violations shows it on each expanded row',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    DisciplineCaseModel mk(String id, String? decision) => DisciplineCaseModel(
          id: id,
          studentName: 'Jane Doe',
          studentNumber: '2024-0001',
          programGradeSection: 'BSIT 3-A',
          violationType: 'Improper uniform',
          submittedBy: 'Kiosk',
          submitterRole: '',
          professorName: 'Ana Cruz',
          incidentDateTime: DateTime(2026, 1, 1),
          description: '',
          professorDecision: decision,
        );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 900,
          child: ValidationQueueCard(
            cases: [mk('a', 'Denied'), mk('b', 'Confirmed')],
            selectedCaseId: null,
            onSelect: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jane Doe').first);
    await tester.pumpAndSettle();
    expect(find.text('Professor denied'), findsOneWidget);
    expect(find.text('Professor confirmed'), findsOneWidget);
  });
}
