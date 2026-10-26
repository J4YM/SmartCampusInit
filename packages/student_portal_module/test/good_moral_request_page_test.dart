import 'package:dashboard_layout/dashboard_layout.dart' show GoodMoralFormData;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

const _prefill = GoodMoralFormData(
  lastName: 'Cruz',
  firstName: 'Ana',
  studentNumber: '2024-0001',
  section: 'BSIT 3-A',
  contactNumber: '0917 123 4567',
  ayStarted: '2024',
  schoolStatus: 'Enrolled',
);

typedef _Sent = ({
  String documentType,
  String purpose,
  String? remarks,
  Map<String, dynamic> formData,
});

Future<void> _pump(
  WidgetTester tester, {
  GoodMoralFormData? initial,
  String? returnNote,
  void Function(_Sent sent)? onSent,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: GoodMoralRequestPage(
      initial: initial,
      returnNote: returnNote,
      onSubmit: ({
        required documentType,
        required purpose,
        remarks,
        required formData,
      }) =>
          onSent?.call((
            documentType: documentType,
            purpose: purpose,
            remarks: remarks,
            formData: formData,
          )),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _certifyAndSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.ensureVisible(find.text('Submit Request'));
  await tester.tap(find.text('Submit Request'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the slip pre-fills from the record; only the identity fields are locked',
      (tester) async {
    _Sent? sent;
    await _pump(tester, initial: _prefill, onSent: (s) => sent = s);

    expect(find.text('Cruz'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('2024-0001'), findsOneWidget);
    expect(find.text('BSIT 3-A'), findsOneWidget);

    // Fill the address, pick a reason, certify and submit.
    await tester.enterText(find.byType(TextFormField).at(3), 'Baliuag, Bulacan');
    await tester.enterText(find.byType(TextFormField).at(8), '2026-2027');
    await tester.ensureVisible(find.text('Employment'));
    await tester.tap(find.text('Employment'));
    await tester.pump();
    await _certifyAndSubmit(tester);

    expect(sent, isNotNull);
    expect(sent!.formData['last_name'], 'Cruz');
    expect(sent!.formData['first_name'], 'Ana');
    expect(sent!.formData['student_number'], '2024-0001');
    expect(sent!.formData['school_status'], 'Enrolled');
    expect(sent!.formData['reason'], 'Employment');
    expect(sent!.purpose, 'Employment');
  });

  testWidgets('the remarks block and the form data describe the same slip',
      (tester) async {
    _Sent? sent;
    await _pump(tester, initial: _prefill, onSent: (s) => sent = s);
    await tester.enterText(find.byType(TextFormField).at(3), 'Baliuag, Bulacan');
    await tester.enterText(find.byType(TextFormField).at(8), '2026-2027');
    await tester.ensureVisible(find.text('Scholarship'));
    await tester.tap(find.text('Scholarship'));
    await tester.pump();
    await _certifyAndSubmit(tester);

    final rebuilt = GoodMoralFormData.fromJson(sent!.formData);
    expect(sent!.remarks, rebuilt.remarksText());
    expect(sent!.remarks, contains('Name: Cruz, Ana'));
  });

  testWidgets('without a record the slip starts empty and cannot be submitted',
      (tester) async {
    _Sent? sent;
    await _pump(tester, onSent: (s) => sent = s);

    expect(find.text('Cruz'), findsNothing);
    await _certifyAndSubmit(tester);
    expect(sent, isNull);
    expect(find.text('Required'), findsWidgets);
  });

  testWidgets('a returned slip shows the officer\'s note and opens prefilled',
      (tester) async {
    await _pump(
      tester,
      initial: _prefill,
      returnNote: 'Section does not match our records.',
    );
    expect(find.text('Section does not match our records.'), findsOneWidget);
    expect(find.text('BSIT 3-A'), findsOneWidget);
  });

  testWidgets('a fresh slip shows no return note', (tester) async {
    await _pump(tester, initial: _prefill);
    expect(find.textContaining('sent back'), findsNothing);
  });

  testWidgets('an "other" purpose is read back into its own field',
      (tester) async {
    await _pump(
      tester,
      initial: const GoodMoralFormData(
        lastName: 'Cruz',
        firstName: 'Ana',
        reason: 'Visa application',
        schoolStatus: 'Transferred',
      ),
    );
    expect(find.text('Visa application'), findsOneWidget);
  });
}
