import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StudentReferralModel _referral(
  String id,
  String name, {
  String status = 'Pending',
  String urgency = 'Normal',
  String concern = 'emotional',
  DateTime? at,
}) =>
    StudentReferralModel(
      id: id,
      studentName: name,
      studentNumber: 'N-$id',
      referredByName: 'Filer $id',
      isSelf: true,
      concern: concern,
      details: 'Details for $name',
      urgency: urgency,
      status: status,
      createdAt: at ?? DateTime(2026, 10, 1, 9),
    );

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget view) async {
  _size(tester, const Size(1400, 900));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: view)),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  final referrals = [
    _referral('c1', 'Closed Cora', status: 'Closed'),
    _referral('n1', 'Normal Nina'),
    _referral('u1', 'Urgent Uma', urgency: 'Urgent'),
  ];

  testWidgets('open referrals come first, urgent before routine',
      (tester) async {
    await _pump(tester, ReferralsView(referrals: referrals));

    final uma = tester.getTopLeft(find.text('Urgent Uma')).dy;
    final nina = tester.getTopLeft(find.text('Normal Nina')).dy;
    final cora = tester.getTopLeft(find.text('Closed Cora')).dy;
    expect(uma, lessThan(nina));
    expect(nina, lessThan(cora));
    expect(find.text('3 referrals | 2 waiting | 1 urgent'), findsOneWidget);
  });

  testWidgets('a row opens the referral, and Save sends the status and note',
      (tester) async {
    StudentReferralModel? saved;
    String? savedStatus;
    String? savedNote;
    await _pump(
      tester,
      ReferralsView(
        referrals: referrals,
        onUpdate: (r, {required status, note}) async {
          saved = r;
          savedStatus = status;
          savedNote = note;
        },
      ),
    );

    await tester.tap(find.text('Normal Nina'));
    await tester.pumpAndSettle();
    expect(find.text('Details for Normal Nina'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'We will call you.');
    await tester.tap(find.byKey(const Key('referral-save')));
    await tester.pumpAndSettle();

    expect(saved?.id, 'n1');
    expect(savedStatus, 'Pending');
    expect(savedNote, 'We will call you.');
  });

  testWidgets('an open referral can be endorsed; a closed one cannot',
      (tester) async {
    StudentReferralModel? endorsed;
    await _pump(
      tester,
      ReferralsView(
        referrals: referrals,
        onEndorse: (r) async => endorsed = r,
      ),
    );

    expect(find.byKey(const Key('endorse-referral-n1')), findsOneWidget);
    expect(find.byKey(const Key('endorse-referral-u1')), findsOneWidget);
    expect(find.byKey(const Key('endorse-referral-c1')), findsNothing);

    await tester.tap(find.byKey(const Key('endorse-referral-u1')));
    await tester.pumpAndSettle();
    expect(endorsed?.id, 'u1');
  });

  testWidgets('a referral already endorsed shows no Endorse action',
      (tester) async {
    await _pump(
      tester,
      ReferralsView(
        referrals: [_referral('n1', 'Normal Nina', status: 'In_Progress')],
        endorsedReferralIds: const {'n1'},
        onEndorse: (r) async {},
      ),
    );

    expect(find.byKey(const Key('endorse-referral-n1')), findsNothing);
    expect(find.text('Endorsed'), findsOneWidget);
  });

  testWidgets('without callbacks the tab is read-only', (tester) async {
    await _pump(tester, ReferralsView(referrals: referrals));
    expect(find.byIcon(Icons.volunteer_activism_outlined), findsNothing,
        reason: 'no Endorse buttons');

    await tester.tap(find.text('Normal Nina'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('referral-save')), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pump(tester, const ReferralsView(referrals: []));
    expect(find.text('No referrals yet'), findsOneWidget);
  });

  testWidgets('the DO dashboard has a Referrals tab, and endorsing a referral '
      'opens the dialog filled in and sends its referral id', (tester) async {
    _size(tester, const Size(1400, 1000));
    EscalationDraft? sent;
    await tester.pumpWidget(MaterialApp(
      home: DisciplineOfficerDashboardPage(
        studentReferrals: [_referral('u1', 'Urgent Uma', urgency: 'Urgent')],
        onIssueEscalation: (d) async => sent = d,
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    await tester.tap(find.text('Referrals'));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.text('Urgent Uma'), findsOneWidget);

    await tester.tap(find.byKey(const Key('endorse-referral-u1')));
    await tester.pumpAndSettle();

    // The reason starts from what the student wrote.
    expect(find.textContaining('Details for Urgent Uma'), findsWidgets);
    await tester.tap(find.byKey(const Key('endorse-confirm')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.referralId, 'u1');
    expect(sent!.studentNumber, 'N-u1');
    expect(sent!.kind, EndorsementKind.counseling);
  });
}
