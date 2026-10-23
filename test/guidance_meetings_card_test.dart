import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GuidanceMeetingInvite _m({
  String id = 'm1',
  String status = 'Proposed',
  Duration fromNow = const Duration(days: 2),
  String? note,
}) =>
    GuidanceMeetingInvite(
      id: id,
      scheduledAt: DateTime.now().add(fromNow),
      location: 'Guidance Office',
      status: status,
      responseNote: note,
    );

Future<void> _pump(
  WidgetTester tester,
  List<GuidanceMeetingInvite> meetings, {
  Future<void> Function(GuidanceMeetingInvite, bool, String?)? onRespond,
  GuidanceMeetingAudience audience = GuidanceMeetingAudience.student,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: GuidanceMeetingsCard(
          meetings: meetings,
          audience: audience,
          onRespond: onRespond,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows nothing when there are no meetings', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Meetings'), findsNothing);
  });

  testWidgets('a proposed meeting can be confirmed', (tester) async {
    final calls = <(String, bool, String?)>[];
    await _pump(tester, [_m()],
        onRespond: (m, accept, note) async => calls.add((m.id, accept, note)));
    expect(find.text('Meetings'), findsOneWidget);
    expect(find.text('At Guidance Office'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meeting-confirm-m1')));
    await tester.pumpAndSettle();
    expect(calls, [('m1', true, null)]);
  });

  testWidgets('declining sends an optional note', (tester) async {
    final calls = <(String, bool, String?)>[];
    await _pump(tester, [_m()],
        onRespond: (m, accept, note) async => calls.add((m.id, accept, note)));

    await tester.tap(find.byKey(const Key('meeting-decline-m1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meeting-note')), 'Out of town');
    await tester.tap(find.byKey(const Key('meeting-decline-send')));
    await tester.pumpAndSettle();

    expect(calls, [('m1', false, 'Out of town')]);
  });

  testWidgets('declining without a note is allowed', (tester) async {
    final calls = <(String, bool, String?)>[];
    await _pump(tester, [_m()],
        onRespond: (m, accept, note) async => calls.add((m.id, accept, note)));
    await tester.tap(find.byKey(const Key('meeting-decline-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-decline-send')));
    await tester.pumpAndSettle();
    expect(calls, [('m1', false, null)]);
  });

  testWidgets('after confirming, the status shows and the answer can change',
      (tester) async {
    await _pump(tester, [_m(status: 'Confirmed')], onRespond: (m, a, n) async {});
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byKey(const Key('meeting-confirm-m1')), findsNothing);
    expect(find.byKey(const Key('meeting-decline-m1')), findsOneWidget);
  });

  testWidgets('a declined meeting can still be confirmed instead',
      (tester) async {
    await _pump(tester, [_m(status: 'Declined', note: 'Out of town')],
        onRespond: (m, a, n) async {});
    expect(find.text('Declined'), findsOneWidget);
    expect(find.byKey(const Key('meeting-confirm-m1')), findsOneWidget);
  });

  testWidgets('a meeting that has passed is read-only', (tester) async {
    await _pump(
        tester, [_m(status: 'Proposed', fromNow: const Duration(hours: -2))],
        onRespond: (m, a, n) async {});
    expect(find.byKey(const Key('meeting-confirm-m1')), findsNothing);
    expect(find.byKey(const Key('meeting-decline-m1')), findsNothing);
  });

  testWidgets('a completed or cancelled meeting has no actions',
      (tester) async {
    await _pump(tester, [
      _m(id: 'a', status: 'Completed', fromNow: const Duration(days: 1)),
      _m(id: 'b', status: 'Cancelled'),
    ], onRespond: (m, a, n) async {});
    expect(find.byKey(const Key('meeting-confirm-a')), findsNothing);
    expect(find.byKey(const Key('meeting-decline-b')), findsNothing);
  });

  testWidgets('without a handler the card is read-only', (tester) async {
    await _pump(tester, [_m()]);
    expect(find.byKey(const Key('meeting-confirm-m1')), findsNothing);
  });

  testWidgets('a failed answer shows the error and keeps the buttons',
      (tester) async {
    await _pump(tester, [_m()],
        onRespond: (m, a, n) async => throw Exception('This meeting has passed'));
    await tester.tap(find.byKey(const Key('meeting-confirm-m1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('This meeting has passed'), findsOneWidget);
    expect(find.byKey(const Key('meeting-confirm-m1')), findsOneWidget);
  });

  testWidgets('a parent sees wording about their child', (tester) async {
    await _pump(tester, [_m()],
        audience: GuidanceMeetingAudience.parent,
        onRespond: (m, a, n) async {});
    expect(find.textContaining('your child'), findsWidgets);
  });
}
