import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/parent_intervention_dialog.dart';

void main() {
  group('defaultParentInterventionMessage', () {
    test('count-based message pluralizes', () {
      expect(
        defaultParentInterventionMessage(
          studentName: 'Juan Dela Cruz',
          violationCount: 3,
          hasMajorViolation: false,
        ),
        'Juan Dela Cruz has 3 conduct violations in the last 30 days. '
        'Please visit the Guidance Office to discuss. Thank you.',
      );
      expect(
        defaultParentInterventionMessage(
          studentName: 'Ana Reyes',
          violationCount: 1,
          hasMajorViolation: false,
        ),
        contains('1 conduct violation in'),
      );
    });

    test('major violation uses the major wording', () {
      expect(
        defaultParentInterventionMessage(
          studentName: 'Juan Dela Cruz',
          violationCount: 1,
          hasMajorViolation: true,
        ),
        startsWith('Juan Dela Cruz was reported for a major conduct violation.'),
      );
    });
  });

  group('ParentInterventionDialog', () {
    Future<void Function()> open(
      WidgetTester tester, {
      String? warning,
      required List<String?> results,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await showParentInterventionDialog(
                  context,
                  studentName: 'Juan Dela Cruz',
                  suggestedMessage: 'Suggested text.',
                  smsWarning: warning,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () {};
    }

    testWidgets('is prefilled with the suggestion and sends it unchanged',
        (tester) async {
      final results = <String?>[];
      await open(tester, results: results);

      expect(find.text('Suggested text.'), findsOneWidget);
      expect(find.byKey(const Key('parent-intervention-reset')), findsNothing);

      await tester.tap(find.byKey(const Key('parent-intervention-send')));
      await tester.pumpAndSettle();
      expect(results, ['Suggested text.']);
    });

    testWidgets('an edit overrides the message and can be reset',
        (tester) async {
      final results = <String?>[];
      await open(tester, results: results);

      await tester.enterText(
          find.byKey(const Key('parent-intervention-message')), 'Custom note.');
      await tester.pump();
      expect(find.byKey(const Key('parent-intervention-reset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('parent-intervention-reset')));
      await tester.pump();
      expect(find.text('Suggested text.'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('parent-intervention-message')), 'Custom note.');
      await tester.pump();
      await tester.tap(find.byKey(const Key('parent-intervention-send')));
      await tester.pumpAndSettle();
      expect(results, ['Custom note.']);
    });

    testWidgets('an empty message cannot be sent', (tester) async {
      final results = <String?>[];
      await open(tester, results: results);

      await tester.enterText(
          find.byKey(const Key('parent-intervention-message')), '   ');
      await tester.pump();

      final send = tester.widget<FilledButton>(
          find.byKey(const Key('parent-intervention-send')));
      expect(send.onPressed, isNull);
    });

    testWidgets('cancel resolves to null; warning is shown when given',
        (tester) async {
      final results = <String?>[];
      await open(tester, results: results, warning: 'No guardian number.');

      expect(find.byKey(const Key('parent-intervention-sms-warning')),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });

    testWidgets('long messages report their SMS segment count', (tester) async {
      final results = <String?>[];
      await open(tester, results: results);

      await tester.enterText(
          find.byKey(const Key('parent-intervention-message')), 'x' * 200);
      await tester.pump();
      expect(find.textContaining('2 SMS segments'), findsOneWidget);
    });
  });
}
