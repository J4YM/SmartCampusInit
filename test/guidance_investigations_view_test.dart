import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/investigations/investigations_view.dart';

InvestigationMeetingModel _meeting({
  String id = 'm1',
  String status = 'Proposed',
  String invitee = 'both',
  String? note,
  Duration fromNow = const Duration(days: 2),
}) =>
    InvestigationMeetingModel(
      id: id,
      scheduledAt: DateTime.now().add(fromNow),
      location: 'Guidance Office',
      invitee: invitee,
      status: status,
      responseNote: note,
    );

InvestigationModel _inv({
  String id = 'i1',
  String status = 'Open',
  List<InvestigationMeetingModel> meetings = const [],
  List<String> evidence = const [],
  String? findings,
}) =>
    InvestigationModel(
      id: id,
      studentName: 'Jane Doe',
      studentNumber: '2024-0001',
      section: 'BSIT 3-A',
      offenseLabel: 'Fighting',
      offenseCategory: 'Major_B',
      incidentNotes: 'Fight in the hallway',
      incidentAt: DateTime(2026, 10, 19, 14, 30),
      createdAt: DateTime(2026, 10, 20, 9),
      status: status,
      meetings: meetings,
      evidencePaths: evidence,
      findings: findings,
    );

Future<void> _pump(
  WidgetTester tester,
  List<InvestigationModel> items, {
  Future<void> Function(InvestigationModel, DateTime, String?, String)?
      onSchedule,
  Future<void> Function(InvestigationMeetingModel, String)? onOutcome,
  Future<void> Function(InvestigationModel, String, String?)? onComplete,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: InvestigationsView(
          investigations: items,
          onSchedule: onSchedule,
          onSetMeetingOutcome: onOutcome,
          onComplete: onComplete,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state', (tester) async {
    await _pump(tester, const []);
    expect(find.text('No investigations yet'), findsOneWidget);
  });

  testWidgets('shows the case, offense, notes and evidence count',
      (tester) async {
    await _pump(tester, [_inv(evidence: const ['a.jpg'])]);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Fighting'), findsOneWidget);
    expect(find.text('Fight in the hallway'), findsOneWidget);
    expect(find.text('Photo evidence (1)'), findsOneWidget);
  });

  testWidgets('a declined meeting shows the invitee\'s answer and offers a new one',
      (tester) async {
    await _pump(
      tester,
      [
        _inv(meetings: [_meeting(status: 'Declined', note: 'Out of town')])
      ],
      onSchedule: (i, at, where, who) async {},
    );
    expect(find.text('Declined'), findsOneWidget);
    expect(find.textContaining('Out of town'), findsOneWidget);
    expect(find.text('Reschedule meeting'), findsOneWidget);
  });

  testWidgets('a confirmed meeting shows Confirmed', (tester) async {
    await _pump(tester, [
      _inv(meetings: [_meeting(status: 'Confirmed')])
    ]);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Schedule meeting'), findsNothing);
  });

  testWidgets('with no meeting yet the counselor can schedule one',
      (tester) async {
    await _pump(
      tester,
      [_inv()],
      onSchedule: (i, at, where, who) async {},
      onComplete: (i, f, r) async {},
    );
    expect(find.text('Schedule meeting'), findsOneWidget);
    expect(find.text('Complete investigation'), findsOneWidget);
  });

  testWidgets('a completed investigation is read-only and shows findings',
      (tester) async {
    await _pump(tester, [
      _inv(status: 'Complete', findings: 'Mutual altercation; both warned')
    ]);
    expect(find.text('Mutual altercation; both warned'), findsOneWidget);
    expect(find.text('Schedule meeting'), findsNothing);
    expect(find.text('Complete investigation'), findsNothing);
  });

  testWidgets('scheduling returns the chosen time, place and invitee',
      (tester) async {
    DateTime? when;
    String? where;
    String? who;
    await _pump(
      tester,
      [_inv()],
      onSchedule: (inv, at, location, invitee) async {
        when = at;
        where = location;
        who = invitee;
      },
    );
    await tester.tap(find.text('Schedule meeting'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('meeting-location')), 'Guidance Office');
    await tester.tap(find.byKey(const Key('meeting-invitee-parent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('meeting-save')));
    await tester.pumpAndSettle();

    expect(when, isNotNull);
    expect(when!.isAfter(DateTime.now()), isTrue);
    expect(where, 'Guidance Office');
    expect(who, 'parent');
  });

  test('a meeting time in the past is invalid', () {
    final now = DateTime(2026, 10, 20, 9);
    expect(validateMeetingTime(DateTime(2026, 10, 20, 8), now: now),
        'Choose a time in the future.');
    expect(validateMeetingTime(now, now: now), 'Choose a time in the future.');
    expect(validateMeetingTime(DateTime(2026, 10, 21, 9), now: now), isNull);
  });

  testWidgets('findings are required to complete', (tester) async {
    String? findings;
    String? recommendation;
    await _pump(
      tester,
      [_inv()],
      onComplete: (inv, f, r) async {
        findings = f;
        recommendation = r;
      },
    );
    await tester.tap(find.text('Complete investigation'));
    await tester.pumpAndSettle();

    bool enabled() => tester
            .widget<AppPopupPrimaryButton>(find.byKey(const Key('complete-save')))
            .onPressed !=
        null;
    expect(enabled(), isFalse);
    await tester.enterText(find.byKey(const Key('findings-field')), '   ');
    await tester.pump();
    expect(enabled(), isFalse);

    await tester.enterText(
        find.byKey(const Key('findings-field')), '  Both parties spoke  ');
    await tester.pump();
    expect(enabled(), isTrue);
    await tester.tap(find.byKey(const Key('complete-save')));
    await tester.pumpAndSettle();

    expect(findings, 'Both parties spoke');
    expect(recommendation, isNull);
  });

  testWidgets('a meeting can be marked missed', (tester) async {
    String? outcome;
    await _pump(
      tester,
      [
        _inv(meetings: [_meeting(status: 'Confirmed', fromNow: const Duration(hours: 1))])
      ],
      onOutcome: (m, status) async => outcome = status,
    );
    await tester.tap(find.byKey(const Key('meeting-menu-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark missed'));
    await tester.pumpAndSettle();
    expect(outcome, 'Missed');
  });
}
