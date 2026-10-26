import 'package:dashboard_layout/dashboard_layout.dart'
    show GoodMoralFormData, GoodMoralRecord;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _form = GoodMoralFormData(
  lastName: 'Cruz',
  firstName: 'Ana',
  middleName: 'Reyes',
  address: 'Baliuag, Bulacan',
  studentNumber: '2024-0001',
  section: 'BSIT 3-B',
  contactNumber: '0917 123 4567',
  ayStarted: '2024-2025',
  ayLastAttended: '2026-2027',
  schoolStatus: 'Enrolled',
  reason: 'Employment',
);

const _record = GoodMoralRecord(
  firstName: 'Ana',
  lastName: 'Cruz',
  studentNumber: '2024-0001',
  section: 'BSIT 3-A',
  contactNumber: '0917 123 4567',
  enrollmentYear: 2024,
);

GoodMoralRequestModel _request({
  GoodMoralFormData? form = _form,
  String status = 'Pending',
  String? flagNote,
  int historyCount = 0,
}) =>
    GoodMoralRequestModel(
      id: 'r1',
      studentName: 'Ana Cruz',
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      documentType: 'Certificate of Good Moral',
      purpose: 'Employment',
      requestedBy: 'Ana Cruz',
      requestDateTime: DateTime(2026, 10, 1, 9),
      remarks: 'Name: Cruz, Ana',
      status: status,
      flagNote: flagNote,
      formData: form,
      record: form == null ? null : _record,
      historyCount: historyCount,
    );

typedef _Flag = ({String note, bool sendBack});

Future<void> _pump(
  WidgetTester tester,
  GoodMoralRequestModel request, {
  void Function(_Flag flag)? onFlag,
  bool canFlag = true,
  VoidCallback? onGenerate,
  Future<void> Function(GoodMoralSelectedStudent request)? onUseRecord,
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GoodMoralPreviewPanel(
        selected: GoodMoralSelectedStudent.fromRequest(request),
        onGenerateCertificate: onGenerate ?? () {},
        onFlagRequest: canFlag
            ? (selected, note, sendBack) async =>
                onFlag?.call((note: note, sendBack: sendBack))
            : null,
        onUseRegistrarRecord: onUseRecord,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  _registrarRecordTests();
  testWidgets('the submitted slip is compared with the record and a mismatch '
      'is called out', (tester) async {
    await _pump(tester, _request());

    expect(find.text('Submitted slip'), findsOneWidget);
    // Section differs (3-B vs 3-A); everything else on record matches.
    expect(find.text('Differs from record'), findsOneWidget);
    expect(find.byKey(const Key('gm-check-Course/Section')), findsOneWidget);
    expect(find.text('BSIT 3-B'), findsOneWidget);
    expect(find.textContaining('BSIT 3-A'), findsWidgets);
  });

  testWidgets('fields the school has no record of are shown as not on record',
      (tester) async {
    await _pump(tester, _request());
    expect(find.text('Not on record'), findsWidgets);
    expect(find.text('Baliuag, Bulacan'), findsOneWidget);
  });

  testWidgets('an older request without a stored slip shows no comparison',
      (tester) async {
    await _pump(tester, _request(form: null));
    expect(find.text('Submitted slip'), findsNothing);
    expect(find.text('Differs from record'), findsNothing);
  });

  testWidgets('Flag keeps the request in place and sends the note',
      (tester) async {
    _Flag? flag;
    await _pump(tester, _request(), onFlag: (f) => flag = f);

    await tester.ensureVisible(find.byKey(const Key('gm-flag')));
    await tester.tap(find.byKey(const Key('gm-flag')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('gm-flag-note')), 'Section does not match.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('gm-flag-confirm')));
    await tester.pumpAndSettle();

    expect(flag, (note: 'Section does not match.', sendBack: false));
  });

  testWidgets('Send back asks the student to fix it', (tester) async {
    _Flag? flag;
    await _pump(tester, _request(), onFlag: (f) => flag = f);

    await tester.ensureVisible(find.byKey(const Key('gm-send-back')));
    await tester.tap(find.byKey(const Key('gm-send-back')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('gm-flag-note')), 'Please correct the section.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('gm-flag-confirm')));
    await tester.pumpAndSettle();

    expect(flag, (note: 'Please correct the section.', sendBack: true));
  });

  testWidgets('a note is required before flagging', (tester) async {
    _Flag? flag;
    await _pump(tester, _request(), onFlag: (f) => flag = f);

    await tester.ensureVisible(find.byKey(const Key('gm-flag')));
    await tester.tap(find.byKey(const Key('gm-flag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gm-flag-confirm')));
    await tester.pumpAndSettle();

    expect(flag, isNull);
    expect(find.byKey(const Key('gm-flag-note')), findsOneWidget,
        reason: 'the dialog stays open');
  });

  testWidgets('a flagged or returned request shows the note and history',
      (tester) async {
    await _pump(
      tester,
      _request(status: 'Returned', flagNote: 'Fix the section.', historyCount: 2),
    );
    expect(find.text('Sent back to the student'), findsOneWidget);
    expect(find.text('Fix the section.'), findsOneWidget);
    expect(find.text('Resubmitted 2 times'), findsOneWidget);
  });

  testWidgets('a flagged request can still be exported, a returned one waits '
      'for the student', (tester) async {
    var generated = 0;
    await _pump(tester, _request(status: 'Pending', flagNote: 'Check it.'),
        onGenerate: () => generated++);
    await tester.ensureVisible(find.byKey(const Key('gm-generate')));
    await tester.tap(find.byKey(const Key('gm-generate')));
    expect(generated, 1);

    await _pump(tester, _request(status: 'Returned', flagNote: 'Fix it.'),
        onGenerate: () => generated++);
    await tester.ensureVisible(find.byKey(const Key('gm-generate')));
    await tester.tap(find.byKey(const Key('gm-generate')), warnIfMissed: false);
    expect(generated, 1, reason: 'a returned request is not printed');
  });

  testWidgets('a fulfilled request cannot be flagged; no callback hides the '
      'actions', (tester) async {
    await _pump(tester, _request(status: 'Fulfilled'));
    expect(find.byKey(const Key('gm-flag')), findsNothing);

    await _pump(tester, _request(), canFlag: false);
    expect(find.byKey(const Key('gm-flag')), findsNothing);
    expect(find.byKey(const Key('gm-send-back')), findsNothing);
  });
}

void _registrarRecordTests() {
  testWidgets('a name, number or section that differs offers "Use registrar '
      'record", and tapping it asks to correct that request', (tester) async {
    final corrected = <String>[];
    await _pump(tester, _request(), onUseRecord: (r) async {
      corrected.add(r.sourceId);
    });

    expect(find.byKey(const Key('gm-use-record')), findsOneWidget);
    expect(find.text('Use registrar record'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('gm-use-record')));
    await tester.tap(find.byKey(const Key('gm-use-record')));
    await tester.pumpAndSettle();

    expect(corrected, ['r1']);
  });

  testWidgets('a slip that matches the record has no such button',
      (tester) async {
    await _pump(
      tester,
      _request(form: _formWith(section: 'BSIT 3-A')),
      onUseRecord: (_) async {},
    );
    expect(find.byKey(const Key('gm-use-record')), findsNothing);
  });

  testWidgets('a contact number that differs is the student\'s to edit, so no '
      'button', (tester) async {
    await _pump(
      tester,
      _request(
          form: _formWith(section: 'BSIT 3-A', contactNumber: '0999')),
      onUseRecord: (_) async {},
    );
    expect(find.text('Differs from record'), findsOneWidget);
    expect(find.byKey(const Key('gm-use-record')), findsNothing);
  });

  testWidgets('without the callback the button is hidden', (tester) async {
    await _pump(tester, _request());
    expect(find.byKey(const Key('gm-use-record')), findsNothing);
  });
}

GoodMoralFormData _formWith({String? section, String? contactNumber}) =>
    GoodMoralFormData(
      lastName: _form.lastName,
      firstName: _form.firstName,
      middleName: _form.middleName,
      address: _form.address,
      studentNumber: _form.studentNumber,
      section: section ?? _form.section,
      contactNumber: contactNumber ?? _form.contactNumber,
      ayStarted: _form.ayStarted,
      ayLastAttended: _form.ayLastAttended,
      schoolStatus: _form.schoolStatus,
      reason: _form.reason,
    );
