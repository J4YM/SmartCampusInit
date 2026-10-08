import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every dashboard table: a column is never laid out narrower than its minimum
/// (the table scrolls sideways first), columns are kept apart by a gap, and a
/// cell is one line — it never wraps onto a second.
void main() {
  const gap = DashboardTableMetrics.columnGap;

  group('column widths', () {
    const columns = <DashboardTableColumn>[
      DashboardTableColumn('Name', flex: 1, minWidth: 200),
      DashboardTableColumn('Status', flex: 4, minWidth: 100),
    ];

    test('a column is never narrower than its minimum while the table has room',
        () {
      // Proportionally the first column would get only 1/5 of 360 = 72px;
      // it is held at 200 and the other takes the rest.
      final widths = dashboardTableColumnWidths(columns, 200 + 100 + gap + 60);
      expect(widths[0], greaterThanOrEqualTo(200));
      expect(widths[1], greaterThanOrEqualTo(100));
      expect(widths[0] + widths[1] + gap, closeTo(200 + 100 + gap + 60, 0.001));
    });

    test('with plenty of room the columns share it by flex', () {
      final widths = dashboardTableColumnWidths(columns, 1000 + gap);
      expect(widths[0], closeTo(200, 0.001));
      expect(widths[1], closeTo(800, 0.001));
    });

    test('at exactly the table minimum every column sits at its minimum', () {
      final total = dashboardTableMinWidth(columns) -
          DashboardTableMetrics.horizontalPadding * 2;
      final widths = dashboardTableColumnWidths(columns, total);
      expect(widths, [200, 100]);
    });

    test('a fixed-width column keeps its width', () {
      final widths = dashboardTableColumnWidths(const [
        DashboardTableColumn('#', width: 32),
        DashboardTableColumn('Name', minWidth: 150),
      ], 600);
      expect(widths[0], 32);
      expect(widths[1], closeTo(600 - 32 - gap, 0.001));
    });

    test('a header label is a floor for its column', () {
      const label = 'Daily Attendance 30D';
      final min = dashboardTableColumnMinWidth(
          const DashboardTableColumn(label, minWidth: 40));
      expect(min, greaterThanOrEqualTo(label.length * 8));
    });

    test('a column without a minimum still gets the default floor', () {
      expect(dashboardTableColumnMinWidth(const DashboardTableColumn('A')),
          kDashboardTableMinColumnWidth);
    });
  });

  group('rendered rows', () {
    const columns = <DashboardTableColumn>[
      DashboardTableColumn('Student', flex: 2, minWidth: 160),
      DashboardTableColumn('Section', flex: 1, minWidth: 120),
    ];
    const longName = 'Maria Cristina Dela Cruz-Santos Villanueva y Reyes';

    Widget table(double width) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DashboardTableScrollFrame(
                  columns: columns,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DashboardTableHeader(columns: columns),
                      DashboardTableRow(
                        columns: columns,
                        cells: const [Text(longName), Text('BSIT 3A')],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('a long value stays on one line, even at the narrowest',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      for (final w in [
        dashboardTableMinWidth(columns), // as narrow as the table gets
        700.0,
      ]) {
        await tester.pumpWidget(table(w));
        await tester.pumpAndSettle();
        tester.takeException();
        final box = tester.renderObject<RenderParagraph>(find.text(longName));
        expect(box.size.height, lessThan(box.text.style!.fontSize! * 2),
            reason: 'one line at width $w');
      }
    });

    testWidgets('cells in neighbouring columns never overlap', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(table(dashboardTableMinWidth(columns)));
      await tester.pumpAndSettle();
      tester.takeException();
      final name = tester.getRect(find.text(longName));
      final section = tester.getRect(find.text('BSIT 3A'));
      expect(section.left - name.right, greaterThanOrEqualTo(gap - 0.5),
          reason: 'at least the column gap between the two cells');
    });

    testWidgets('narrower than the minimum, the table scrolls sideways',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(table(dashboardTableMinWidth(columns) - 100));
      await tester.pumpAndSettle();
      tester.takeException();
      expect(
          find.byWidgetPredicate((w) =>
              w is Scrollable && w.axisDirection == AxisDirection.right),
          findsOneWidget);
    });
  });
}
