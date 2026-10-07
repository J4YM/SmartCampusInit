import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:dashboard_layout/dashboard_layout.dart' show BentoCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case(
  String id, {
  String name = 'Jane Doe',
  String number = '24-0001',
  String section = 'BSIT-3A',
  String type = 'Minor – Uniform Violation',
  String by = 'Guard J. De Leon',
  String? status,
  DateTime? at,
  String? slip,
}) =>
    DisciplineCaseModel(
      id: id,
      studentName: name,
      studentNumber: number,
      programGradeSection: section,
      violationType: type,
      submittedBy: by,
      submitterRole: '',
      incidentDateTime: at ?? DateTime(2026, 1, 1, 9),
      description: '',
      status: status,
      admissionSlipId: slip,
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('groupCasesByStudent', () {
    test('one group per student, whatever slips their violations came on', () {
      final groups = groupCasesByStudent([
        _case('a1', slip: 'slip-A'),
        _case('b1', name: 'John Roe', number: '24-0002'),
        _case('a2', slip: 'slip-B'),
        _case('a3'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.map((g) => g.studentKey), ['24-0001', '24-0002']);
      expect(groups.first.cases.map((c) => c.id), containsAll(['a1', 'a2', 'a3']));
    });

    test("each group's violations run newest first", () {
      final group = groupCasesByStudent([
        _case('old', at: DateTime(2026, 1, 1)),
        _case('new', at: DateTime(2026, 5, 1)),
        _case('mid', at: DateTime(2026, 3, 1)),
      ]).single;

      expect(group.cases.map((c) => c.id), ['new', 'mid', 'old']);
      expect(group.primaryCase.id, 'new');
    });

    test('equal times keep their incoming order', () {
      final at = DateTime(2026, 1, 1);
      final group = groupCasesByStudent([
        _case('1', at: at),
        _case('2', at: at),
        _case('3', at: at),
      ]).single;
      expect(group.cases.map((c) => c.id), ['1', '2', '3']);
    });

    test('students keep the order they first appear in', () {
      final groups = groupCasesByStudent([
        _case('x1', name: 'Zed', number: '24-0009'),
        _case('a1', name: 'Amy', number: '24-0001'),
        _case('x2', name: 'Zed', number: '24-0009'),
      ]);
      expect(groups.map((g) => g.primaryCase.studentName), ['Zed', 'Amy']);
    });

    test('a case without a student number is matched on its name', () {
      final groups = groupCasesByStudent([
        _case('1', name: 'Jane Doe', number: ''),
        _case('2', name: 'JANE DOE ', number: ''),
        _case('3', name: 'John Roe', number: ''),
      ]);
      expect(groups, hasLength(2));
    });
  });

  group('Students Violation History', () {
    // Jane has THREE violations (one pending, one under investigation, one
    // resolved), John one resolved, Ana one under investigation.
    final history = [
      _case('j-new', status: 'Pending', type: 'Major – Vandalism',
          at: DateTime(2026, 5, 3, 14, 5)),
      _case('j-mid', status: 'Under_Investigation',
          type: 'Minor – Late Return of Equipment',
          at: DateTime(2026, 3, 10, 9)),
      _case('j-old', status: 'Resolved', type: 'Minor – Uniform Violation',
          at: DateTime(2026, 1, 5, 8)),
      _case('r', name: 'John Roe', number: '24-0002', section: 'BSBA-2A',
          type: 'Major – Academic Dishonesty', status: 'Resolved',
          at: DateTime(2026, 4, 1, 9)),
      _case('u', name: 'Ana Cruz', number: '24-0003', section: 'BSHM-1A',
          type: 'Minor – Unauthorized Use of Mobile Phone',
          status: 'Under_Investigation', at: DateTime(2026, 6, 1, 8)),
    ];

    Future<void> pump(WidgetTester tester, List<DisciplineCaseModel> cases) async {
      _size(tester, const Size(1400, 1400));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ViolationHistoryView(cases: cases)),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();
    }

    testWidgets('one row per student, however many violations they have',
        (tester) async {
      await pump(tester, history);

      expect(find.text('Students Violation History'), findsOneWidget);
      expect(find.text('3 students | 5 violations on record'), findsOneWidget);
      // Jane has three violations but ONE row.
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('John Roe'), findsOneWidget);
      expect(find.text('Ana Cruz'), findsOneWidget);
      // Her row carries the count (3) and how many are still open (2).
      expect(find.text('3'), findsOneWidget);
      // Each row shows the student's LATEST violation, not all of them.
      expect(find.text('Major – Vandalism'), findsOneWidget);
      expect(find.text('Minor – Uniform Violation'), findsNothing);
      expect(find.text('2026-05-03 2:05 PM'), findsOneWidget);
    });

    testWidgets('students are ordered by their latest violation, newest first',
        (tester) async {
      await pump(tester, history);
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(top('Ana Cruz'), lessThan(top('Jane Doe'))); // Jun 1 vs May 3
      expect(top('Jane Doe'), lessThan(top('John Roe'))); // May 3 vs Apr 1
    });

    testWidgets("clicking a student opens a popup of THEIR violations, newest first",
        (tester) async {
      await pump(tester, history);

      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      // The popup: her details and all three violations.
      expect(find.text('Violation History'), findsOneWidget);
      expect(find.text('3 violations'), findsOneWidget);
      expect(find.text('2 open'), findsOneWidget);
      for (final id in ['j-new', 'j-mid', 'j-old']) {
        expect(find.byKey(ValueKey('student-history-case-$id')), findsOneWidget,
            reason: id);
      }
      // Another student's violation is not in the popup (it is still in the
      // table behind it).
      expect(
        find.descendant(
          of: find.byType(StudentViolationHistorySheet),
          matching: find.text('Major – Academic Dishonesty'),
        ),
        findsNothing,
      );

      double top(String id) => tester
          .getTopLeft(find.byKey(ValueKey('student-history-case-$id')))
          .dy;
      expect(top('j-new'), lessThan(top('j-mid')));
      expect(top('j-mid'), lessThan(top('j-old')));

      // Each shows its status; the severity and filer are there too.
      expect(find.text('Under Investigation'), findsWidgets);
      expect(find.text('Resolved'), findsWidgets);
      expect(find.text('Major'), findsOneWidget);
      expect(find.text('2026-01-05 8:00 AM'), findsOneWidget);
      expect(find.text('Filed by Guard J. De Leon'), findsNWidgets(3));

      // Closing it returns to the table.
      await tester.tap(find.byKey(const Key('popup-close')));
      await tester.pumpAndSettle();
      expect(find.text('Violation History'), findsNothing);
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('the popup lists the whole history even when a filter is on',
        (tester) async {
      await pump(tester, history);

      await tester.enterText(
          find.byKey(const Key('violation-history-search')), 'vandalism');
      await tester.pumpAndSettle();
      // Only Jane has a matching violation.
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('John Roe'), findsNothing);

      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();
      // ...but her popup still shows all three, not just the matching one.
      expect(find.byKey(const ValueKey('student-history-case-j-old')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('student-history-case-j-mid')),
          findsOneWidget);
    });

    testWidgets('search narrows students by name, violation or status',
        (tester) async {
      await pump(tester, history);

      await tester.enterText(
          find.byKey(const Key('violation-history-search')), 'academic');
      await tester.pumpAndSettle();
      expect(find.text('John Roe'), findsOneWidget);
      expect(find.text('Jane Doe'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('violation-history-search')), 'ana');
      await tester.pumpAndSettle();
      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('John Roe'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('violation-history-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No students match your search'), findsOneWidget);
    });

    testWidgets('an empty record says so', (tester) async {
      await pump(tester, const []);
      expect(find.text('No violations on record'), findsOneWidget);
    });

    testWidgets('pages hold 5 students on a phone, 10 on a wide screen',
        (tester) async {
      final many = [
        for (var i = 1; i <= 12; i++)
          _case('c$i',
              name: 'Student ${i.toString().padLeft(2, '0')}',
              number: '24-${i.toString().padLeft(4, '0')}',
              at: DateTime(2026, 1, i)),
      ];

      Future<void> pumpAt(Size size) async {
        _size(tester, size);
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: SingleChildScrollView(child: ViolationHistoryView(cases: many)),
          ),
        ));
        await tester.pumpAndSettle();
        tester.takeException();
      }

      await pumpAt(const Size(390, 2400));
      expect(find.textContaining('Student '), findsNWidgets(5));
      await pumpAt(const Size(1400, 2400));
      expect(find.textContaining('Student '), findsNWidgets(10));
    });

    testWidgets('the popup follows the dark theme', (tester) async {
      _size(tester, const Size(1400, 1400));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(child: ViolationHistoryView(cases: history)),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      final sheet = find.byType(StudentViolationHistorySheet);
      expect(sheet, findsOneWidget);
      // The dark card color, not the light one, behind the popup's content.
      final card = tester.widget<BentoCard>(find
          .descendant(of: find.byType(Dialog), matching: find.byType(BentoCard))
          .first);
      expect(card.backgroundColor, const Color(0xFF191A1F));
    });

    testWidgets('on a phone the popup is a bottom sheet that fits without '
        'overflow', (tester) async {
      _size(tester, const Size(390, 800));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ViolationHistoryView(cases: history)),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();

      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'layout overflow');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      // Its content is scrollable: the third violation is reachable.
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('student-history-case-j-old')),
          findsOneWidget);
    });

    testWidgets('the dashboard has the tab, and resolving a violation marks it '
        'resolved there', (tester) async {
      _size(tester, const Size(1400, 1000));
      final pending = _case('p', status: 'Pending', at: DateTime(2026, 5, 3, 14, 5));
      await tester.pumpWidget(MaterialApp(
        home: DisciplineOfficerDashboardPage(
          initialPendingQueue: [pending],
          initialViolationHistory: [pending],
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();

      expect(find.text('Students Violation History'), findsOneWidget); // the tab

      // Resolve the pending violation from the queue.
      await tester.tap(find.byKey(const ValueKey('queue-row-p')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validate').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Students Violation History'));
      await tester.pumpAndSettle();
      tester.takeException();

      // Her one row remains; opening it shows the violation as resolved.
      expect(find.text('Jane Doe'), findsOneWidget);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
    });
  });

  testWidgets('the Good Moral Student List holds 5 rows on a phone',
      (tester) async {
    _size(tester, const Size(390, 2400));
    final rows = [
      for (var i = 1; i <= 12; i++)
        GoodMoralQueueRowData(
          id: '$i',
          name: 'Pupil ${i.toString().padLeft(2, '0')}',
          section: 'BSIT-1A',
          number: '24-${i.toString().padLeft(4, '0')}',
        ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoodMoralQueueCard(
            title: 'Student List',
            totalCountLabel: '12 students',
            rows: rows,
            selectedId: null,
            onSelect: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    expect(find.textContaining('Pupil '), findsNWidgets(5));
  });
}
