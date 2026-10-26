import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConcernReportModel _concern(
  String id,
  String name, {
  String status = 'Pending',
  String urgency = 'Normal',
  String concern = 'emotional',
  DateTime? at,
}) =>
    ConcernReportModel(
      id: id,
      studentName: name,
      studentNumber: 'N-$id',
      aboutStudentName: id == 'a1' ? 'Classmate Cal' : null,
      concern: concern,
      details: 'Details for $name',
      urgency: urgency,
      status: status,
      createdAt: at ?? DateTime(2026, 10, 1, 9),
    );

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget view) async {
  _size(tester, const Size(1400, 900));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: view)),
  ));
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  _concernTabTests();
  _aboutTests();

  final concerns = [
    _concern('c1', 'Closed Cora', status: 'Closed'),
    _concern('n1', 'Normal Nina'),
    _concern('u1', 'Urgent Uma', urgency: 'Urgent'),
  ];

  testWidgets('open concerns come first, urgent before routine',
      (tester) async {
    await _pump(tester, ConcernsView(concerns: concerns));

    final uma = tester.getTopLeft(find.text('Urgent Uma')).dy;
    final nina = tester.getTopLeft(find.text('Normal Nina')).dy;
    final cora = tester.getTopLeft(find.text('Closed Cora')).dy;
    expect(uma, lessThan(nina));
    expect(nina, lessThan(cora));
    expect(find.text('3 concerns | 2 waiting | 1 urgent'), findsOneWidget);
  });

  testWidgets('a row opens the concern, and Save sends the status and note',
      (tester) async {
    ConcernReportModel? saved;
    String? savedStatus;
    String? savedNote;
    await _pump(
      tester,
      ConcernsView(
        concerns: concerns,
        onUpdate: (r, {required status, note}) async {
          saved = r;
          savedStatus = status;
          savedNote = note;
        },
      ),
    );

    await tester.tap(find.text('Normal Nina'));
    await tester.pumpAndSettle();
    expect(find.text('Details for Normal Nina'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'We will call you.');
    await tester.tap(find.byKey(const Key('concern-save')));
    await tester.pumpAndSettle();

    expect(saved?.id, 'n1');
    expect(savedStatus, 'Pending');
    expect(savedNote, 'We will call you.');
  });

  testWidgets('an open concern can be endorsed; a closed one cannot',
      (tester) async {
    ConcernReportModel? endorsed;
    await _pump(
      tester,
      ConcernsView(
        concerns: concerns,
        onEndorse: (r) async => endorsed = r,
      ),
    );

    expect(find.byKey(const Key('endorse-concern-n1')), findsOneWidget);
    expect(find.byKey(const Key('endorse-concern-u1')), findsOneWidget);
    expect(find.byKey(const Key('endorse-concern-c1')), findsNothing);

    await tester.tap(find.byKey(const Key('endorse-concern-u1')));
    await tester.pumpAndSettle();
    expect(endorsed?.id, 'u1');
  });

  testWidgets('a concern already endorsed shows no Endorse action',
      (tester) async {
    await _pump(
      tester,
      ConcernsView(
        concerns: [_concern('n1', 'Normal Nina', status: 'In_Progress')],
        endorsedConcernIds: const {'n1'},
        onEndorse: (r) async {},
      ),
    );

    expect(find.byKey(const Key('endorse-concern-n1')), findsNothing);
    expect(find.text('Endorsed'), findsOneWidget);
  });

  testWidgets('without callbacks the tab is read-only', (tester) async {
    await _pump(tester, ConcernsView(concerns: concerns));
    expect(find.byIcon(Icons.volunteer_activism_outlined), findsNothing,
        reason: 'no Endorse buttons');

    await tester.tap(find.text('Normal Nina'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('concern-save')), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pump(tester, const ConcernsView(concerns: []));
    expect(find.text('No concerns yet'), findsOneWidget);
  });

  testWidgets('the DO dashboard has a Concerns tab, and endorsing a concern '
      'opens the dialog filled in and sends its concern id', (tester) async {
    _size(tester, const Size(1400, 1000));
    EscalationDraft? sent;
    await tester.pumpWidget(MaterialApp(
      home: DisciplineOfficerDashboardPage(
        studentConcerns: [_concern('u1', 'Urgent Uma', urgency: 'Urgent')],
        onIssueEscalation: (d) async => sent = d,
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    await tester.tap(find.text('Concerns'));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.text('Urgent Uma'), findsOneWidget);

    await tester.tap(find.byKey(const Key('endorse-concern-u1')));
    await tester.pumpAndSettle();

    // The reason starts from what the student wrote.
    expect(find.textContaining('Details for Urgent Uma'), findsWidgets);
    await tester.tap(find.byKey(const Key('endorse-confirm')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.concernId, 'u1');
    expect(sent!.studentNumber, 'N-u1');
    expect(sent!.kind, EndorsementKind.counseling);
  });
}

EscalationReportModel _endorsement(String concernId, String status) =>
    EscalationReportModel(
      id: 'e-$concernId',
      studentName: 'Urgent Uma',
      studentNumber: 'N-$concernId',
      title: 'Endorsement',
      summary: 'x',
      message: '',
      channels: const [],
      source: 'officer',
      status: status,
      createdAt: DateTime(2026, 10, 2),
      kind: EndorsementKind.counseling,
      concernId: concernId,
    );

void _concernTabTests() {
  Future<void> openConcerns(WidgetTester tester, String endorsementStatus) async {
    _size(tester, const Size(1400, 1000));
    await tester.pumpWidget(MaterialApp(
      home: DisciplineOfficerDashboardPage(
        studentConcerns: [_concern('u1', 'Urgent Uma', urgency: 'Urgent')],
        escalationReports: [_endorsement('u1', endorsementStatus)],
        onIssueEscalation: (d) async {},
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.text('Concerns'));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  testWidgets('a concern whose endorsement is waiting shows Endorsed',
      (tester) async {
    await openConcerns(tester, 'Pending_GC');
    expect(find.text('Endorsed'), findsOneWidget);
    expect(find.byKey(const Key('endorse-concern-u1')), findsNothing);
  });

  testWidgets('a declined endorsement frees the concern to be endorsed again',
      (tester) async {
    await openConcerns(tester, 'Rejected');
    expect(find.text('Endorsed'), findsNothing);
    expect(find.byKey(const Key('endorse-concern-u1')), findsOneWidget);
  });
}

void _aboutTests() {
  testWidgets('a migrated classmate concern shows who it is about',
      (tester) async {
    _size(tester, const Size(1400, 900));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConcernsView(concerns: [_concern('a1', 'Reporter Rey')]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.text('Reporter Rey'), findsOneWidget);
    expect(find.text('Classmate Cal'), findsOneWidget);
  });
}
