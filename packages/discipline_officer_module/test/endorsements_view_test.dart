import 'package:dashboard_layout/dashboard_layout.dart'
    show AppPopupCheckboxTile, BentoCard;
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case(String id, String number, {String type = 'Major – Fighting'}) =>
    DisciplineCaseModel(
      id: id,
      studentName: 'S $number',
      studentNumber: number,
      programGradeSection: 'BSIT-3A',
      violationType: type,
      submittedBy: 'Guard',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 1, 1, 9),
      description: '',
    );

StudentDirectoryEntryModel _student(String number, String name) =>
    StudentDirectoryEntryModel(
      id: 'id-$number',
      studentName: name,
      studentNumber: number,
      programGradeSection: 'BSIT-3A',
    );

EscalationReportModel _report(
  String id, {
  String number = '24-0001',
  String status = 'Pending_GC',
  EndorsementKind kind = EndorsementKind.counseling,
}) =>
    EscalationReportModel(
      id: id,
      studentName: 'Jane Doe',
      studentNumber: number,
      title: 'Endorsement',
      summary: 'Seems withdrawn.',
      message: '',
      channels: const [],
      source: 'officer',
      status: status,
      createdAt: DateTime(2026, 2, 1, 10),
      kind: kind,
    );

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Records what the tab asked the host for.
class _Loader {
  _Loader(this.students);

  final List<StudentDirectoryEntryModel> students;
  final calls = <({int page, String query})>[];

  Future<EndorsementStudentPage> call({required int page, String query = ''}) async {
    calls.add((page: page, query: query));
    final q = query.toLowerCase();
    final hit = [
      for (final s in students)
        if (q.isEmpty ||
            s.studentName.toLowerCase().contains(q) ||
            s.studentNumber.contains(q))
          s,
    ];
    return (items: hit, totalCount: hit.length);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _Loader loader,
  List<DisciplineCaseModel> cases = const [],
  List<EscalationReportModel> reports = const [],
  Future<void> Function(EscalationDraft)? onIssue,
}) async {
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: SizedBox(
        height: 900,
        child: SingleChildScrollView(
          child: EndorsementsView(
            reports: reports,
            cases: cases,
            loadStudents: loader.call,
            onIssue: onIssue,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  tester.takeException(); // Ahem-width test fonts may overflow a label
}

Finder _card(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(BentoCard),
    );

void main() {
  _otherKindTests();
  final loader = () => _Loader([
        _student('24-0001', 'Ana Cruz'),
        _student('24-0002', 'Ben Reyes'),
      ]);

  testWidgets('lists every student, including one with no violations',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        loader: loader(),
        cases: [_case('a', '24-0001')],
        onIssue: (_) async {});

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('None'), findsOneWidget, reason: 'Ben has no violations');
    expect(find.byKey(const Key('endorse-24-0002')), findsOneWidget,
        reason: 'a student without violations can be endorsed');
  });

  testWidgets('wide: students and endorsements share one row', (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, loader: loader(), reports: [_report('r1')]);

    final students = tester.getRect(_card('Students').first);
    final reports = tester.getRect(_card('Endorsements').first);
    expect(reports.left, greaterThan(students.right - 1));
    expect(reports.width, 320);
    expect(reports.top, students.top);
  });

  testWidgets('narrow: the cards stack, students first', (tester) async {
    _size(tester, const Size(700, 1800));
    await _pump(tester, loader: loader(), reports: [_report('r1')]);
    final students = tester.getRect(_card('Students').first);
    final reports = tester.getRect(_card('Endorsements').first);
    expect(reports.top, greaterThanOrEqualTo(students.bottom));
  });

  testWidgets('typing in the search asks the host for that query',
      (tester) async {
    _size(tester, const Size(1400, 900));
    final l = loader();
    await _pump(tester, loader: l);
    expect(l.calls.single, (page: 1, query: ''));

    await tester.enterText(
        find.byKey(const Key('endorsement-student-search')), 'ben');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(l.calls.last, (page: 1, query: 'ben'));
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsNothing);
  });

  testWidgets('a student shows their latest endorsement status', (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        loader: loader(), reports: [_report('r1', status: 'Approved')]);

    expect(find.text('Not endorsed'), findsOneWidget);
    expect(find.text('Approved'), findsWidgets);
  });

  testWidgets('counseling needs only a reason: no message or channels',
      (tester) async {
    _size(tester, const Size(1400, 900));
    EscalationDraft? sent;
    await _pump(tester,
        loader: loader(), onIssue: (d) async => sent = d);

    await tester.tap(find.byKey(const Key('endorse-24-0002')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('endorsement-message')), findsNothing);
    expect(find.byKey(const Key('endorsement-sms')), findsNothing);
    FilledButton confirm() => tester.widget<FilledButton>(find.descendant(
        of: find.byKey(const Key('endorse-confirm')),
        matching: find.byType(FilledButton)));
    expect(confirm().onPressed, isNull, reason: 'a reason is required');

    await tester.enterText(
        find.byKey(const Key('endorsement-reason')), 'Seems withdrawn.');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('endorse-confirm')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.studentNumber, '24-0002');
    expect(sent!.kind, EndorsementKind.counseling);
    expect(sent!.violationIds, isEmpty);
    expect(sent!.channels, isEmpty);
    expect(sent!.message, isEmpty);
  });

  testWidgets('a parent intervention adds the message and channels',
      (tester) async {
    _size(tester, const Size(1400, 900));
    EscalationDraft? sent;
    await _pump(tester,
        loader: loader(),
        cases: [_case('a', '24-0001'), _case('b', '24-0001', type: 'Minor – Late')],
        onIssue: (d) async => sent = d);

    await tester.tap(find.byKey(const Key('endorse-24-0001')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('endorsement-kind-parent_intervention')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('endorsement-message')), findsOneWidget);
    expect(find.byKey(const Key('endorsement-sms')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('endorsement-reason')), 'Repeated concerns.');
    await tester.tap(find.byKey(const ValueKey('endorsement-violation-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('endorse-confirm')));
    await tester.pumpAndSettle();

    expect(sent!.kind, EndorsementKind.parentIntervention);
    expect(sent!.violationIds, ['a']);
    expect(sent!.channels, ['sms']);
    expect(sent!.message, isNotEmpty);
  });

  testWidgets('violations are offered only to a student who has some',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester,
        loader: loader(),
        cases: [_case('a', '24-0001')],
        onIssue: (_) async {});

    await tester.tap(find.byKey(const Key('endorse-24-0002')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('endorsement-violation-a')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('endorse-24-0001')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('endorsement-violation-a')), findsOneWidget);
  });

  testWidgets('each endorsement tile shows what Guidance was asked for',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, loader: loader(), reports: [
      _report('r1', kind: EndorsementKind.both),
    ]);

    final text = tester
        .widget<Text>(find.byKey(const ValueKey('report-kind-r1')))
        .data!;
    expect(text, contains('Counseling and parent intervention'));
  });

  testWidgets('demo mode (no onIssue) hides every Endorse button',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await _pump(tester, loader: loader());

    expect(find.byIcon(kIssueEscalationIcon), findsNothing);
    expect(find.text('Ana Cruz'), findsOneWidget);
  });

  testWidgets('a failing student load says so', (tester) async {
    _size(tester, const Size(1400, 900));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 900,
          child: SingleChildScrollView(
            child: EndorsementsView(
              reports: const [],
              cases: const [],
              loadStudents: ({required page, query = ''}) async =>
                  throw StateError('offline'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.textContaining('Could not load students'), findsOneWidget);
  });
}

void _otherKindTests() {
  final loader = () => _Loader([
        _student('24-0001', 'Ana Cruz'),
        _student('24-0002', 'Ben Reyes'),
      ]);

  FilledButton confirm(WidgetTester tester) =>
      tester.widget<FilledButton>(find.descendant(
          of: find.byKey(const Key('endorse-confirm')),
          matching: find.byType(FilledButton)));

  testWidgets('Other asks to describe the intervention and keeps the parent '
      'out by default', (tester) async {
    _size(tester, const Size(1400, 900));
    EscalationDraft? sent;
    await _pump(tester, loader: loader(), onIssue: (d) async => sent = d);

    await tester.tap(find.byKey(const Key('endorse-24-0002')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('endorsement-kind-other')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('endorsement-message')), findsNothing,
        reason: 'Other never messages the parent');
    expect(find.byKey(const Key('endorsement-other-description')),
        findsOneWidget);
    final exclude = tester.widget<AppPopupCheckboxTile>(
        find.byKey(const Key('endorsement-exclude-parent')));
    expect(exclude.value, isTrue, reason: 'checked by default for Other');

    await tester.enterText(
        find.byKey(const Key('endorsement-reason')), 'Needs a mediator.');
    await tester.pump();
    expect(confirm(tester).onPressed, isNull,
        reason: 'the description is required');

    await tester.enterText(
        find.byKey(const Key('endorsement-other-description')),
        '  Peer mediation  ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('endorse-confirm')));
    await tester.pumpAndSettle();

    expect(sent!.kind, EndorsementKind.other);
    expect(sent!.otherDescription, 'Peer mediation');
    expect(sent!.excludeParent, isTrue);
    expect(sent!.channels, isEmpty);
    expect(sent!.message, isEmpty);
  });

  testWidgets('Counseling offers Exclude the parent, unchecked; a parent '
      'intervention does not', (tester) async {
    _size(tester, const Size(1400, 900));
    EscalationDraft? sent;
    await _pump(tester, loader: loader(), onIssue: (d) async => sent = d);

    await tester.tap(find.byKey(const Key('endorse-24-0002')));
    await tester.pumpAndSettle();

    final exclude = find.byKey(const Key('endorsement-exclude-parent'));
    expect(tester.widget<AppPopupCheckboxTile>(exclude).value, isFalse);
    expect(find.byKey(const Key('endorsement-other-description')), findsNothing);

    await tester.tap(exclude);
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('endorsement-reason')), 'Seems withdrawn.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('endorse-confirm')));
    await tester.pumpAndSettle();
    expect(sent!.excludeParent, isTrue);
    expect(sent!.otherDescription, isNull);

    await tester.tap(find.byKey(const Key('endorse-24-0001')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('endorsement-kind-parent_intervention')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('endorsement-exclude-parent')), findsNothing);
  });
}
