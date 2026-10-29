import 'dart:typed_data';

import 'package:dashboard_layout/dashboard_layout.dart'
    show AppPopupPrimaryButton, TitledTableCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/pages/dashboard/violation_reports_view.dart';

ProfessorReportModel _report(
  String id,
  String student, {
  String status = 'Pending',
  bool filedByYou = true,
}) =>
    ProfessorReportModel(
      id: id,
      studentName: student,
      studentNumber: '0200$id',
      section: 'BSIT 2A',
      violationLabel: 'Dress code violation',
      category: 'Minor',
      status: status,
      createdAt: DateTime(2026, 10, 1, 9, 30),
      filedByYou: filedByYou,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  _decisionTests();
  testWidgets('lists pending and resolved reports tied to the professor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [
        _report('1', 'Ana Cruz'),
        _report('2', 'Ben Reyes', status: 'Resolved', filedByYou: false),
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Filed by you'), findsOneWidget);
    expect(find.text('Student self-report'), findsOneWidget);
    // Status is a pill; what still needs the professor is a line under it.
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Awaiting your decision'), findsOneWidget);
  });

  testWidgets('File a Report sits at the far right of the toolbar, after the '
      'search and filter', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [_report('1', 'Ana Cruz')],
      onSearchStudents: (_) async => const [],
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();

    final search = tester.getRect(find.byKey(const Key('reports-search')));
    final filter = tester.getRect(find.text('Filter'));
    final file = tester.getRect(find.byKey(const Key('file-report')));
    final card = tester.getRect(find.byType(TitledTableCard));

    // One row: search, then Filter, then the action — flush with the card's
    // right padding.
    expect((file.center.dy - search.center.dy).abs(), lessThan(8));
    expect(filter.left, greaterThan(search.left));
    expect(file.left, greaterThan(filter.right));
    expect(card.right - file.right, closeTo(25, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the status filter narrows the list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [
        _report('1', 'Ana Cruz'),
        _report('2', 'Ben Reyes', status: 'Resolved'),
      ],
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Under investigation'));
    await tester.pumpAndSettle();
    // Neither report is under investigation.
    expect(find.text('No reports match your search'), findsOneWidget);
  });

  testWidgets('search narrows the list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [_report('1', 'Ana Cruz'), _report('2', 'Ben Reyes')],
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('reports-search')), 'ben');
    await tester.pumpAndSettle();
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsNothing);
  });

  testWidgets('phone: the toolbar fits without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [_report('1', 'Ana Cruz')],
      onSearchStudents: (_) async => const [],
      onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('file-report')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('File a Report is hidden without a submit callback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(const ViolationReportsView(
      reports: [],
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('file-report')), findsNothing);
  });

  _fileReportTests();
}

void _fileReportTests() {
  ReportEvidence photo(String name) => ReportEvidence(
        name: name,
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      );

  const carla = ReportStudentOption(
    id: 's1',
    name: 'Carla Lim',
    studentNumber: '02000123',
    section: 'BSHM 1A',
  );

  Future<void> openForm(
    WidgetTester tester, {
    Future<List<ReportEvidence>> Function()? pickEvidence,
    Future<void> Function(ReportSubmission)? onSubmit,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(ViolationReportsView(
      reports: const [],
      onSearchStudents: (q) async => const [carla],
      pickEvidence: pickEvidence,
      onSubmit: onSubmit ?? (s) async {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file-report')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('report-student-search')), 'carla');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carla Lim'));
    await tester.pumpAndSettle();
  }

  testWidgets('the form has no violation picker or escalate toggle',
      (tester) async {
    await openForm(tester);
    expect(find.byKey(const Key('report-offense-search')), findsNothing);
    expect(find.byKey(const Key('report-escalate')), findsNothing);
    expect(find.byKey(const Key('report-incident-date')), findsOneWidget);
    expect(find.byKey(const Key('report-incident-time')), findsOneWidget);
    expect(find.byKey(const Key('report-description')), findsOneWidget);
  });

  testWidgets('submit stays disabled until the incident is described',
      (tester) async {
    await openForm(tester);
    Finder submit() => find.byKey(const Key('file-report-submit'));
    bool enabled() => tester.widget<AppPopupPrimaryButton>(submit()).onPressed != null;
    expect(enabled(), isFalse);

    await tester.enterText(find.byKey(const Key('report-description')), '   ');
    await tester.pump();
    expect(enabled(), isFalse);

    await tester.enterText(
        find.byKey(const Key('report-description')), 'Vaping behind the gym');
    await tester.pump();
    expect(enabled(), isTrue);
  });

  testWidgets('files the incident time, description and photos',
      (tester) async {
    ReportSubmission? filed;
    await openForm(
      tester,
      pickEvidence: () async => [photo('a.jpg'), photo('b.jpg')],
      onSubmit: (s) async => filed = s,
    );
    final before = DateTime.now();
    await tester.enterText(find.byKey(const Key('report-description')),
        '  Vaping behind the gym  ');
    await tester.tap(find.byKey(const Key('report-add-photos')));
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('b.jpg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-remove-photo-b.jpg')));
    await tester.pumpAndSettle();
    expect(find.text('b.jpg'), findsNothing);

    await tester.tap(find.byKey(const Key('file-report-submit')));
    await tester.pumpAndSettle();

    expect(filed, isNotNull);
    expect(filed!.studentId, 's1');
    expect(filed!.description, 'Vaping behind the gym');
    expect(filed!.evidence.map((e) => e.name), ['a.jpg']);
    expect(filed!.incidentAt.isBefore(before.subtract(const Duration(minutes: 1))),
        isFalse);
    expect(filed!.incidentAt.isAfter(DateTime.now().add(const Duration(minutes: 1))),
        isFalse);
  });

  test('an incident time in the future is invalid', () {
    final now = DateTime(2026, 10, 20, 9, 0);
    expect(validateIncidentAt(DateTime(2026, 10, 20, 9, 30), now: now),
        'Incident time cannot be in the future.');
    expect(validateIncidentAt(DateTime(2026, 10, 20, 8, 59), now: now), isNull);
    expect(validateIncidentAt(now, now: now), isNull);
  });
}

void _decisionTests() {
  testWidgets('the report popup shows status, notes and the decision as pills '
      'and wells', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [
        ProfessorReportModel(
          id: '9',
          studentName: 'Christian Roque',
          studentNumber: '900096',
          section: 'BSIT 2A',
          violationLabel: 'Disruptive classroom behavior',
          category: 'Minor',
          status: 'Resolved',
          createdAt: DateTime(2026, 10, 11, 12, 11),
          filedByYou: false,
          isEscalated: true,
          notes: 'Kept talking during the quiz.',
          professorDecision: 'Confirmed',
          professorDecisionNote: 'I was there.',
        ),
      ],
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Christian Roque'));
    await tester.pumpAndSettle();

    expect(find.text('Violation report'), findsOneWidget);
    // Facts sit beside their labels; status and decision are pills.
    for (final label in ['Violation', 'Category', 'Status', 'Source', 'Filed']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Escalated'), findsWidgets);
    // Longer text gets its own heading and well.
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Kept talking during the quiz.'), findsOneWidget);
    expect(find.text('Your decision'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('I was there.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Violation report'), findsNothing);
  });

  testWidgets('confirms or denies a report that names the professor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final decisions = <(String, bool)>[];
    await tester.pumpWidget(_host(ViolationReportsView(
      reports: [
        _report('1', 'Ana Cruz', filedByYou: false),
        _report('2', 'Ben Reyes'),
      ],
      onDecide: (r, {required confirm, note}) async =>
          decisions.add((r.id, confirm)),
    )));
    await tester.pumpAndSettle();

    // A report the professor filed themselves has nothing to decide.
    await tester.tap(find.text('Ben Reyes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-confirm')), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana Cruz'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-deny')));
    await tester.pumpAndSettle();

    expect(decisions, [('1', false)]);
  });
}
