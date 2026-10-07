import 'package:dashboard_layout/dashboard_layout.dart';
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
      tester.widget<SecondaryPillButton>(find.byKey(buttonKey)).onTap,
      isNull,
    );

    await analyze(tester);
    expect(
      tester.widget<SecondaryPillButton>(find.byKey(buttonKey)).onTap,
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
  Future<(Rect, Rect)> actionRects(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SingleStudentAnalysisView(
            isMobile: width < 600,
            onRequestParentIntervention: (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();

    final request = find.byKey(buttonKey);
    final download = find.ancestor(
      of: find.text('Download Assessment'),
      matching: find.bySubtype<FilledButton>(),
    );
    await tester.ensureVisible(request);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'layout overflow');
    // Both keep their full labels — nothing is shortened.
    expect(find.text('Request Parent Intervention'), findsOneWidget);
    expect(find.text('Download Assessment'), findsOneWidget);
    return (tester.getRect(request), tester.getRect(download));
  }

  testWidgets('on a phone the two buttons stack: Request above Download',
      (tester) async {
    final (r, d) = await actionRects(tester, 390);
    expect(r.bottom, lessThanOrEqualTo(d.top), reason: 'Request is above');
    // Both pushed to the card's right edge.
    expect(r.right, closeTo(d.right, 1));
  });

  testWidgets('on a wide card they share a row: Request LEFT of Download',
      (tester) async {
    final (r, d) = await actionRects(tester, 1400);
    expect(r.right, lessThanOrEqualTo(d.left), reason: 'Request is left');
    expect(r.center.dy, closeTo(d.center.dy, 1), reason: 'same row');
  });
}
