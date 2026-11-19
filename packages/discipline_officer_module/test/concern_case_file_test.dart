import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConcernReportModel _concern(
  String id, {
  String status = 'Pending',
  String? violationId,
}) =>
    ConcernReportModel(
      id: id,
      studentName: 'Student $id',
      studentNumber: 'N-$id',
      concern: 'bullying',
      details: 'Details for $id',
      urgency: 'Normal',
      status: status,
      createdAt: DateTime(2026, 10, 1, 9),
      violationId: violationId,
    );

final _file = ConcernCaseFile(
  endorsements: [
    CaseEndorsement(
      id: 'e1',
      status: 'Approved',
      decisionNote: 'Please attend',
      summary: 'Seems withdrawn',
      decidedAt: DateTime(2026, 10, 3),
      meetings: [
        CaseMeeting(
          id: 'm1',
          scheduledAt: DateTime(2026, 10, 5, 9),
          status: 'Completed',
          responseNote: 'We will attend',
          location: 'Guidance Office',
        ),
      ],
    ),
  ],
  investigation: CaseInvestigation(
    id: 'i1',
    status: 'Complete',
    findings: 'Student admitted taking the money',
    recommendation: 'Return the money and apologise',
    completedAt: DateTime(2026, 10, 8),
    sanctionType: 'Warning',
    sanctionDescription: 'Written warning',
  ),
);

Future<void> _pump(WidgetTester tester, Widget view) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: view)),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  test('ConcernCaseFile.fromJson reads endorsements, meetings and findings', () {
    final f = ConcernCaseFile.fromJson({
      'endorsements': [
        {
          'id': 'e1',
          'status': 'Approved',
          'decision_note': 'Please attend',
          'summary': 'Seems withdrawn',
          'decided_at': '2026-10-03T00:00:00Z',
          'meetings': [
            {
              'id': 'm1',
              'scheduled_at': '2026-10-05T01:00:00Z',
              'status': 'Completed',
              'response_note': 'We will attend',
              'location': 'Guidance Office',
            },
          ],
        },
      ],
      'investigation': {
        'id': 'i1',
        'status': 'Complete',
        'findings': 'Admitted',
        'recommendation': 'Apologise',
        'completed_at': '2026-10-08T00:00:00Z',
        'sanction': {'type': 'warning', 'description': 'Written warning'},
      },
    });
    expect(f.endorsements.single.meetings.single.responseNote, 'We will attend');
    expect(f.investigation!.findings, 'Admitted');
    expect(f.investigation!.sanctionDescription, 'Written warning');
    expect(ConcernCaseFile.fromJson({'endorsements': [], 'investigation': null})
        .investigation, isNull);
  });

  testWidgets('an open concern offers Endorse and Send to investigation',
      (tester) async {
    ConcernReportModel? sent;
    await _pump(
      tester,
      ConcernsView(
        concerns: [_concern('c1')],
        onEndorse: (_) async {},
        onSendToInvestigation: (c) async => sent = c,
      ),
    );
    expect(find.byKey(const Key('endorse-concern-c1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-to-investigation-c1')));
    await tester.pumpAndSettle();
    expect(sent?.id, 'c1');
  });

  testWidgets('a concern under investigation shows it and cannot be sent again',
      (tester) async {
    await _pump(
      tester,
      ConcernsView(
        concerns: [_concern('c1', status: 'In_Progress', violationId: 'v1')],
        onEndorse: (_) async {},
        onSendToInvestigation: (_) async {},
      ),
    );
    expect(find.text('Under investigation'), findsOneWidget);
    expect(find.byKey(const Key('send-to-investigation-c1')), findsNothing);
  });

  testWidgets('a closed concern has no action icons but can still be opened',
      (tester) async {
    await _pump(
      tester,
      ConcernsView(
        concerns: [_concern('c1', status: 'Closed')],
        onEndorse: (_) async {},
        onSendToInvestigation: (_) async {},
        onUpdate: (r, {required status, note}) async {},
      ),
    );
    expect(find.byKey(const Key('endorse-concern-c1')), findsNothing);
    expect(find.byKey(const Key('send-to-investigation-c1')), findsNothing);
    expect(find.byKey(const Key('manage-concern-c1')), findsOneWidget);
  });

  testWidgets(
      'an endorsed concern keeps the status picker and shows the returned '
      'findings when opened', (tester) async {
    String? savedStatus;
    await _pump(
      tester,
      ConcernsView(
        concerns: [_concern('c1', status: 'In_Progress')],
        endorsedConcernIds: const {'c1'},
        onEndorse: (_) async {},
        onUpdate: (r, {required status, note}) async => savedStatus = status,
        loadCaseFile: (_) async => _file,
      ),
    );
    expect(find.text('Endorsed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('manage-concern-c1')));
    await tester.pumpAndSettle();

    expect(find.text('Please attend'), findsOneWidget);
    expect(find.textContaining('We will attend'), findsOneWidget);
    expect(find.text('Student admitted taking the money'), findsOneWidget);
    expect(find.text('Return the money and apologise'), findsOneWidget);
    expect(find.textContaining('Written warning'), findsWidgets);

    // The picker is usable: close the concern.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('concern-save')));
    await tester.pumpAndSettle();
    expect(savedStatus, 'Closed');
  });

  testWidgets('a case file that fails to load says so and keeps the picker',
      (tester) async {
    await _pump(
      tester,
      ConcernsView(
        concerns: [_concern('c1')],
        onUpdate: (r, {required status, note}) async {},
        loadCaseFile: (_) async => throw 'boom',
      ),
    );
    await tester.tap(find.byKey(const Key('manage-concern-c1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load the case file'), findsOneWidget);
    expect(find.byKey(const Key('concern-save')), findsOneWidget);
  });

  testWidgets(
      'on the dashboard, Send to investigation opens the incident form filled '
      'from the concern and sends the officer-picked student with the concern id',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    IncidentDraft? sent;
    await tester.pumpWidget(MaterialApp(
      home: DisciplineOfficerDashboardPage(
        studentConcerns: [_concern('c1')],
        onSendConcernToInvestigation: (d) async => sent = d,
        onSearchIncidentStudents: (q) async => const [
          IncidentStudentOption(
              id: 's2', name: 'Carl Cruz', studentNumber: '2026-0002'),
        ],
        availableOffenses: const [
          OffenseOption(id: 'o1', label: 'Bullying', category: 'Major_A'),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.text('Concerns'));
    await tester.pumpAndSettle();
    tester.takeException();

    await tester.tap(find.byKey(const Key('send-to-investigation-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Details for c1'), findsWidgets,
        reason: 'the description starts from what the student wrote');

    await tester.enterText(
        find.byKey(const Key('incident-student-search')), 'car');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carl Cruz'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incident-offense')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bullying').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incident-submit')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.concernId, 'c1');
    expect(sent!.studentId, 's2');
    expect(sent!.offenseId, 'o1');
    expect(sent!.notifyParent, isFalse);
  });
}
