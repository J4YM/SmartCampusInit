import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';

void main() {
  const buttonKey = Key('request-parent-intervention');

  Future<void> pump(
    WidgetTester tester, {
    Future<void> Function(BuildContext, String)? onRequest,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SingleStudentAnalysisView(onRequestParentIntervention: onRequest),
        ),
      ),
    ));
  }

  Future<void> analyze(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Analyze Risk'));
    await tester.tap(find.text('Analyze Risk'));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  testWidgets('hidden entirely when no callback is wired (demo mode)',
      (tester) async {
    await pump(tester);
    await analyze(tester);
    expect(find.byKey(buttonKey), findsNothing);
  });

  testWidgets('disabled until an analysis exists, then enabled',
      (tester) async {
    await pump(tester, onRequest: (_, __) async {});
    expect(
      tester.widget<OutlinedButton>(find.byKey(buttonKey)).onPressed,
      isNull,
    );

    await analyze(tester);
    expect(
      tester.widget<OutlinedButton>(find.byKey(buttonKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('tapping passes the typed Student ID to the callback',
      (tester) async {
    final calls = <String>[];
    await pump(tester, onRequest: (_, id) async => calls.add(id));

    await tester.enterText(find.byType(TextField).first, '2024-00123');
    await analyze(tester);
    await tester.ensureVisible(find.byKey(buttonKey));
    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();

    expect(calls, ['2024-00123']);
  });

  testWidgets('a failing request surfaces a snackbar instead of throwing',
      (tester) async {
    await pump(tester, onRequest: (_, __) async => throw 'boom');
    await tester.enterText(find.byType(TextField).first, '2024-00123');
    await analyze(tester);
    await tester.ensureVisible(find.byKey(buttonKey));
    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not request parent intervention'),
        findsOneWidget);
  });
}
