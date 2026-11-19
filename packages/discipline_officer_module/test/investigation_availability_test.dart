import 'package:dashboard_layout/dashboard_layout.dart' show formatDateTime12h;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:discipline_officer_module/pages/investigations/investigations_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t1 = DateTime(2026, 11, 25, 9);
final _t2 = DateTime(2026, 11, 26, 14, 30);

InvestigationModel _inv() => InvestigationModel(
      id: 'i1',
      studentName: 'Carl Cruz',
      studentNumber: '2026-0002',
      section: 'BSIT-3A',
      offenseLabel: 'Bullying',
      incidentNotes: 'Took lunch money',
      createdAt: DateTime(2026, 11, 19),
      status: 'Open',
      meetings: const [],
      evidencePaths: const [],
    );

InvestigationAvailabilityRound _round(String status) =>
    InvestigationAvailabilityRound(
      roundId: 'r1',
      roundNo: 1,
      status: status,
      requestedAt: DateTime(2026, 11, 20),
      offeredTimes: status == 'Offered'
          ? [OfferedTime(id: 'sl1', at: _t1), OfferedTime(id: 'sl2', at: _t2)]
          : const [],
    );

Future<void> _pump(WidgetTester tester, InvestigationsView view) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: view)),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
}

InvestigationsView _view({
  Map<String, InvestigationAvailabilityRound>? rounds,
  Future<void> Function(InvestigationModel)? onRequest,
  Future<void> Function(String)? onCancel,
  Future<void> Function(String, String, String?)? onApprove,
  Future<void> Function(String, String?)? onDecline,
}) =>
    InvestigationsView(
      investigations: [_inv()],
      onSchedule: (inv, at, where, who) async {},
      availabilityRounds: rounds,
      onRequestAvailability: onRequest,
      onCancelAvailability: onCancel,
      onApproveAvailability: onApprove,
      onDeclineAvailability: onDecline,
    );

void main() {
  testWidgets('an open investigation with no round offers Request availability',
      (tester) async {
    InvestigationModel? asked;
    await _pump(
      tester,
      _view(rounds: const {}, onRequest: (inv) async => asked = inv),
    );
    expect(find.byKey(const Key('schedule-meeting-i1')), findsOneWidget,
        reason: 'the direct schedule stays available');
    await tester.tap(find.byKey(const Key('request-availability-i1')));
    await tester.pumpAndSettle();
    expect(asked?.id, 'i1');
  });

  testWidgets('without the availability wiring there is no request button',
      (tester) async {
    await _pump(tester, _view());
    expect(find.byKey(const Key('request-availability-i1')), findsNothing);
    expect(find.byKey(const Key('schedule-meeting-i1')), findsOneWidget);
  });

  testWidgets('an open round shows waiting and offers Cancel only',
      (tester) async {
    String? cancelled;
    await _pump(
      tester,
      _view(
        rounds: {'i1': _round('Open')},
        onRequest: (_) async {},
        onCancel: (id) async => cancelled = id,
      ),
    );
    expect(find.textContaining('Waiting for the parent'), findsOneWidget);
    expect(find.byKey(const Key('request-availability-i1')), findsNothing);
    expect(find.byKey(const Key('schedule-meeting-i1')), findsNothing);
    await tester.tap(find.byKey(const Key('cancel-availability-i1')));
    await tester.pumpAndSettle();
    expect(cancelled, 'r1');
  });

  testWidgets('offered times can be reviewed and one approved', (tester) async {
    String? round, slot, location;
    await _pump(
      tester,
      _view(
        rounds: {'i1': _round('Offered')},
        onRequest: (_) async {},
        onApprove: (r, s, l) async {
          round = r;
          slot = s;
          location = l;
        },
        onDecline: (r, n) async {},
      ),
    );
    await tester.tap(find.byKey(const Key('review-availability-i1')));
    await tester.pumpAndSettle();
    expect(find.text(formatDateTime12h(_t1)), findsOneWidget);
    expect(find.text(formatDateTime12h(_t2)), findsOneWidget);

    await tester.tap(find.byKey(const Key('availability-slot-sl2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('availability-approve')));
    await tester.pumpAndSettle();

    expect(round, 'r1');
    expect(slot, 'sl2');
    expect(location, 'Guidance Office');
  });

  testWidgets('approve needs a time chosen', (tester) async {
    var approved = 0;
    await _pump(
      tester,
      _view(
        rounds: {'i1': _round('Offered')},
        onRequest: (_) async {},
        onApprove: (r, s, l) async => approved++,
        onDecline: (r, n) async {},
      ),
    );
    await tester.tap(find.byKey(const Key('review-availability-i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('availability-approve')));
    await tester.pumpAndSettle();
    expect(approved, 0);
  });

  testWidgets('declining every time sends the note', (tester) async {
    String? round, note;
    await _pump(
      tester,
      _view(
        rounds: {'i1': _round('Offered')},
        onRequest: (_) async {},
        onApprove: (r, s, l) async {},
        onDecline: (r, n) async {
          round = r;
          note = n;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('review-availability-i1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('availability-note')), 'Those days are exams');
    await tester.tap(find.byKey(const Key('availability-decline')));
    await tester.pumpAndSettle();
    expect(round, 'r1');
    expect(note, 'Those days are exams');
  });

  testWidgets('a declined round lets the officer ask again', (tester) async {
    await _pump(
      tester,
      _view(rounds: {'i1': _round('Declined')}, onRequest: (_) async {}),
    );
    expect(find.byKey(const Key('request-availability-i1')), findsOneWidget);
  });
}
