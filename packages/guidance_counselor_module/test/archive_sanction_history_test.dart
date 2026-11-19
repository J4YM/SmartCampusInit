import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/student_archive/sanction_history_dialog.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_models.dart';
import 'package:guidance_counselor_module/pages/student_archive/student_archive_view.dart';

void main() {
  const maria = ArchiveStudentModel(
      id: 's1', name: 'Maria Santos', studentNumber: '2024-0001');

  Future<void> pumpView(WidgetTester tester, Widget view) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: view)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a student row opens their sanction history', (tester) async {
    ArchiveStudentModel? asked;
    await pumpView(
      tester,
      StudentArchiveView(
        onSearchStudents: (_) async => [maria],
        onLoadSanctions: (student) async {
          asked = student;
          return [
            SanctionHistoryItem(
              id: 'x',
              typeLabel: 'Suspension',
              description: '3-day suspension',
              basisLabel: 'Handbook',
              effectiveOn: DateTime(2026, 11, 18),
              endsOn: null,
              affectsEnrollment: false,
              overrideReason: 'Repeat offence',
            ),
          ];
        },
      ),
    );

    await tester.tap(find.byKey(const Key('archive-sanctions-s1')));
    await tester.pumpAndSettle();

    expect(asked?.id, 's1');
    expect(find.text('3-day suspension'), findsOneWidget);
    expect(find.textContaining('Repeat offence'), findsOneWidget);
  });

  testWidgets('without a loader there is no sanction history button',
      (tester) async {
    await pumpView(
      tester,
      StudentArchiveView(onSearchStudents: (_) async => [maria]),
    );
    expect(find.byKey(const Key('archive-sanctions-s1')), findsNothing);
  });

  testWidgets('an empty record says so', (tester) async {
    await pumpView(
      tester,
      const SanctionHistoryDialog(studentName: 'Maria Santos', items: []),
    );
    expect(find.text('No sanctions on record.'), findsOneWidget);
  });
}
