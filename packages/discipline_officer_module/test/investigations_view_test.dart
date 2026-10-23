import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';

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

/// Opens the first case's popup (the eye button on its row).
Future<void> _openCase(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('investigation-view-i1')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state', (tester) async {
    await _pump(tester, const []);
    expect(find.text('No investigations yet'), findsOneWidget);
  });

  testWidgets(
      'the table shows the case; the incident notes and photo evidence open in '
      'the case popup', (tester) async {
    await _pump(tester, [_inv(evidence: const ['a.jpg'])]);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Fighting'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    // The notes and evidence aren't in the row...
    expect(find.text('Fight in the hallway'), findsNothing);

    await _openCase(tester);
    expect(find.text('Fight in the hallway'), findsOneWidget);
    expect(find.text('Photo evidence (1)'), findsOneWidget);
  });

  testWidgets(
      'a declined meeting shows in the row, its reply in the popup, and the '
      'officer can book a new one', (tester) async {
    await _pump(
      tester,
      [
        _inv(meetings: [_meeting(status: 'Declined', note: 'Out of town')])
      ],
      onSchedule: (i, at, where, who) async {},
    );
    expect(find.byKey(const Key('meeting-status-m1')), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.byKey(const Key('schedule-meeting-i1')), findsOneWidget);
    await tester.longPress(find.byKey(const Key('schedule-meeting-i1')));
    await tester.pumpAndSettle();
    expect(find.text('Reschedule meeting'), findsOneWidget);

    await _openCase(tester);
    expect(find.textContaining('Out of town'), findsOneWidget);
  });

  testWidgets('a confirmed meeting shows Confirmed and no schedule button',
      (tester) async {
    await _pump(tester, [
      _inv(meetings: [_meeting(status: 'Confirmed')])
    ], onSchedule: (i, at, where, who) async {});
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byKey(const Key('schedule-meeting-i1')), findsNothing);
  });

  testWidgets('with no meeting yet the officer can schedule one',
      (tester) async {
    await _pump(
      tester,
      [_inv()],
      onSchedule: (i, at, where, who) async {},
      onComplete: (i, f, r) async {},
    );
    expect(find.text('No meeting yet'), findsOneWidget);
    expect(find.byKey(const Key('schedule-meeting-i1')), findsOneWidget);
    expect(find.byKey(const Key('complete-investigation-i1')), findsOneWidget);
  });

  testWidgets('a completed investigation is read-only and shows findings',
      (tester) async {
    await _pump(
      tester,
      [_inv(status: 'Complete', findings: 'Mutual altercation; both warned')],
      onSchedule: (i, at, where, who) async {},
      onComplete: (i, f, r) async {},
    );
    expect(find.text('Complete'), findsOneWidget);
    expect(find.byKey(const Key('schedule-meeting-i1')), findsNothing);
    expect(find.byKey(const Key('complete-investigation-i1')), findsNothing);

    await _openCase(tester);
    expect(find.text('Mutual altercation; both warned'), findsOneWidget);
    expect(find.byKey(const Key('detail-complete')), findsNothing);
  });

  testWidgets('the Status filter narrows to open or complete cases',
      (tester) async {
    await _pump(tester, [
      _inv(id: 'a'),
      _inv(id: 'b', status: 'Complete', findings: 'done'),
    ]);
    expect(find.text('Jane Doe'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('investigations-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('schedule-meeting-i1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('meeting-location')), 'Guidance Office');
    await tester.tap(find.byKey(const Key('meeting-invitee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parent').last);
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const Key('complete-investigation-i1')));
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

  testWidgets('the case popup can start the schedule flow', (tester) async {
    var scheduled = false;
    await _pump(
      tester,
      [_inv()],
      onSchedule: (i, at, where, who) async => scheduled = true,
      onComplete: (i, f, r) async {},
    );
    await _openCase(tester);
    expect(find.byKey(const Key('detail-schedule')), findsOneWidget);
    expect(find.byKey(const Key('detail-complete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-schedule')));
    await tester.pumpAndSettle();
    // The case popup closed and the schedule form opened.
    expect(find.byKey(const Key('meeting-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('meeting-save')));
    await tester.pumpAndSettle();
    expect(scheduled, isTrue);
  });

  testWidgets('a meeting can be marked missed from the case popup',
      (tester) async {
    String? outcome;
    await _pump(
      tester,
      [
        _inv(meetings: [
          _meeting(status: 'Confirmed', fromNow: const Duration(hours: 1))
        ])
      ],
      onOutcome: (m, status) async => outcome = status,
    );
    await _openCase(tester);
    await tester.tap(find.byKey(const Key('meeting-menu-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark missed'));
    await tester.pumpAndSettle();
    expect(outcome, 'Missed');
  });

  group('on the Discipline Officer dashboard', () {
    void size(WidgetTester tester, Size s) {
      tester.view.physicalSize = s;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpDashboard(WidgetTester tester, Size s) async {
      size(tester, s);
      await tester.pumpWidget(MaterialApp(
        home: DisciplineOfficerDashboardPage(
          investigations: [_inv()],
          onScheduleMeeting: (i, at, where, who) async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an Investigations tab lists the cases', (tester) async {
      await pumpDashboard(tester, const Size(1400, 1000));
      tester.takeException();

      // The tab strip scrolls sideways when the tabs are wider than the window.
      await tester.ensureVisible(find.text('Investigations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Investigations'));
      await tester.pumpAndSettle();
      tester.takeException();

      expect(find.byKey(const ValueKey('investigation-i1')), findsOneWidget);
    });

    testWidgets('six tabs fit a 1100px window without overflowing',
        (tester) async {
      await pumpDashboard(tester, const Size(1100, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Investigations'), findsOneWidget);
      expect(find.text('Endorsements'), findsOneWidget);
    });
  });
}
