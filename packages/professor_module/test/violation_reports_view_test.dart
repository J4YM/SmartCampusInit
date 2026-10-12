import 'package:dashboard_layout/dashboard_layout.dart' show TitledTableCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/pages/dashboard/conduct_report_view.dart'
    show ConductViolationOption;
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
      offenseOptions: const [],
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
      offenseOptions: const [],
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
      offenseOptions: const [],
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
      offenseOptions: const [],
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
      offenseOptions: const [],
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
      offenseOptions: [],
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('file-report')), findsNothing);
  });

  testWidgets('files a report for any searched student and any violations',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    ReportSubmission? filed;
    await tester.pumpWidget(_host(ViolationReportsView(
      reports: const [],
      offenseOptions: const [
        ConductViolationOption(id: 'o1', label: 'Tardiness', category: 'Minor'),
        ConductViolationOption(id: 'o2', label: 'Cheating', category: 'Major'),
      ],
      onSearchStudents: (q) async => const [
        ReportStudentOption(
          id: 's1',
          name: 'Carla Lim',
          studentNumber: '02000123',
          section: 'BSHM 1A',
        ),
      ],
      onSubmit: (s) async => filed = s,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file-report')));
    await tester.pumpAndSettle();

    // Submit stays disabled until a student and a violation are chosen.
    await tester.enterText(
        find.byKey(const Key('report-student-search')), 'carla');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carla Lim'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tardiness'));
    await tester.tap(find.text('Cheating'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file-report-submit')));
    await tester.pumpAndSettle();

    expect(filed, isNotNull);
    expect(filed!.studentId, 's1');
    expect(filed!.offenseIds, unorderedEquals(['o1', 'o2']));
    expect(filed!.escalateNow, isFalse);
  });
}

void _decisionTests() {
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
      offenseOptions: const [],
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
