import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';

void main() {
  // Matches only the large risk-status label (fontSize 22 at this test's
  // desktop width) in `_RiskAssessmentBox` — plain `find.text(status)` is
  // ambiguous once every reasoning-factor row also happens to carry the
  // same severity word (e.g. "LOW" appears on 3 fontSize-11 severity
  // badges plus this one).
  Finder riskStatusBadge(String status) => find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == status && widget.style?.fontSize == 22,
      );

  // Wide enough to trigger the two-column desktop layout and fit the whole
  // form without scrolling, matching how this view actually renders.
  //
  // Uses `tester.view.physicalSize` rather than `tester.binding.
  // setSurfaceSize` — the latter does NOT update `MediaQuery.of(context)
  // .size`, so `context.isMobileWidth`-gated font sizing would silently
  // read the test harness's default (mobile-width) MediaQuery instead of
  // this 1400px viewport.
  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleStudentAnalysisView()),
      ),
    );
  }

  testWidgets('Analyze Risk populates the gauge, alert, and reasoning table', (tester) async {
    await pumpView(tester);

    // Before analyzing: neutral "Invalid" state, zeroed metrics, empty
    // states, disabled download button.
    expect(find.text('Invalid'), findsOneWidget);
    expect(riskStatusBadge('LOW'), findsNothing);
    expect(find.text('Risk Probability: 0%'), findsOneWidget);
    expect(find.text('Confidence: 0%'), findsOneWidget);
    expect(find.text('0.0%'), findsNWidgets(3)); // Absence/30-Day/GPA Decline
    expect(find.text('Run an analysis to see contributing factors'), findsOneWidget);
    expect(find.text('Run an analysis to see recommended interventions'), findsOneWidget);
    final downloadButtonBefore = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(downloadButtonBefore.onPressed, isNull);

    await tester.tap(find.text('Analyze Risk'));
    await tester.pumpAndSettle();

    // Every field starts empty/zero, so analyzing the untouched form scores
    // LOW risk — but the reasoning table and interventions still switch
    // from the pre-analysis placeholders to real (zero-valued) content.
    expect(riskStatusBadge('LOW'), findsOneWidget);
    expect(find.text('Declining GPA'), findsOneWidget);
    expect(find.text('Violation Severity (STI Handbook weighted)'), findsOneWidget);
    expect(find.text('Failing Courses'), findsWidgets); // form label + table row
    expect(find.text('Continue routine monitoring'), findsOneWidget);
    expect(find.text('Confidence: 100%'), findsOneWidget);

    final downloadButtonAfter = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(downloadButtonAfter.onPressed, isNotNull);

    // "30-Day Absence Rate" must render on a single line — never wrap.
    final thirtyDayLabel = tester.widget<Text>(find.text('30-Day Absence Rate'));
    expect(thirtyDayLabel.maxLines, 1);
    expect(thirtyDayLabel.softWrap, false);
    expect(tester.takeException(), isNull); // no overflow at this width
  });

  testWidgets('Fields start empty and direct text entry updates a numeric field', (tester) async {
    await pumpView(tester);

    final studentIdColumn = find
        .ancestor(of: find.text('Student ID'), matching: find.byType(Column))
        .first;
    expect(
      tester.widget<TextField>(find.descendant(of: studentIdColumn, matching: find.byType(TextField))).controller?.text,
      isEmpty,
    );

    final fieldColumn = find
        .ancestor(of: find.text('Total Absences (Semester)'), matching: find.byType(Column))
        .first;
    final textField = find.descendant(of: fieldColumn, matching: find.byType(TextField));

    expect(find.descendant(of: fieldColumn, matching: find.text('0')), findsOneWidget);

    await tester.enterText(textField, '42');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.descendant(of: fieldColumn, matching: find.text('42')), findsOneWidget);
  });

  testWidgets('Recovery Score slider starts at zero and updates the live badge', (tester) async {
    await pumpView(tester);

    // Scoped to the Recovery Score field's own Column — the now-empty GPA
    // fields also read "0.00", so an unscoped `find.text('0.00')` is
    // ambiguous.
    final recoveryScoreColumn = find
        .ancestor(of: find.text('Recovery Score'), matching: find.byType(Column))
        .first;
    expect(find.descendant(of: recoveryScoreColumn, matching: find.text('0.00')), findsOneWidget);

    final sliderFinder = find.byType(Slider);
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChanged!(0.75);
    await tester.pump();

    expect(find.descendant(of: recoveryScoreColumn, matching: find.text('0.75')), findsOneWidget);
  });

  testWidgets('Two-column layout renders without overflow at a realistic viewport height',
      (tester) async {
    // Shorter than the form's natural content height, so this specifically
    // exercises the "expand to fill / scroll if taller" column behavior.
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleStudentAnalysisView())),
    );
    await tester.tap(find.text('Analyze Risk'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(riskStatusBadge('LOW'), findsOneWidget);
  });
}
