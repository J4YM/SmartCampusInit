import 'package:dashboard_layout/dashboard_layout.dart'
    show AppPopup, AppPopupCheckboxTile, BentoCard, CardPaginationFooter;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case(
  String id, {
  String name = 'Jane Doe',
  String number = '24-0001',
  String type = 'Major – Fighting',
  DateTime? at,
  bool escalated = true,
}) =>
    DisciplineCaseModel(
      id: id,
      studentName: name,
      studentNumber: number,
      programGradeSection: 'BSIT-3A',
      violationType: type,
      submittedBy: 'Guard',
      submitterRole: '',
      incidentDateTime: at ?? DateTime(2026, 1, 1, 9),
      description: '',
      isEscalated: escalated,
    );

EscalationReportModel _report(String id, {String status = 'Pending_GC'}) =>
    EscalationReportModel(
      id: id,
      studentName: 'Jane Doe',
      studentNumber: '24-0001',
      title: 'Escalation',
      summary: 'Repeated fighting.',
      message: 'Please visit.',
      channels: const ['sms'],
      source: 'officer',
      status: status,
      createdAt: DateTime(2026, 2, 1, 10),
    );

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester, {
  required List<DisciplineCaseModel> cases,
  List<EscalationReportModel> reports = const [],
  Future<void> Function(EscalationDraft)? onIssue,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: ParentalInterventionView(
            reports: reports,
            cases: cases,
            onIssue: onIssue,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  tester.takeException(); // Ahem-width test fonts may overflow a label
}

/// The popup's violation tick-boxes (not the SMS / Email ones).
final _violationTiles = find.byWidgetPredicate((w) =>
    w is AppPopupCheckboxTile &&
    w.key.toString().contains('escalation-violation-'));

Finder _card(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(BentoCard),
    );

void main() {
  final threeFights = [
    _case('a', type: 'Major – Fighting', at: DateTime(2026, 3, 1)),
    _case('b', type: 'Major – Bullying', at: DateTime(2026, 2, 1)),
    _case('c', type: 'Major – Vandalism', at: DateTime(2026, 1, 1)),
  ];

  testWidgets('wide: history and reports share one row, reports on the right',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        cases: threeFights, reports: [_report('r1')], onIssue: (_) async {});

    final history = tester.getRect(_card('Escalated Violation History').first);
    final reports = tester.getRect(_card('Escalation Reports').first);
    expect(reports.left, greaterThan(history.right - 1),
        reason: 'reports card is to the right of the history');
    expect(reports.width, 320, reason: 'the standard side-card width');
    expect(reports.top, history.top, reason: 'same row');
    expect(reports.height, history.height, reason: 'same height');
  });

  testWidgets('narrow: the cards stack, history first', (tester) async {
    _size(tester, const Size(700, 1600));
    await _pump(tester, cases: threeFights, reports: [_report('r1')]);
    final history = tester.getRect(_card('Escalated Violation History').first);
    final reports = tester.getRect(_card('Escalation Reports').first);
    expect(reports.top, greaterThanOrEqualTo(history.bottom));
  });

  testWidgets('a student with several escalated violations is ONE row',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, cases: [
      ...threeFights,
      _case('x', name: 'John Roe', number: '24-0002', type: 'Major – Theft'),
    ]);

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('John Roe'), findsOneWidget);
    expect(find.text('3 violations'), findsOneWidget);
    // Collapsed: her individual violations are not listed.
    expect(find.text('Major – Bullying'), findsNothing);
  });

  testWidgets('opening the dropdown lists only the violations, no name',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, cases: threeFights, onIssue: (_) async {});

    await tester.tap(find.byKey(const ValueKey("escalated-toggle-24-0001")));
    await tester.pumpAndSettle();

    expect(find.text("Major – Fighting"), findsOneWidget);
    expect(find.text('Major – Bullying'), findsOneWidget);
    expect(find.text('Major – Vandalism'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget,
        reason: 'only the dropdown header carries the name');

    await tester.tap(find.byKey(const ValueKey("escalated-toggle-24-0001")));
    await tester.pumpAndSettle();
    expect(find.text("Major – Bullying"), findsNothing);
  });

  testWidgets('every row ends with an icon-only Issue Escalation Report button',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        cases: [
          ...threeFights,
          _case('x', name: 'John Roe', number: '24-0002', type: 'Major – Theft'),
        ],
        onIssue: (_) async {});
    await tester.tap(find.byKey(const ValueKey("escalated-toggle-24-0001")));
    await tester.pumpAndSettle();

    final history = _card('Escalated Violation History').first;
    final buttons = find.descendant(
        of: history, matching: find.byIcon(kIssueEscalationIcon));
    // Jane's header + her 3 violations + John's single row.
    expect(buttons, findsNWidgets(5));
    // Icon only: the label text lives on the side card's button, not on rows.
    expect(
        find.descendant(
            of: history, matching: find.text('Issue Escalation Report')),
        findsNothing);

    // Each sits at the row's far right edge: all the same x.
    final rights = [
      for (var i = 0; i < 5; i++) tester.getRect(buttons.at(i)).right
    ];
    expect(rights.map((r) => r.round()).toSet(), hasLength(1),
        reason: rights.toString());
  });

  testWidgets('a row button opens the shared popup with that violation ticked',
      (tester) async {
    _size(tester, const Size(1400, 1400));
    EscalationDraft? sent;
    await _pump(tester, cases: threeFights, onIssue: (d) async => sent = d);

    await tester.tap(find.byKey(const ValueKey("escalated-toggle-24-0001")));
    await tester.pumpAndSettle();
    // The "Major – Bullying" row's own button: only that violation is ticked.
    final bullying = find.byKey(const ValueKey('escalated-violation-b'));
    await tester.tap(find.descendant(
        of: bullying, matching: find.byIcon(kIssueEscalationIcon)));
    await tester.pumpAndSettle();

    expect(find.byType(AppPopup), findsOneWidget);
    final checks =
        tester.widgetList<AppPopupCheckboxTile>(_violationTiles);
    expect(checks, hasLength(3));
    expect(checks.where((c) => c.value == true), hasLength(1));

    await tester.enterText(
        find.descendant(
                of: find.byType(AppPopup), matching: find.byType(TextField))
            .first,
        'Repeated incidents.');
    await tester.pump();
    await tester.tap(find.text('Send to Guidance'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.studentNumber, '24-0001');
    expect(sent!.violationIds, ['b']);
  });

  testWidgets("the header button pre-ticks all of the student's violations",
      (tester) async {
    _size(tester, const Size(1400, 1400));
    await _pump(tester, cases: threeFights, onIssue: (_) async {});
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('escalated-header-24-0001')),
        matching: find.byIcon(kIssueEscalationIcon)));
    await tester.pumpAndSettle();
    final checks =
        tester.widgetList<AppPopupCheckboxTile>(_violationTiles);
    expect(checks, hasLength(3));
    expect(checks.every((c) => c.value == true), isTrue);
  });

  testWidgets('demo mode (no onIssue) hides every Issue action',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, cases: threeFights);
    expect(find.byIcon(kIssueEscalationIcon), findsNothing);
  });

  testWidgets('both cards paginate with the shared footer', (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, cases: [
      for (var i = 0; i < 12; i++)
        _case('c$i', name: 'Student $i', number: '24-10$i'),
    ], reports: [
      for (var i = 0; i < 12; i++) _report('r$i'),
    ]);
    expect(find.byType(CardPaginationFooter), findsNWidgets(2));
    // 10 per page on a wide screen: the 11th student is on page 2.
    expect(find.text('Student 10'), findsNothing);
  });

  testWidgets('dark mode renders without errors', (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        cases: threeFights,
        reports: [_report('r1', status: 'Approved')],
        onIssue: (_) async {},
        brightness: Brightness.dark);
    expect(find.text('Escalation Reports'), findsOneWidget);
  });

  testWidgets("the Reports card has no Issue button", (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        cases: threeFights, reports: [_report("r1")], onIssue: (_) async {});
    expect(
        find.descendant(
            of: _card("Escalation Reports").first,
            matching: find.text("Issue Escalation Report")),
        findsNothing);
  });

  testWidgets("a dropdown's violations are indented under the student name",
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, cases: threeFights, onIssue: (_) async {});
    await tester.tap(find.byKey(const ValueKey("escalated-toggle-24-0001")));
    await tester.pumpAndSettle();
    final nameX = tester.getTopLeft(find.text("Jane Doe")).dx;
    for (final v in ["Fighting", "Bullying", "Vandalism"]) {
      expect(tester.getTopLeft(find.text("Major – $v")).dx,
          greaterThanOrEqualTo(nameX + 20),
          reason: "$v is indented inside the dropdown");
    }
  });

  group('which rows are clickable', () {
    List<bool?> ticks(WidgetTester tester) => [
          for (final c in tester.widgetList<AppPopupCheckboxTile>(_violationTiles))
            c.value
        ];

    testWidgets('clicking a dropdown header opens and closes it, with no popup',
        (tester) async {
      _size(tester, const Size(1400, 1400));
      await _pump(tester, cases: threeFights, onIssue: (_) async {});

      // Anywhere on the header row — name, section, the count pill.
      var open = false;
      for (final label in ['Jane Doe', 'BSIT-3A', '3 violations', 'Jane Doe']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        open = !open;
        expect(find.byType(AppPopup), findsNothing, reason: '$label: no popup');
        expect(find.text('Major – Bullying'), open ? findsOneWidget : findsNothing,
            reason: '$label: dropdown ${open ? "opens" : "closes"}');
      }
    });

    testWidgets('tapping a violation row does nothing', (tester) async {
      _size(tester, const Size(1400, 1400));
      await _pump(tester, cases: threeFights, onIssue: (_) async {});
      await tester.tap(find.byKey(const ValueKey('escalated-toggle-24-0001')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Major – Vandalism'));
      await tester.pumpAndSettle();
      expect(find.byType(AppPopup), findsNothing);
      expect(find.text('Major – Vandalism'), findsOneWidget);
    });

    testWidgets('a single-violation row does nothing on tap', (tester) async {
      _size(tester, const Size(1400, 900));
      await _pump(tester,
          cases: [_case('x', name: 'John Roe', number: '24-0002')],
          onIssue: (_) async {});
      await tester.tap(find.text('John Roe'));
      await tester.pumpAndSettle();
      expect(find.byType(AppPopup), findsNothing);
    });

    testWidgets('only a dropdown header shows the click cursor', (tester) async {
      _size(tester, const Size(1400, 900));
      await _pump(tester, cases: [
        ...threeFights,
        _case('x', name: 'John Roe', number: '24-0002', type: 'Major – Theft'),
      ], onIssue: (_) async {});
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      Future<MouseCursor> cursorOver(String label) async {
        await gesture.moveTo(tester.getCenter(find.text(label)));
        await tester.pump();
        return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
      }

      // Jane has three violations: her header is a dropdown, so it is clickable.
      expect(await cursorOver('3 violations'), SystemMouseCursors.click);
      // John has one: nothing to open.
      expect(await cursorOver('Major – Theft'), isNot(SystemMouseCursors.click));
    });

    testWidgets('the icon button still issues the report for the student',
        (tester) async {
      _size(tester, const Size(1400, 1400));
      await _pump(tester, cases: threeFights, onIssue: (_) async {});
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('escalated-header-24-0001')),
          matching: find.byIcon(kIssueEscalationIcon)));
      await tester.pumpAndSettle();
      expect(find.byType(AppPopup), findsOneWidget);
      expect(ticks(tester), [true, true, true]);
    });

    testWidgets('the chevron still opens and closes the dropdown',
        (tester) async {
      _size(tester, const Size(1400, 900));
      await _pump(tester, cases: threeFights, onIssue: (_) async {});
      await tester.tap(find.byKey(const ValueKey('escalated-toggle-24-0001')));
      await tester.pumpAndSettle();
      expect(find.text('Major – Bullying'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('escalated-toggle-24-0001')));
      await tester.pumpAndSettle();
      expect(find.text('Major – Bullying'), findsNothing);
    });

    testWidgets('demo mode: the dropdown still works from the chevron or header',
        (tester) async {
      _size(tester, const Size(1400, 900));
      await _pump(tester, cases: threeFights);
      await tester.tap(find.byKey(const ValueKey('escalated-toggle-24-0001')));
      await tester.pumpAndSettle();
      expect(find.text('Major – Bullying'), findsOneWidget);
    });
  });
}
