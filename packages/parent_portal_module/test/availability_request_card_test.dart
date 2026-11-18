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

  Finder date(String id, int i) => find.byKey(ValueKey('availability-date-$id-$i'));
  Finder time(String id, int i) => find.byKey(ValueKey('availability-time-$id-$i'));
  Finder submit(String id) => find.byKey(ValueKey('availability-submit-$id'));

  Future<void> pickDate(WidgetTester t, String id, int i) async {
    await t.ensureVisible(date(id, i));
    await t.tap(date(id, i));
    await t.pumpAndSettle();
    // Tomorrow, always selectable. If it falls in next month, page forward.
    final target = DateTime.now().add(const Duration(days: 1));
    if (target.month != DateTime.now().month) {
      await t.tap(find.byIcon(Icons.chevron_right));
      await t.pumpAndSettle();
    }
    await t.tap(find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('${target.day}')));
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  Future<void> pickTime(WidgetTester t, String id, int i) async {
    await t.ensureVisible(time(id, i));
    await t.tap(time(id, i));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  testWidgets('hidden when there are no requests', (t) async {
    await t.pumpWidget(host(const [], (_, __) async {}));
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Guidance needs your availability'), findsNothing);
  });

  testWidgets('one row initially, add up to 10', (t) async {
    await t.pumpWidget(host([req], (_, __) async {}));
    expect(date('r1', 0), findsOneWidget);
    expect(date('r1', 1), findsNothing);
    for (var i = 1; i < 10; i++) {
      await t.ensureVisible(find.text('Add another time'));
      await t.tap(find.text('Add another time'));
      await t.pump();
    }
    expect(date('r1', 9), findsOneWidget);
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
    expect(t.widget<FilledButton>(submit('r1')).onPressed, isNull);
    await pickDate(t, 'r1', 0);
    expect(t.widget<FilledButton>(submit('r1')).onPressed, isNull);
    await pickTime(t, 'r1', 0);
    expect(t.widget<FilledButton>(submit('r1')).onPressed, isNotNull);
    await t.tap(submit('r1'));
    await t.pumpAndSettle();
    expect(gotId, 'r1');
    expect(gotSlots, hasLength(1));
    expect(gotSlots!.first.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('past time shows inline error and does not submit', (t) async {
    var calls = 0;
    await t.pumpWidget(host([req], (_, __) async => calls++));
    // Today (first selectable day) with a time picked far enough back that
    // it is always in the past, via the picker's text-entry mode:
    // 12:00 AM is past except in the first minute of the day, so instead use
    // a clear margin: a time at least an hour before now, on a day we only
    // run this on when that stays today; otherwise skip the margin to 12:00
    // AM of today which is then > 1h in the past anyway.
    await t.tap(date('r1', 0));
    await t.pumpAndSettle();
    await t.tap(find.text('OK')); // today
    await t.pumpAndSettle();
    final now = DateTime.now();
    final past = now.subtract(const Duration(hours: 1));
    final useMargin = past.day == now.day;
    await t.tap(time('r1', 0));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    await t.pumpAndSettle();
    final fields = find.byType(TextField);
    final h = useMargin ? (past.hour % 12 == 0 ? 12 : past.hour % 12) : 12;
    final m = useMargin ? past.minute : 0;
    await t.enterText(fields.at(0), '$h');
    await t.enterText(fields.at(1), m.toString().padLeft(2, '0'));
    final pm = useMargin ? past.hour >= 12 : false;
    await t.tap(find.text(pm ? 'PM' : 'AM'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(submit('r1'));
    await t.pumpAndSettle();
    expect(find.text('Choose a time in the future.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('an incomplete row blocks submit with an inline message',
      (t) async {
    var calls = 0;
    await t.pumpWidget(host([req], (_, __) async => calls++));
    await pickDate(t, 'r1', 0);
    await pickTime(t, 'r1', 0);
    await t.tap(find.text('Add another time'));
    await t.pump();
    await pickDate(t, 'r1', 1); // date only
    await t.ensureVisible(submit('r1'));
    await t.tap(submit('r1'));
    await t.pumpAndSettle();
    expect(find.text('Finish or remove the incomplete time.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('two requests render two forms, each submits its own round',
      (t) async {
    final calls = <String, List<DateTime>>{};
    await t.pumpWidget(host([
      const AvailabilityRequest(
          roundId: 'a', roundNo: 1, studentName: 'Ana Reyes'),
      const AvailabilityRequest(
          roundId: 'b', roundNo: 1, studentName: 'Ben Reyes'),
    ], (id, s) async => calls[id] = s));
    expect(find.text('Guidance needs your availability'), findsNWidgets(2));
    expect(find.textContaining('Ana Reyes'), findsOneWidget);
    expect(find.textContaining('Ben Reyes'), findsOneWidget);
    await pickDate(t, 'b', 0);
    await pickTime(t, 'b', 0);
    expect(t.widget<FilledButton>(submit('a')).onPressed, isNull);
    await t.ensureVisible(submit('b'));
    await t.tap(submit('b'));
    await t.pumpAndSettle();
    expect(calls.keys, ['b']);
  });

  testWidgets('errors are friendly, never raw exception text', (t) async {
    await t.pumpWidget(host([req], (_, __) async => throw StateError('boom 42')));
    await pickDate(t, 'r1', 0);
    await pickTime(t, 'r1', 0);
    await t.tap(submit('r1'));
    await t.pumpAndSettle();
    expect(find.text("We couldn't send your times. Please try again."),
        findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  // Real server strings from add_parent_availability_scheduling.sql.
  const serverMappings = {
    'Every time must be in the future.':
        'One of the times is no longer in the future. Please pick other times.',
    'A time Guidance already declined cannot be offered again.':
        'Guidance already declined one of those times. '
            'Please pick a different time.',
    'The same time was offered twice.':
        'You picked the same time twice. Please remove the duplicate.',
    'This availability request is no longer open.':
        'This request is no longer open. Please refresh to see the latest.',
    'This endorsement no longer needs your availability.':
        'Guidance no longer needs these times.',
  };
  for (final entry in serverMappings.entries) {
    testWidgets('server error "${entry.key}" maps precisely', (t) async {
      await t.pumpWidget(host([req], (_, __) async => throw Exception(entry.key)));
      await pickDate(t, 'r1', 0);
      await pickTime(t, 'r1', 0);
      await t.tap(submit('r1'));
      await t.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('date and time buttons carry row-numbered semantics',
      (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host([req], (_, __) async {}));
    await t.tap(find.text('Add another time'));
    await t.pump();
    expect(find.bySemanticsLabel(RegExp('Date for time 2')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Time for time 2')), findsOneWidget);
    handle.dispose();
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

  testWidgets('narrow dark screen: no overflow, time is readable',
      (t) async {
    await t.pumpWidget(host([
      const AvailabilityRequest(
          roundId: 'r2', roundNo: 2, studentName: 'Juan Dela Cruz')
    ], (_, __) async {}, width: 320, theme: ThemeData.dark()));
    await t.tap(find.text('Add another time'));
    await t.pump();
    await pickTime(t, 'r2', 1);
    expect(find.text('Pick a time'), findsOneWidget); // row 0 still empty
    // The chosen time is shown in full (stacked layout, no ellipsis clip).
    final box = t.getSize(time('r2', 1));
    expect(box.width, greaterThan(200));
    expect(t.takeException(), isNull);
  });

  group('home page', () {
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
      testWidgets('shows the availability card at width $w', (t) async {
        size(t, w);
        await t.pumpWidget(page(
            reqs: const [AvailabilityRequest(roundId: 'r1', roundNo: 1)]));
        await t.pumpAndSettle();
        expect(find.text('Guidance needs your availability'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('hides the card without requests or handler', (t) async {
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
  });
}
