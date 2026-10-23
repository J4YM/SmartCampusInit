import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:parent_portal_module/widgets/parent_overview_widgets.dart';

GoodMoralRequestStatus _request(String id,
        {String status = 'Pending', String? note}) =>
    GoodMoralRequestStatus(
      id: id,
      documentType: 'Certificate of Good Moral',
      purpose: 'Employment',
      status: status,
      requestDate: DateTime(2026, 10, 1),
      flagNote: note,
      formData: const {'last_name': 'Cruz', 'first_name': 'Ana'},
    );

Future<void> _pump(
  WidgetTester tester,
  List<GoodMoralRequestStatus> requests, {
  void Function(GoodMoralRequestStatus r)? onResubmit,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DocumentRequestsCard(
          requests: requests,
          onRequest: () {},
          onResubmit: onResubmit,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a request sent back shows the note and an Edit & resubmit button',
      (tester) async {
    GoodMoralRequestStatus? edited;
    await _pump(
      tester,
      [_request('r1', status: 'Returned', note: 'Name does not match.')],
      onResubmit: (r) => edited = r,
    );

    expect(find.text('Name does not match.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resubmit-r1')));
    expect(edited?.id, 'r1');
  });

  testWidgets('a pending request has no resubmit button', (tester) async {
    await _pump(tester, [_request('r1')], onResubmit: (_) {});
    expect(find.byKey(const Key('resubmit-r1')), findsNothing);
  });

  test('a returned request knows it was sent back', () {
    expect(_request('r1', status: 'Returned').isReturned, isTrue);
    expect(_request('r1').isReturned, isFalse);
  });
}
