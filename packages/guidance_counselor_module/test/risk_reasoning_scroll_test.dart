import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart';

void main() {
  testWidgets('the Risk Reasoning table scrolls sideways on a phone',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SingleStudentAnalysisView(isMobile: true),
        ),
      ),
    ));
    await tester.ensureVisible(find.text('Analyze Risk'));
    await tester.tap(find.text('Analyze Risk'));
    await tester.pumpAndSettle();
    tester.takeException();

    final header = find.byType(DashboardTableHeader);
    expect(header, findsOneWidget);
    expect(
        find
            .ancestor(
                of: header,
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.right))
            .evaluate(),
        isNotEmpty);
    final columns = tester.widget<DashboardTableHeader>(header).columns;
    expect(tester.getSize(header).width,
        greaterThanOrEqualTo(dashboardTableMinWidth(columns)));
  });
}
