import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart';
import 'package:parent_portal_module/widgets/availability_request_card.dart';

void main() {
  const req = AvailabilityRequest(roundId: 'r1', roundNo: 1);

  Widget host(
    List<AvailabilityRequest> requests,
    Future<void> Function(String, List<DateTime>) onSubmit, {
    double width = 800,
    ThemeData? theme,
  }) =>
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: AvailabilityRequestCard(
                  requests: requests, onSubmit: onSubmit),
            ),
          ),
        ),
      );

  Finder submit() => find.byKey(const ValueKey('availability-submit'));

  Future<void> pickRow(WidgetTester t, int i, {int dayOffset = 3}) async {
    await t.tap(find.byKey(ValueKey('availability-date-$i')));
    await t.pumpAndSettle();
    // Date picker: choose the day by tapping its number, then OK.
    final target = DateTime.now().add(Duration(days: dayOffset));
    if (target.month != DateTime.now().month) {
      await t.tap(find.byIcon(Icons.chevron_right));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('${target.day}').last);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('availability-time-$i')));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  testWidgets('hidden when there are no requests', (t) async {
    await t.pumpWidget(host(const [], (_, __) async {}));
    expect(find.byType(AvailabilityRequestCard), findsOneWidget);
    expect(find.byKey(const ValueKey('availability-date-0')), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('one row initially, add up to 10', (t) async {
    await t.pumpWidget(host([req], (_, __) async {}));
    expect(find.byKey(const ValueKey('availability-date-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('availability-date-1')), findsNothing);
    for (var i = 1; i < 10; i++) {
      await t.ensureVisible(find.text('Add another time'));
      await t.tap(find.text('Add another time'));
      await t.pump();
    }
    expect(find.byKey(const ValueKey('availability-date-9')), findsOneWidget);
    expect(find.text('Add another time'), findsNothing);
  });

  testWidgets('submit disabled until first row complete, then submits',
      (t) async {
    String? gotId;
    List<DateTime>? gotSlots;
    await t.pumpWidget(host([req], (id, s) async {
      gotId = id;
      gotSlots = s;
    }));
    expect(t.widget<FilledButton>(submit()).onPressed, isNull);
    await pickRow(t, 0);
    expect(t.widget<FilledButton>(submit()).onPressed, isNotNull);
    await t.tap(submit());
    await t.pumpAndSettle();
    expect(gotId, 'r1');
    expect(gotSlots, hasLength(1));
    expect(gotSlots!.first.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('past time shows inline error and does not submit', (t) async {
    var calls = 0;
    await t.pumpWidget(host([req], (_, __) async => calls++));
    // Today's date with 00:00 picked is in the past (unless run at midnight).
    await t.tap(find.byKey(const ValueKey('availability-date-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('availability-time-0')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    await t.pumpAndSettle();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), '12');
    await t.enterText(fields.at(1), '00');
    await t.tap(find.text('AM'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(submit());
    await t.pumpAndSettle();
    expect(find.text('Choose a time in the future.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('later rounds explain Guidance needs other dates', (t) async {
    await t.pumpWidget(host(
        [const AvailabilityRequest(roundId: 'r2', roundNo: 2)],
        (_, __) async {}));
    expect(
        find.text(
            'Guidance could not make the previous times. Please pick other dates.'),
        findsOneWidget);
    await t.pumpWidget(host([req], (_, __) async {}));
    expect(find.textContaining('could not make'), findsNothing);
  });

  homePageTests();

  testWidgets('no overflow on a narrow dark screen', (t) async {
    await t.pumpWidget(host(
        [const AvailabilityRequest(roundId: 'r2', roundNo: 2, studentName: 'Juan Dela Cruz')],
        (_, __) async {},
        width: 320,
        theme: ThemeData.dark()));
    await t.tap(find.text('Add another time'));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}

void homePageTests() {
  Widget page({List<AvailabilityRequest>? reqs, bool wired = true}) =>
      MaterialApp(
        home: ParentPortalHomePage(
          initialAvailabilityRequests: reqs,
          onSubmitAvailability: wired ? (_, __) async {} : null,
        ),
      );

  void size(WidgetTester t, double w) {
    t.view.physicalSize = Size(w, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  for (final w in [1280.0, 360.0]) {
    testWidgets('home page shows the availability card at width $w',
        (t) async {
      size(t, w);
      await t.pumpWidget(page(
          reqs: const [AvailabilityRequest(roundId: 'r1', roundNo: 1)]));
      await t.pumpAndSettle();
      expect(find.text('Guidance needs your availability'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('home page hides the card without requests or handler',
      (t) async {
    size(t, 1280);
    await t.pumpWidget(page());
    await t.pumpAndSettle();
    expect(find.text('Guidance needs your availability'), findsNothing);
    await t.pumpWidget(page(
        reqs: const [AvailabilityRequest(roundId: 'r1', roundNo: 1)],
        wired: false));
    await t.pumpAndSettle();
    expect(find.text('Guidance needs your availability'), findsNothing);
  });
}
