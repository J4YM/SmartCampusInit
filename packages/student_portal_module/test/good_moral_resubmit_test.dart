import 'package:dashboard_layout/dashboard_layout.dart' show GoodMoralFormData;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_portal_module/student_portal_module.dart';

const _prefill = GoodMoralFormData(
  lastName: 'Cruz',
  firstName: 'Ana',
  studentNumber: '2024-0001',
  section: 'BSIT 3-A',
  schoolStatus: 'Enrolled',
);

GoodMoralRequestStatus _request(
  String id, {
  String status = 'Pending',
  String? note,
  Map<String, dynamic>? formData,
}) =>
    GoodMoralRequestStatus(
      id: id,
      documentType: 'Certificate of Good Moral',
      purpose: 'Employment',
      status: status,
      requestDate: DateTime(2026, 10, 1),
      flagNote: note,
      formData: formData,
    );

Future<void> _pump(
  WidgetTester tester, {
  List<GoodMoralRequestStatus> requests = const [],
  GoodMoralFormData? prefill,
  void Function(Map<String, dynamic> formData)? onSubmit,
  void Function(String requestId, Map<String, dynamic> formData)? onResubmit,
}) async {
  tester.view.physicalSize = const Size(1440, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: StudentPortalHomePage(
      initialGoodMoralRequests: requests,
      goodMoralPrefill: prefill,
      onSubmitGoodMoralRequest: ({
        required documentType,
        required purpose,
        remarks,
        required formData,
      }) =>
          onSubmit?.call(formData),
      onResubmitGoodMoralRequest: ({
        required requestId,
        required purpose,
        remarks,
        required formData,
      }) =>
          onResubmit?.call(requestId, formData),
    ),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
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
  _legacyReturnedTests();

  testWidgets('Request Good Moral opens the slip filled in from the record',
      (tester) async {
    await _pump(tester, prefill: _prefill);
    await tester.ensureVisible(find.text('Request Good Moral'));
    await tester.tap(find.text('Request Good Moral'));
    await tester.pumpAndSettle();

    expect(find.text('Cruz'), findsOneWidget);
    expect(find.text('BSIT 3-A'), findsOneWidget);
  });

  testWidgets('a request sent back shows the note and can be edited and '
      'resubmitted', (tester) async {
    String? resubmittedId;
    Map<String, dynamic>? resubmitted;
    var newRequests = 0;
    await _pump(
      tester,
      requests: [
        _request('r1',
            status: 'Returned',
            note: 'Section does not match our records.',
            formData: {
              ..._prefill.toJson(),
              'address': 'Baliuag, Bulacan',
              'contact_number': '0917 123 4567',
              'ay_started': '2024-2025',
              'ay_last_attended': '2026-2027',
              'reason': 'Employment',
            }),
      ],
      prefill: _prefill,
      onSubmit: (_) => newRequests++,
      onResubmit: (id, data) {
        resubmittedId = id;
        resubmitted = data;
      },
    );

    expect(find.text('Returned'), findsOneWidget);
    expect(find.text('Section does not match our records.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('resubmit-r1')));
    await tester.tap(find.byKey(const Key('resubmit-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Cruz'), findsOneWidget, reason: 'opens with the old answers');

    await tester.enterText(find.byType(TextFormField).at(5), 'BSIT 3-B');
    await _certifyAndSubmit(tester);

    expect(newRequests, 0, reason: 'it is the same request, not a new one');
    expect(resubmittedId, 'r1');
    expect(resubmitted!['section'], 'BSIT 3-B');
  });

  testWidgets('a pending request has no resubmit button', (tester) async {
    await _pump(tester, requests: [_request('r1')]);
    expect(find.byKey(const Key('resubmit-r1')), findsNothing);
    expect(find.text('Returned'), findsNothing);
  });
}

void _legacyReturnedTests() {
  testWidgets('a request sent back before slips were stored field by field '
      'reopens filled in from the record, not empty', (tester) async {
    await _pump(
      tester,
      requests: [_request('r1', status: 'Returned', note: 'Please recheck.')],
      prefill: _prefill,
      onResubmit: (id, data) {},
    );
    await tester.ensureVisible(find.byKey(const Key('resubmit-r1')));
    await tester.tap(find.byKey(const Key('resubmit-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Cruz'), findsOneWidget);
    expect(find.text('Please recheck.'), findsWidgets);
  });
}
