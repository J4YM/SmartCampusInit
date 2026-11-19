import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const maria = IncidentStudentOption(
      id: 's1', name: 'Maria Santos', studentNumber: '2026-0001', section: 'BSIT-3A');
  const offenses = [
    IncidentOffenseOption(id: 'o1', label: 'Vaping', category: 'Major_A'),
    IncidentOffenseOption(id: 'o2', label: 'Tardiness', category: 'Minor'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required Future<void> Function(IncidentDraft) onSubmit,
    IncidentDraft? prefill,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ManualIncidentView(
            onSubmit: onSubmit,
            onSearchStudents: (q) async =>
                'maria'.contains(q.toLowerCase()) ? [maria] : const [],
            offenses: offenses,
            prefill: prefill,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pickStudentAndOffense(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('incident-student-search')), 'mar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incident-offense')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Vaping').last);
    await tester.pumpAndSettle();
  }

  testWidgets('submit is blocked until student, offense and description are set',
      (tester) async {
    var calls = 0;
    await pump(tester, onSubmit: (_) async => calls++);
    await tester.tap(find.byKey(const Key('incident-submit')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Choose a student.'), findsOneWidget);
    expect(find.text('Choose an offense.'), findsOneWidget);
    expect(find.text('Describe the incident.'), findsOneWidget);
  });

  testWidgets('a complete form submits, and Notify parent is off by default',
      (tester) async {
    IncidentDraft? sent;
    await pump(tester, onSubmit: (d) async => sent = d);
    await pickStudentAndOffense(tester);
    await tester.enterText(
        find.byKey(const Key('incident-description')), 'Found vaping');
    await tester.tap(find.byKey(const Key('incident-submit')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.studentId, 's1');
    expect(sent!.offenseId, 'o1');
    expect(sent!.description, 'Found vaping');
    expect(sent!.occurredAt, isNotNull);
    expect(sent!.notifyParent, isFalse);
  });

  testWidgets('turning Notify parent on is passed through', (tester) async {
    IncidentDraft? sent;
    await pump(tester, onSubmit: (d) async => sent = d);
    await pickStudentAndOffense(tester);
    await tester.enterText(
        find.byKey(const Key('incident-description')), 'Found vaping');
    await tester.tap(find.byKey(const Key('incident-notify')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incident-submit')));
    await tester.pumpAndSettle();
    expect(sent!.notifyParent, isTrue);
  });

  testWidgets('a prefill fills the description and carries the concern id',
      (tester) async {
    IncidentDraft? sent;
    await pump(
      tester,
      onSubmit: (d) async => sent = d,
      prefill: const IncidentDraft(
          description: 'He keeps taking my lunch money', concernId: 'c1'),
    );
    expect(find.text('He keeps taking my lunch money'), findsOneWidget);
    await pickStudentAndOffense(tester);
    await tester.tap(find.byKey(const Key('incident-submit')));
    await tester.pumpAndSettle();
    expect(sent!.concernId, 'c1');
    expect(sent!.description, 'He keeps taking my lunch money');
  });

  testWidgets('a failing submit shows the message and keeps the form',
      (tester) async {
    await pump(tester, onSubmit: (_) async => throw 'Only the Discipline Officer can report an incident.');
    await pickStudentAndOffense(tester);
    await tester.enterText(
        find.byKey(const Key('incident-description')), 'Found vaping');
    await tester.tap(find.byKey(const Key('incident-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only the Discipline Officer'), findsOneWidget);
    expect(find.text('Found vaping'), findsOneWidget);
  });
}
