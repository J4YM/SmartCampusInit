import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

void main() {
  const student = RegistrarStudentModel(
    id: 'stu-1',
    name: 'Juan D. Dela Cruz',
    studentId: '2024-00123',
    program: 'BS Information Technology',
    section: 'BSIT - 3B',
    status: EnrollmentStatus.active,
    firstName: 'Juan',
    middleInitial: 'D',
    lastName: 'Dela Cruz',
    email: 'juan@example.com',
    contactNo: '09170000000',
    parentGuardian: 'Maria Dela Cruz',
    guardianContactNo: '09171234567',
  );

  Future<List<(String, EditStudentForm)>> open(
    WidgetTester tester, {
    Future<void> Function(String, EditStudentForm)? onSave,
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saved = <(String, EditStudentForm)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EditStudentDialog(
          student: student,
          onSave: onSave ??
              (id, form) async {
                saved.add((id, form));
              },
        ),
      ),
    ));
    return saved;
  }

  Finder field(String key) => find.byKey(Key(key));

  testWidgets('is prefilled from the student, guardian name and number included',
      (tester) async {
    await open(tester);
    expect(find.text('2024-00123'), findsOneWidget);
    expect(find.text('Juan'), findsOneWidget);
    expect(find.text('Dela Cruz'), findsOneWidget);
    expect(find.text('juan@example.com'), findsOneWidget);
    expect(find.text('Maria Dela Cruz'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
  });

  testWidgets('saving hands back the edited values for that student id',
      (tester) async {
    final saved = await open(tester);

    await tester.enterText(field('edit-guardian-name'), 'Ana Reyes');
    await tester.enterText(field('edit-guardian-contact'), '09181112222');
    await tester.enterText(field('edit-last-name'), 'Santos');
    await tester.pump();
    await tester.tap(field('edit-student-save'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    final (id, form) = saved.single;
    expect(id, 'stu-1');
    expect(form.guardianName, 'Ana Reyes');
    expect(form.guardianContactNo, '09181112222');
    expect(form.lastName, 'Santos');
    expect(form.firstName, 'Juan');
    expect(form.studentNumber, '2024-00123');
  });

  testWidgets('a non-PH guardian number blocks saving and explains why',
      (tester) async {
    await open(tester);
    await tester.enterText(field('edit-guardian-contact'), '12345');
    await tester.pump();

    expect(find.textContaining('PH mobile number'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(field('edit-student-save')).onPressed,
      isNull,
    );
  });

  testWidgets('guardian number may be cleared (it is optional)', (tester) async {
    final saved = await open(tester);
    await tester.enterText(field('edit-guardian-contact'), '');
    await tester.pump();
    await tester.tap(field('edit-student-save'));
    await tester.pumpAndSettle();
    expect(saved.single.$2.guardianContactNo, '');
  });

  testWidgets('first name, last name and student number are required',
      (tester) async {
    await open(tester);
    for (final key in ['edit-first-name', 'edit-last-name', 'edit-student-number']) {
      final original = tester
          .widget<TextField>(field(key))
          .controller!
          .text;
      await tester.enterText(field(key), '  ');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(field('edit-student-save')).onPressed,
        isNull,
        reason: '$key blank should disable Save',
      );
      await tester.enterText(field(key), original);
      await tester.pump();
    }
  });

  testWidgets('a failed save keeps the dialog open and shows the error',
      (tester) async {
    await open(
      tester,
      onSave: (_, __) async => throw 'That student number is already used',
    );
    await tester.tap(field('edit-student-save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditStudentDialog), findsOneWidget);
    expect(find.text('That student number is already used'), findsOneWidget);
  });

  group('isValidGuardianMobile', () {
    test('accepts the PH mobile shapes', () {
      for (final n in ['09171234567', '9171234567', '639171234567', '+63 917 123 4567']) {
        expect(isValidGuardianMobile(n), isTrue, reason: n);
      }
    });
    test('rejects everything else', () {
      for (final n in ['', 'N/A', '0917123456', '(044) 123-4567', '+1 415 555 2671']) {
        expect(isValidGuardianMobile(n), isFalse, reason: n);
      }
    });
  });
}
