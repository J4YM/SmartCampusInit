import 'package:dashboard_layout/dashboard_layout.dart';
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

  VoidCallback? saveOnPressed(WidgetTester tester) =>
      tester.widget<AppPopupPrimaryButton>(field('edit-student-save')).onPressed;

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
      saveOnPressed(tester),
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
        saveOnPressed(tester),
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
  group('matches IT Technician\'s Edit Student popup', () {
    const fieldKeys = [
      'edit-student-number',
      'edit-email',
      'edit-contact',
      'edit-first-name',
      'edit-last-name',
      'edit-middle-initial',
      'edit-guardian-name',
      'edit-guardian-contact',
    ];

    testWidgets('a wide popup titled "Edit Student" with a close button',
        (tester) async {
      await open(tester);
      final title = tester.widget<Text>(find.text('Edit Student'));
      expect(title.style!.fontSize, 18);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(find.byTooltip('Close'), findsOneWidget);
      // The same 720px-wide shell as IT's.
      expect(tester.getSize(find.byType(BentoCard).first).width, 720);
    });

    testWidgets('fields are grouped under icon + title + rule sections',
        (tester) async {
      await open(tester);
      final sections = find.byType(AppPopupSection);
      expect(sections, findsNWidgets(3));
      for (final (title, icon) in [
        ('Student Information', Icons.badge_outlined),
        ('Personal Details', Icons.person_outline_rounded),
        ('Parent / Guardian', Icons.family_restroom_outlined),
      ]) {
        expect(find.text(title), findsOneWidget);
        expect(find.byIcon(icon), findsOneWidget);
      }
      // Sections run top to bottom in that order.
      double top(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(top('Student Information'), lessThan(top('Personal Details')));
      expect(top('Personal Details'), lessThan(top('Parent / Guardian')));
    });

    testWidgets('related fields share a row on a wide popup', (tester) async {
      await open(tester);
      double top(String key) => tester.getTopLeft(field(key)).dy;
      double left(String key) => tester.getTopLeft(field(key)).dx;
      // Side by side: the next cell starts to the right and (give or take a
      // wrapped one-line label in the test font) at the same height; a stacked
      // layout would put it a whole field-height lower.
      void sameRow(String first, String next) {
        expect(left(next), greaterThan(left(first)), reason: '$next right of $first');
        expect((top(next) - top(first)).abs(), lessThan(24),
            reason: '$next is on $first\'s row');
      }

      sameRow('edit-student-number', 'edit-email');
      sameRow('edit-email', 'edit-contact');
      sameRow('edit-first-name', 'edit-last-name');
      sameRow('edit-last-name', 'edit-middle-initial');
      sameRow('edit-guardian-name', 'edit-guardian-contact');
      // The three rows run top to bottom.
      expect(top('edit-first-name'), greaterThan(top('edit-student-number') + 40));
      expect(top('edit-guardian-name'), greaterThan(top('edit-first-name') + 40));
      // M.I. is the narrow cell.
      expect(tester.getSize(field('edit-middle-initial')).width,
          lessThan(tester.getSize(field('edit-first-name')).width / 2));
    });

    testWidgets('every field has its label above it, no floating label or hint',
        (tester) async {
      await open(tester);
      for (final key in fieldKeys) {
        final d = tester.widget<TextField>(field(key)).decoration!;
        expect(d.labelText, isNull, reason: '$key has a floating label');
        expect(d.filled, isTrue);
        expect(d.isDense, isTrue);
      }
      for (final (label, key) in [
        ('Student Number', 'edit-student-number'),
        ('First Name', 'edit-first-name'),
        ('Guardian Contact No.', 'edit-guardian-contact'),
      ]) {
        expect(tester.getRect(find.text(label)).bottom,
            lessThanOrEqualTo(tester.getRect(field(key)).top));
      }
    });

    testWidgets('footer: Cancel (secondary) left of Save Changes (primary)',
        (tester) async {
      await open(tester);
      expect(tester.widget(field('edit-student-cancel')),
          isA<AppPopupSecondaryButton>());
      expect(tester.widget(field('edit-student-save')),
          isA<AppPopupPrimaryButton>());
      final cancel = tester.getRect(field('edit-student-cancel'));
      final save = tester.getRect(field('edit-student-save'));
      expect(cancel.right, lessThan(save.left));
      expect(cancel.center.dy, closeTo(save.center.dy, 1));
      expect(save.height, kDashboardControlHeight);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('a disabled Save is the same blue at half strength',
        (tester) async {
      await open(tester);
      await tester.enterText(field('edit-first-name'), '');
      await tester.pump();
      expect(saveOnPressed(tester), isNull);
      final button = tester.widget<FilledButton>(find.descendant(
          of: field('edit-student-save'), matching: find.byType(FilledButton)));
      expect(button.style!.backgroundColor!.resolve({WidgetState.disabled}),
          const Color(0xFF345892).withOpacity(0.5));
    });

    testWidgets('a validation error shows under its field in the system red',
        (tester) async {
      await open(tester);
      await tester.enterText(field('edit-guardian-contact'), '12345');
      await tester.pump();
      final d =
          tester.widget<TextField>(field('edit-guardian-contact')).decoration!;
      expect(d.errorText, contains('PH mobile number'));
      expect(d.errorStyle!.color, const Color(0xFFCD4855));
    });

    testWidgets('on a phone the rows stack, sizes step down, nothing overflows',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditStudentDialog(student: student, onSave: (_, __) async {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text('Edit Student')).style!.fontSize, 16);
      expect(tester.widget<TextField>(field('edit-last-name')).style!.fontSize, 11);
      // Stacked: last name sits BELOW first name, not beside it.
      expect(tester.getTopLeft(field('edit-last-name')).dy,
          greaterThan(tester.getTopLeft(field('edit-first-name')).dy));
    });

    testWidgets('follows the dark theme', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: EditStudentDialog(student: student, onSave: (_, __) async {}),
        ),
      ));
      await tester.pumpAndSettle();
      final d = tester.widget<TextField>(field('edit-last-name')).decoration!;
      expect(d.fillColor, const Color(0xFF0E0E0E));
      expect(tester.widget<BentoCard>(find.byType(BentoCard).first).backgroundColor,
          const Color(0xFF191A1F));
    });
  });
}
