import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/referrals/referrals_models.dart';
import 'package:guidance_counselor_module/pages/referrals/referrals_view.dart';

GuidanceReferralModel _referral(
  String id,
  String name, {
  String source = 'self',
  String status = 'Pending',
  String urgency = 'Normal',
  List<ReferralMeetingModel> meetings = const [],
  String? note,
}) =>
    GuidanceReferralModel(
      id: id,
      studentId: 's-$id',
      studentName: name,
      studentNumber: 'N-$id',
      source: source,
      concern: 'emotional',
      details: 'Details for $name',
      urgency: urgency,
      status: status,
      createdAt: DateTime(2026, 10, 1, 9),
      note: note,
      meetings: meetings,
    );

Future<void> _pump(WidgetTester tester, Widget view) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: view)),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  testWidgets('self referrals and accepted endorsements are listed together, '
      'each labelled', (tester) async {
    await _pump(
      tester,
      GuidanceReferralsView(referrals: [
        _referral('a', 'Self Sam'),
        _referral('b', 'Endorsed Ena', source: 'endorsement'),
      ]),
    );

    expect(find.text('Self Sam'), findsOneWidget);
    expect(find.text('Endorsed Ena'), findsOneWidget);
    expect(find.text('Self referral'), findsOneWidget);
    expect(find.text('From Student Affairs'), findsOneWidget);
    expect(find.text('2 referrals | 2 waiting'), findsOneWidget);
  });

  testWidgets('Schedule meeting asks for when, where and who, then reports '
      'them for that referral', (tester) async {
    GuidanceReferralModel? scheduledFor;
    MeetingFormResult? result;
    await _pump(
      tester,
      GuidanceReferralsView(
        referrals: [_referral('a', 'Self Sam')],
        onScheduleMeeting: (referral, form) async {
          scheduledFor = referral;
          result = form;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('schedule-meeting-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meeting-invitee')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('meeting-location')), 'Guidance Office');
    await tester.tap(find.byKey(const Key('meeting-save')));
    await tester.pumpAndSettle();

    expect(scheduledFor?.id, 'a');
    expect(result?.invitee, 'both');
    expect(result?.location, 'Guidance Office');
    expect(result!.scheduledAt.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('an upcoming meeting shows with its reply status',
      (tester) async {
    await _pump(
      tester,
      GuidanceReferralsView(referrals: [
        _referral('a', 'Self Sam', meetings: [
          ReferralMeetingModel(
            id: 'm1',
            scheduledAt: DateTime.now().add(const Duration(days: 3)),
            invitee: 'student',
            status: 'Confirmed',
          ),
        ]),
      ]),
    );

    expect(find.textContaining('Student'), findsWidgets);
    expect(find.textContaining('Confirmed'), findsOneWidget);
  });

  testWidgets('a row opens the referral; Save sends the status and note',
      (tester) async {
    GuidanceReferralModel? saved;
    String? savedStatus;
    String? savedNote;
    await _pump(
      tester,
      GuidanceReferralsView(
        referrals: [_referral('a', 'Self Sam')],
        onUpdate: (r, {required status, note}) async {
          saved = r;
          savedStatus = status;
          savedNote = note;
        },
      ),
    );

    await tester.tap(find.text('Self Sam'));
    await tester.pumpAndSettle();
    expect(find.text('Details for Self Sam'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Let us talk Friday.');
    await tester.tap(find.byKey(const Key('referral-save')));
    await tester.pumpAndSettle();

    expect(saved?.id, 'a');
    expect(savedStatus, 'Pending');
    expect(savedNote, 'Let us talk Friday.');
  });

  testWidgets('a meeting can be marked completed from the referral popup',
      (tester) async {
    String? outcomeMeeting;
    String? outcome;
    await _pump(
      tester,
      GuidanceReferralsView(
        referrals: [
          _referral('a', 'Self Sam', meetings: [
            ReferralMeetingModel(
              id: 'm1',
              scheduledAt: DateTime.now().add(const Duration(days: 1)),
              invitee: 'parent',
              status: 'Confirmed',
            ),
          ]),
        ],
        onUpdate: (r, {required status, note}) async {},
        onSetMeetingOutcome: (meeting, status) async {
          outcomeMeeting = meeting.id;
          outcome = status;
        },
      ),
    );

    await tester.tap(find.text('Self Sam'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-outcome-m1-Completed')));
    await tester.pumpAndSettle();

    expect(outcomeMeeting, 'm1');
    expect(outcome, 'Completed');
  });

  testWidgets('a closed referral cannot be scheduled; no callbacks is '
      'read-only', (tester) async {
    await _pump(
      tester,
      GuidanceReferralsView(
        referrals: [_referral('a', 'Closed Cleo', status: 'Closed')],
        onScheduleMeeting: (r, f) async {},
      ),
    );
    expect(find.byKey(const Key('schedule-meeting-a')), findsNothing);

    await _pump(
      tester,
      GuidanceReferralsView(referrals: [_referral('b', 'Open Ola')]),
    );
    expect(find.byKey(const Key('schedule-meeting-b')), findsNothing);
    await tester.tap(find.text('Open Ola'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('referral-save')), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pump(tester, const GuidanceReferralsView(referrals: []));
    expect(find.text('No referrals yet'), findsOneWidget);
  });
}
