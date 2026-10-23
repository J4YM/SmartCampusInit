import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _case({
  String? status = 'Pending',
  bool classified = true,
  String? category = 'Minor',
  bool suggested = false,
  DateTime? expiredAt,
  List<String> evidence = const [],
  String? handbookPenalty,
}) =>
    DisciplineCaseModel(
      id: 'v1',
      studentName: 'Jane Doe',
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: classified ? 'Smoking' : 'Awaiting classification',
      offenseCategory: classified ? category : null,
      offenseId: classified ? 'o1' : null,
      submittedBy: 'Prof Cruz',
      submitterRole: '',
      incidentDateTime: DateTime(2026, 10, 19, 14, 30),
      filedAt: DateTime(2026, 10, 20, 9, 0),
      description: 'Seen smoking behind the gym',
      status: status,
      isClassified: classified,
      suggestedEscalation: suggested,
      expiredAt: expiredAt,
      evidencePaths: evidence,
      handbookPenalty: handbookPenalty,
    );

Future<void> _pumpPanel(
  WidgetTester tester,
  DisciplineCaseModel c, {
  List<String>? calls,
  Map<String, String>? evidenceUrls,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  void log(String name) => calls?.add(name);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ViolationPreviewPanel(
          selectedCase: c,
          onModify: () => log('modify'),
          onDelete: () => log('delete'),
          onClassify: () => log('classify'),
          onAutoRecord: () => log('auto'),
          onEscalate: () => log('escalate'),
          onSanction: () => log('sanction'),
          evidenceUrls: evidenceUrls ?? const {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('stage-driven actions', () {
    testWidgets('a classified case can still be modified; an unclassified one '
        'must be classified first', (tester) async {
      await _pumpPanel(tester, _case());
      expect(find.text('Modify'), findsOneWidget);
      await _pumpPanel(tester, _case(classified: false));
      expect(find.text('Modify'), findsNothing);
    });

    testWidgets('an unclassified report offers only Classify', (tester) async {
      await _pumpPanel(tester, _case(classified: false));
      expect(find.text('Classify'), findsOneWidget);
      expect(find.text('Auto-record'), findsNothing);
      expect(find.text('Start investigation'), findsNothing);
      expect(find.text('Sanction'), findsNothing);
    });

    testWidgets('a classified Minor offers auto-record, escalate and sanction',
        (tester) async {
      await _pumpPanel(tester, _case());
      expect(find.text('Auto-record'), findsOneWidget);
      expect(find.text('Start investigation'), findsOneWidget);
      expect(find.text('Sanction'), findsOneWidget);
      expect(find.text('Classify'), findsNothing);
    });

    testWidgets('a classified Major hides auto-record', (tester) async {
      await _pumpPanel(tester, _case(category: 'Major_B'));
      expect(find.text('Auto-record'), findsNothing);
      expect(find.text('Start investigation'), findsOneWidget);
      expect(find.text('Sanction'), findsOneWidget);
    });

    testWidgets('with guidance, sanctioning is an override', (tester) async {
      await _pumpPanel(tester, _case(status: 'Under_Investigation'));
      expect(find.text('Sanction'), findsNothing);
      expect(find.text('Sanction before findings'), findsOneWidget);
      expect(find.text('Start investigation'), findsNothing);
      expect(find.textContaining('Under investigation'), findsWidgets);
    });

    testWidgets('after the investigation, Sanction is available',
        (tester) async {
      await _pumpPanel(tester, _case(status: 'Investigation_Complete'));
      expect(find.text('Sanction'), findsOneWidget);
      expect(find.text('Sanction before findings'), findsNothing);
      expect(find.text('Start investigation'), findsNothing);
    });

    testWidgets('a sanctioned case has no workflow actions', (tester) async {
      await _pumpPanel(tester, _case(status: 'Resolved'));
      for (final l in [
        'Classify',
        'Auto-record',
        'Start investigation',
        'Sanction',
        'Sanction before findings'
      ]) {
        expect(find.text(l), findsNothing, reason: l);
      }
    });

    testWidgets('buttons call their callbacks', (tester) async {
      final calls = <String>[];
      await _pumpPanel(tester, _case(), calls: calls);
      await tester.tap(find.text('Auto-record'));
      await tester.tap(find.text('Start investigation'));
      await tester.tap(find.text('Sanction'));
      expect(calls, ['auto', 'escalate', 'sanction']);
    });
  });

  group('case details', () {
    testWidgets('shows when it happened and when it was filed', (tester) async {
      await _pumpPanel(tester, _case());
      expect(find.text('Incident time'), findsOneWidget);
      expect(find.text('Filed'), findsOneWidget);
    });

    testWidgets('flags a suggested escalation and an expired case',
        (tester) async {
      await _pumpPanel(
          tester, _case(suggested: true, expiredAt: DateTime(2026, 10, 23)));
      expect(find.text('Suggested escalation'), findsOneWidget);
      expect(find.text('EXPIRED'), findsOneWidget);
    });

    testWidgets('lists evidence photos', (tester) async {
      await _pumpPanel(tester, _case(evidence: const ['p/a.jpg', 'p/b.jpg']));
      expect(find.text('Photo evidence (2)'), findsOneWidget);
    });
  });

  group('case history', () {
    Future<void> pumpWithHistory(
      WidgetTester tester,
      DisciplineCaseModel c,
      Future<List<ViolationActionEntry>> Function(String id)? load,
    ) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ViolationPreviewPanel(
              selectedCase: c,
              onModify: () {},
              onDelete: () {},
              onLoadHistory: load,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every action with who did it and when', (tester) async {
      String? asked;
      await pumpWithHistory(tester, _case(), (id) async {
        asked = id;
        return [
          ViolationActionEntry(
            action: 'Report filed',
            actorName: 'Prof Cruz',
            actorRole: 'Teacher',
            at: DateTime(2026, 10, 19, 9, 30),
            detail: 'Awaiting classification',
          ),
          ViolationActionEntry(
            action: 'Classified as Smoking',
            actorName: 'Officer Reyes',
            actorRole: 'Discipline_Officer',
            at: DateTime(2026, 10, 20, 8, 5),
          ),
        ];
      });
      expect(asked, 'v1');
      expect(find.text('Case history'), findsOneWidget);
      expect(find.text('Report filed'), findsOneWidget);
      expect(find.text('Classified as Smoking'), findsOneWidget);
      expect(find.textContaining('Prof Cruz (Teacher)'), findsOneWidget);
      expect(find.textContaining('Officer Reyes (Discipline Officer)'),
          findsOneWidget);
      expect(find.text('Awaiting classification'), findsOneWidget);
      expect(
          find.textContaining('Officer Reyes (Discipline Officer) · Oct 20, 2026'),
          findsOneWidget);
    });

    testWidgets('no history section when there is nothing yet', (tester) async {
      await pumpWithHistory(tester, _case(), (id) async => const []);
      expect(find.text('Case history'), findsNothing);
    });

    testWidgets('a failing history load never breaks the panel', (tester) async {
      await pumpWithHistory(tester, _case(), (id) async => throw Exception('x'));
      expect(find.text('Case history'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('the history reloads when the case moves to a new stage',
        (tester) async {
      var loads = 0;
      Future<List<ViolationActionEntry>> load(String id) async {
        loads++;
        return [
          ViolationActionEntry(
              action: 'Step $loads', actorName: 'X', at: DateTime(2026, 10, 20)),
        ];
      }

      await pumpWithHistory(tester, _case(), load);
      expect(loads, 1);
      await pumpWithHistory(tester, _case(status: 'Under_Investigation'), load);
      expect(loads, 2);
      expect(find.text('Step 2'), findsOneWidget);
    });
  });

  group('ClassifyDialog', () {
    const options = [
      OffenseOption(id: 'o1', label: 'Tardiness', category: 'Minor'),
      OffenseOption(id: 'o2', label: 'Smoking', category: 'Major_A'),
    ];

    Future<List<String>?> open(WidgetTester tester) async {
      List<String>? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAppPopup<List<String>>(
              context: context,
              builder: (_) => ClassifyDialog(
                caseItem: _case(classified: false),
                offenseOptions: options,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('save is disabled until an offense is ticked', (tester) async {
      await open(tester);
      bool enabled() => tester
              .widget<AppPopupPrimaryButton>(
                  find.byKey(const Key('classify-save')))
              .onPressed !=
          null;
      expect(enabled(), isFalse);
      await tester.tap(find.text('Smoking'));
      await tester.pump();
      expect(enabled(), isTrue);
    });

    testWidgets('returns every ticked offense id', (tester) async {
      List<String>? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAppPopup<List<String>>(
              context: context,
              builder: (_) => ClassifyDialog(
                caseItem: _case(classified: false),
                offenseOptions: options,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tardiness'));
      await tester.tap(find.text('Smoking'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('classify-save')));
      await tester.pumpAndSettle();
      expect(result, unorderedEquals(['o1', 'o2']));
    });
  });

  group('SanctionDialog', () {
    Future<SanctionFormResult?> run(
      WidgetTester tester,
      DisciplineCaseModel c,
      Future<void> Function(WidgetTester) interact,
    ) async {
      SanctionFormResult? result;
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showAppPopup<SanctionFormResult>(
              context: context,
              builder: (_) => SanctionDialog(caseItem: c),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await interact(tester);
      return result;
    }

    bool saveEnabled(WidgetTester tester) => tester
            .widget<AppPopupPrimaryButton>(find.byKey(const Key('sanction-save')))
            .onPressed !=
        null;

    testWidgets('a handbook penalty prefills the description', (tester) async {
      await run(tester, _case(handbookPenalty: 'Written warning'), (t) async {
        final field = t.widget<TextField>(find.byKey(const Key('sanction-description')));
        expect(field.controller!.text, 'Written warning');
        expect(saveEnabled(t), isTrue);
      });
    });

    testWidgets('submits a handbook-based sanction', (tester) async {
      final result = await run(tester, _case(handbookPenalty: 'Written warning'),
          (t) async {
        await t.tap(find.byKey(const Key('sanction-save')));
        await t.pumpAndSettle();
      });
      expect(result, isNotNull);
      expect(result!.basis, 'handbook');
      expect(result.sanctionType, 'warning');
      expect(result.description, 'Written warning');
      expect(result.affectsEnrollment, isFalse);
      expect(result.overrideReason, isNull);
    });

    testWidgets('editing the text makes it a custom sanction', (tester) async {
      final result = await run(tester, _case(handbookPenalty: 'Written warning'),
          (t) async {
        await t.enterText(find.byKey(const Key('sanction-description')),
            '2-day suspension, counselling required');
        await t.pump();
        await t.tap(find.byKey(const Key('sanction-save')));
        await t.pumpAndSettle();
      });
      expect(result!.basis, 'custom');
      expect(result.description, '2-day suspension, counselling required');
    });

    testWidgets('non-readmission needs an explicit confirmation',
        (tester) async {
      final result = await run(tester, _case(), (t) async {
        await t.tap(find.byType(DropdownButtonFormField<String>));
        await t.pumpAndSettle();
        await t.tap(find.text('Non-readmission').last);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('sanction-description')),
            'Not to be readmitted next term');
        await t.pump();
        expect(find.textContaining('block re-enrollment'), findsOneWidget);
        expect(saveEnabled(t), isFalse);

        await t.tap(find.byKey(const Key('sanction-confirm-enrollment')));
        await t.pump();
        expect(saveEnabled(t), isTrue);
        await t.tap(find.byKey(const Key('sanction-save')));
        await t.pumpAndSettle();
      });
      expect(result!.sanctionType, 'non_readmission');
      expect(result.affectsEnrollment, isTrue);
    });

    testWidgets('an early sanction on a case with Guidance needs a reason',
        (tester) async {
      final result = await run(
          tester, _case(status: 'Under_Investigation', handbookPenalty: 'Warning'),
          (t) async {
        expect(find.byKey(const Key('sanction-override-reason')), findsOneWidget);
        expect(saveEnabled(t), isFalse);
        await t.enterText(
            find.byKey(const Key('sanction-override-reason')), '   ');
        await t.pump();
        expect(saveEnabled(t), isFalse);
        await t.enterText(find.byKey(const Key('sanction-override-reason')),
            'Student is graduating this week');
        await t.pump();
        expect(saveEnabled(t), isTrue);
        await t.tap(find.byKey(const Key('sanction-save')));
        await t.pumpAndSettle();
      });
      expect(result!.overrideReason, 'Student is graduating this week');
    });

    testWidgets('no override field when the case is not with Guidance',
        (tester) async {
      await run(tester, _case(), (t) async {
        expect(find.byKey(const Key('sanction-override-reason')), findsNothing);
      });
    });
  });
}
