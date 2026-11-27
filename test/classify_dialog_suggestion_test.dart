import 'package:dashboard_layout/dashboard_layout.dart' show FilterLabelBand;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _report(String description) => DisciplineCaseModel(
      id: 'v1',
      studentName: 'Jane Doe',
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: 'Awaiting classification',
      submittedBy: 'Prof Cruz',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 10, 19, 14, 30),
      filedAt: DateTime(2026, 10, 20, 9, 0),
      description: description,
      status: 'Pending',
      isClassified: false,
    );

const _options = [
  OffenseOption(
      id: 'a',
      label: 'Cheating during quizzes, exams, or graded activities',
      category: 'Major_A',
      behaviorCategory: 'Academic_Integrity'),
  OffenseOption(
      id: 'b',
      label: 'No valid ID worn inside campus',
      category: 'Minor',
      behaviorCategory: 'Uniform_Dress_Code'),
];

Future<void> _pump(WidgetTester tester, String description) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ClassifyDialog(
          caseItem: _report(description), offenseOptions: _options),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('suggests a category and offense from the report text',
      (tester) async {
    await _pump(tester, 'Caught cheating during the midterm exam');
    expect(find.byKey(const Key('classify-suggested-category')),
        findsOneWidget);
    expect(find.text('Category: Academic Integrity'), findsOneWidget);
    expect(find.byKey(const Key('classify-suggestion-a')), findsOneWidget);
    expect(find.byKey(const Key('classify-suggestion-b')), findsNothing);
  });

  testWidgets('tapping a suggestion selects it', (tester) async {
    await _pump(tester, 'Caught cheating during the midterm exam');
    await tester.tap(find.byKey(const Key('classify-suggestion-a')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('shows no suggestion block when the text matches nothing',
      (tester) async {
    await _pump(tester, 'zzz');
    expect(find.text('Suggested'), findsNothing);
  });

  testWidgets('the offense list is grouped by behavior category with severity',
      (tester) async {
    await _pump(tester, 'zzz');
    expect(find.widgetWithText(FilterLabelBand, 'Academic Integrity'),
        findsOneWidget);
    expect(find.widgetWithText(FilterLabelBand, 'Uniform / Dress Code'),
        findsOneWidget);
    expect(
        find.text('Cheating during quizzes, exams, or graded activities (Major A)'),
        findsOneWidget);
    expect(find.text('No valid ID worn inside campus (Minor)'), findsOneWidget);
  });
}
