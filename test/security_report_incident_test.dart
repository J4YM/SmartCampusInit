import 'package:capstone_dashboard/kiosk/security_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_kiosk_module/student_kiosk.dart';

const _jane = SecurityReportStudentOption(
  id: 's1',
  displayName: 'Jane Doe',
  studentNumber: '2024-0001',
  gradeSection: 'BSIT 1A',
);

Future<List<SecurityReportSubmission>> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final submitted = <SecurityReportSubmission>[];
  await tester.pumpWidget(MaterialApp(
    home: SecurityReportScreen(
      officerName: 'Officer',
      onSearchStudents: (q) async => const [_jane],
      onSubmit: submitted.add,
    ),
  ));
  return submitted;
}

Future<void> _pickStudent(WidgetTester tester) async {
  await tester.tap(find.byType(TextField).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('2'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Jane Doe'));
  await tester.pumpAndSettle();
}

void _typeNotes(WidgetTester tester, String text) {
  final notes = tester.widget<TextField>(find.byType(TextField).last);
  notes.controller!.text = text;
}

Finder get _submitButton => find.ancestor(
      of: find.text('Review & Submit'),
      matching: find.bySubtype<FilledButton>(),
    );

void main() {
  testWidgets('there is no violation picker and no escalate toggle',
      (tester) async {
    await _open(tester);
    expect(find.text('Select the violation(s)'), findsNothing);
    expect(find.text('Escalate immediately'), findsNothing);
    expect(find.text('When did it happen?'), findsOneWidget);
  });

  testWidgets('submit needs a student and a description', (tester) async {
    await _open(tester);
    bool enabled() =>
        tester.widget<FilledButton>(_submitButton).onPressed != null;
    expect(enabled(), isFalse);

    await _pickStudent(tester);
    expect(enabled(), isFalse);

    _typeNotes(tester, '   ');
    await tester.pump();
    expect(enabled(), isFalse);

    _typeNotes(tester, 'Fight near the canteen');
    await tester.pump();
    expect(enabled(), isTrue);
  });

  testWidgets('the incident time defaults to now and can be set earlier',
      (tester) async {
    final submitted = await _open(tester);
    await _pickStudent(tester);
    _typeNotes(tester, 'Fight near the canteen');
    await tester.pump();

    await tester.ensureVisible(find.text('1 hour ago'));
    await tester.tap(find.text('1 hour ago'));
    await tester.pump();
    final before = DateTime.now();
    await tester.ensureVisible(_submitButton);
    await tester.tap(_submitButton);
    await tester.pump();

    expect(submitted, hasLength(1));
    final s = submitted.single;
    expect(s.studentId, 's1');
    expect(s.notes, 'Fight near the canteen');
    final ago = before.difference(s.incidentAt);
    expect(ago, greaterThan(const Duration(minutes: 59)));
    expect(ago, lessThan(const Duration(minutes: 61)));
  });

  testWidgets('just now is the default choice', (tester) async {
    final submitted = await _open(tester);
    await _pickStudent(tester);
    _typeNotes(tester, 'Smoking');
    await tester.pump();
    await tester.ensureVisible(_submitButton);
    await tester.tap(_submitButton);
    await tester.pump();

    expect(DateTime.now().difference(submitted.single.incidentAt),
        lessThan(const Duration(minutes: 1)));
  });

  testWidgets('tapping the student search still shows the on-screen keyboard',
      (tester) async {
    await _open(tester);
    expect(find.byType(KioskOnScreenKeyboard), findsNothing);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byType(KioskOnScreenKeyboard), findsOneWidget);
  });
}
