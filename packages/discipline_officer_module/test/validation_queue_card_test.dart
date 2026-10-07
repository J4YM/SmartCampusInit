import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DisciplineCaseModel makeCase({
    required String id,
    String studentName = 'Jane Doe',
    String? studentNumber,
    String? admissionSlipId,
    String violationType = 'Improper uniform',
    DateTime? at,
  }) {
    return DisciplineCaseModel(
      id: id,
      studentName: studentName,
      // One number per student, as in real data.
      studentNumber: studentNumber ??
          '2024-${studentName.hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}',
      programGradeSection: 'BSIT 3-A',
      violationType: violationType,
      submittedBy: 'System',
      submitterRole: '',
      incidentDateTime: at ?? DateTime(2026, 1, 1),
      description: '',
      admissionSlipId: admissionSlipId,
    );
  }

  Widget buildCard({
    required List<DisciplineCaseModel> cases,
    required ValueChanged<DisciplineCaseModel> onSelect,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 900,
          child: ValidationQueueCard(
            cases: cases,
            selectedCaseId: null,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }

  Future<void> pumpCard(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'violations sharing an admission slip collapse into one student entry',
    (tester) async {
      final cases = [
        makeCase(id: 'v1', studentName: 'Jane Doe', admissionSlipId: 'slip-A'),
        makeCase(id: 'v2', studentName: 'Jane Doe', admissionSlipId: 'slip-A'),
        makeCase(id: 'v3', studentName: 'John Roe'),
      ];

      await pumpCard(tester, buildCard(cases: cases, onSelect: (_) {}));

      // One entry for the 2-violation student, one for the standalone case.
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('John Roe'), findsOneWidget);
      expect(find.textContaining('2 violations'), findsOneWidget);
    },
  );

  testWidgets(
    'the same student on DIFFERENT slips is still one entry, not two',
    (tester) async {
      // Two separate submissions, plus one with no slip at all.
      final cases = [
        makeCase(id: 'v1', studentName: 'Jane Doe', admissionSlipId: 'slip-A'),
        makeCase(id: 'v2', studentName: 'Jane Doe', admissionSlipId: 'slip-B'),
        makeCase(id: 'v3', studentName: 'Jane Doe'),
        makeCase(id: 'v4', studentName: 'John Roe'),
      ];

      await pumpCard(tester, buildCard(cases: cases, onSelect: (_) {}));

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.textContaining('3 violations'), findsOneWidget);
      expect(find.text('John Roe'), findsOneWidget);
    },
  );

  testWidgets(
    'expanding a student reveals each violation as its own selectable row',
    (tester) async {
      DisciplineCaseModel? selected;
      final cases = [
        makeCase(id: 'v1', admissionSlipId: 'slip-A'),
        makeCase(id: 'v2', admissionSlipId: 'slip-A'),
      ];

      await pumpCard(
        tester,
        buildCard(cases: cases, onSelect: (c) => selected = c),
      );

      // Sub-rows aren't shown until expanded.
      expect(find.byKey(const ValueKey('queue-row-v1')), findsNothing);
      expect(find.byKey(const ValueKey('queue-row-v2')), findsNothing);

      await tester.tap(find.textContaining('2 violations'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('queue-row-v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-row-v2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('queue-row-v2')));
      await tester.pumpAndSettle();

      expect(selected?.id, 'v2');
    },
  );

  testWidgets(
    "a dropdown's violations don't repeat the student's own details",
    (tester) async {
      final cases = [
        makeCase(
          id: 'v1',
          studentName: 'Jane Doe',
          studentNumber: '24-0001',
          violationType: 'Minor – Uniform Violation',
        ),
        makeCase(
          id: 'v2',
          studentName: 'Jane Doe',
          studentNumber: '24-0001',
          violationType: 'Major – Vandalism',
        ),
      ];

      await pumpCard(tester, buildCard(cases: cases, onSelect: (_) {}));
      await tester.tap(find.textContaining('2 violations'));
      await tester.pumpAndSettle();

      // The name, section and number appear once — on the dropdown header.
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('24-0001'), findsOneWidget);
      expect(find.text('BSIT 3-A'), findsOneWidget);
      // The nested rows say what was violated instead.
      expect(find.text('Minor – Uniform Violation'), findsOneWidget);
      expect(find.text('Major – Vandalism'), findsOneWidget);
    },
  );

  testWidgets("a dropdown lists the student's newest violation first",
      (tester) async {
    final cases = [
      makeCase(
          id: 'old',
          violationType: 'Minor – Uniform Violation',
          at: DateTime(2026, 1, 1)),
      makeCase(
          id: 'newest',
          violationType: 'Major – Vandalism',
          at: DateTime(2026, 3, 1)),
      makeCase(
          id: 'mid',
          violationType: 'Minor – Late Return of Equipment',
          at: DateTime(2026, 2, 1)),
    ];

    await pumpCard(tester, buildCard(cases: cases, onSelect: (_) {}));
    await tester.tap(find.textContaining('3 violations'));
    await tester.pumpAndSettle();

    double top(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('queue-row-$id'))).dy;
    expect(top('newest'), lessThan(top('mid')));
    expect(top('mid'), lessThan(top('old')));
  });

  testWidgets(
    'a new violation for a student already queued joins their dropdown, on top',
    (tester) async {
      DisciplineCaseModel older(String id) =>
          makeCase(id: id, at: DateTime(2026, 1, 1));
      final first = [older('v1'), older('v2'), makeCase(id: 'x', studentName: 'John Roe')];

      await pumpCard(tester, buildCard(cases: first, onSelect: (_) {}));
      await tester.tap(find.textContaining('2 violations'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-row-v1')), findsOneWidget);

      // A brand-new violation for Jane arrives (a later slip, a later time).
      final withNew = [
        ...first,
        makeCase(
          id: 'v-new',
          admissionSlipId: 'slip-new',
          violationType: 'Major – Vandalism',
          at: DateTime(2026, 6, 1),
        ),
      ];
      await tester.pumpWidget(buildCard(cases: withNew, onSelect: (_) {}));
      await tester.pumpAndSettle();

      // Still ONE Jane Doe, now with 3 violations — no second Jane entry.
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.textContaining('3 violations'), findsOneWidget);
      // The dropdown she had open stays open, and the new one is on top.
      expect(find.byKey(const ValueKey('queue-row-v-new')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('queue-row-v-new'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('queue-row-v1'))).dy),
      );
    },
  );

  testWidgets(
    'a student with one violation is a plain row with their details; tap selects it',
    (tester) async {
      DisciplineCaseModel? selected;
      final cases = [makeCase(id: 'v1', studentName: 'Solo Student')];

      await pumpCard(
        tester,
        buildCard(cases: cases, onSelect: (c) => selected = c),
      );

      expect(find.text('Solo Student'), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-row-v1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('queue-row-v1')));
      await tester.pumpAndSettle();

      expect(selected?.id, 'v1');
    },
  );

  testWidgets(
    'the red violation caption shows for a single violation, not in a dropdown',
    (tester) async {
      // Captions are the generalized violation type in capitals.
      const caption = 'VANDALISM';

      // One violation: the caption heads its row.
      await pumpCard(
        tester,
        buildCard(
          cases: [makeCase(id: 'solo', violationType: 'Major – Vandalism')],
          onSelect: (_) {},
        ),
      );
      expect(find.text(caption), findsOneWidget);

      // Two violations: collapsed, no caption; expanded, none above the rows
      // either — each row already names its violation.
      await tester.pumpWidget(buildCard(
        cases: [
          makeCase(id: 'a', violationType: 'Major – Vandalism'),
          makeCase(id: 'b', violationType: 'Major – Vandalism'),
        ],
        onSelect: (_) {},
      ));
      await tester.pumpAndSettle();
      expect(find.text(caption), findsNothing);

      await tester.tap(find.textContaining('2 violations'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-row-a')), findsOneWidget);
      expect(find.text(caption), findsNothing);
      // The violation is still named once per row.
      expect(find.text('Major – Vandalism'), findsNWidgets(2));
    },
  );

  testWidgets('the header counts students and pending violations',
      (tester) async {
    final cases = [
      makeCase(id: 'v1', studentName: 'Jane Doe'),
      makeCase(id: 'v2', studentName: 'Jane Doe'),
      makeCase(id: 'v3', studentName: 'John Roe'),
    ];
    await pumpCard(tester, buildCard(cases: cases, onSelect: (_) {}));
    expect(find.text('Students: 2 | Pending violations: 3'), findsOneWidget);
  });
  group('View Archived button', () {
    Future<void> pumpWith(WidgetTester tester, {VoidCallback? onViewArchived}) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 900,
            child: ValidationQueueCard(
              cases: [makeCase(id: 'v1')],
              selectedCaseId: null,
              onSelect: (_) {},
              onViewArchived: onViewArchived,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sits between the title and the search bar, full width, as a '
        'secondary button', (tester) async {
      var taps = 0;
      await pumpWith(tester, onViewArchived: () => taps++);

      final button = find.byKey(const Key('view-archived'));
      expect(tester.widget(button), isA<SecondaryPillButton>());

      final card = tester.getRect(find.ancestor(
          of: find.text('Violation Queue'), matching: find.byType(BentoCard)).first);
      final title = tester.getRect(find.text('Violation Queue'));
      final subtitle = tester.getRect(find.textContaining('Students: '));
      final rect = tester.getRect(button);
      final search = tester.getRect(find.byType(TextField));

      // Under the title and its summary line, above the search bar.
      expect(rect.top, greaterThanOrEqualTo(subtitle.bottom));
      expect(rect.top, greaterThan(title.bottom));
      expect(rect.bottom, lessThanOrEqualTo(search.top));
      // Spanning the card's full width (the search row's own 25px inset).
      expect(rect.left, closeTo(card.left + 25, 1));
      expect(rect.right, closeTo(card.right - 25, 1));

      await tester.tap(button);
      expect(taps, 1);
      // The old text link is gone; the label is on the button.
      expect(find.text('View Archived'), findsOneWidget);
    });

    testWidgets('is not shown when there is no archive to view', (tester) async {
      await pumpWith(tester);
      expect(find.byKey(const Key('view-archived')), findsNothing);
      expect(find.text('View Archived'), findsNothing);
    });
  });
}
