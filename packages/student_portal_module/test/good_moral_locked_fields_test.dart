import 'package:dashboard_layout/dashboard_layout.dart' show GoodMoralFormData;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

const _full = GoodMoralFormData(
  lastName: 'Cruz',
  firstName: 'Ana',
  studentNumber: '2024-0001',
  section: 'BSIT 3-A',
  contactNumber: '0917 123 4567',
  schoolStatus: 'Enrolled',
);

Future<void> _pump(
  WidgetTester tester, {
  GoodMoralFormData? initial,
  bool prefillFailed = false,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: GoodMoralRequestPage(
      initial: initial,
      prefillFailed: prefillFailed,
      onSubmit: ({
        required documentType,
        required purpose,
        remarks,
        required formData,
      }) {},
    ),
  ));
  await tester.pumpAndSettle();
}

/// The slip's text fields in on-page order: last, first, middle, address,
/// student number, section, contact number, A.Y. started, A.Y. last attended.
Finder _field(int i) => find.byType(TextFormField).at(i);

bool _readOnly(WidgetTester tester, int i) =>
    tester.widget<TextField>(find.descendant(
            of: _field(i), matching: find.byType(TextField)))
        .readOnly;

void main() {
  testWidgets('name, student number and section are locked; address and '
      'contact number stay editable', (tester) async {
    await _pump(tester, initial: _full);

    expect(_readOnly(tester, 0), isTrue, reason: 'last name');
    expect(_readOnly(tester, 1), isTrue, reason: 'first name');
    expect(_readOnly(tester, 4), isTrue, reason: 'student number');
    expect(_readOnly(tester, 5), isTrue, reason: 'section');
    expect(_readOnly(tester, 2), isFalse, reason: 'middle name');
    expect(_readOnly(tester, 3), isFalse, reason: 'address');
    expect(_readOnly(tester, 6), isFalse, reason: 'contact number');

    await tester.enterText(_field(0), 'Santos');
    expect(find.text('Cruz'), findsOneWidget);
    expect(find.text('Santos'), findsNothing);
  });

  testWidgets('a field with no value on record stays editable', (tester) async {
    await _pump(
      tester,
      initial: const GoodMoralFormData(
        lastName: 'Cruz',
        firstName: 'Ana',
        studentNumber: '2024-0001',
        section: '',
      ),
    );

    expect(_readOnly(tester, 0), isTrue);
    expect(_readOnly(tester, 5), isFalse, reason: 'blank section is editable');
    await tester.enterText(_field(5), 'BSIT 3-B');
    expect(find.text('BSIT 3-B'), findsOneWidget);
  });

  testWidgets('with no record at all every field is editable and a notice '
      'says why', (tester) async {
    await _pump(tester, prefillFailed: true);

    expect(_readOnly(tester, 0), isFalse);
    expect(find.text('Could not load your details. Please fill them in.'),
        findsOneWidget);
  });
}
