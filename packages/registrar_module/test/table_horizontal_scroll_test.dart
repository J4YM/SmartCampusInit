import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/pages/dashboard/registrar_dashboard_page.dart';

/// A table that no longer fits its card must scroll sideways — header and rows
/// together, columns kept at a readable width — instead of crumpling its text;
/// where it does fit, nothing changes.
void main() {
  sectionScheduleTests();

  const columns = <DashboardTableColumn>[
    DashboardTableColumn('Name', flex: 2),
    DashboardTableColumn('Section', flex: 2),
    DashboardTableColumn('Status', flex: 1, compact: true),
  ];

  Widget table(double cardWidth) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: cardWidth,
              child: SingleChildScrollView(
                child: DashboardTableSection(
                  columns: columns,
                  body: Column(
                    children: [
                      for (var i = 0; i < 3; i++)
                        DashboardTableRow(
                          columns: columns,
                          cells: [
                            Text('Student number $i'),
                            const Text('BS Information Technology'),
                            const Text('Active'),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Finder horizontalScroll() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right);

  test('a table needs room for its padding, columns and gaps', () {
    // 20+20 padding, 8+8 gaps, columns of 88 (2 flex), 88, 84 (the floor).
    expect(dashboardTableMinWidth(columns), 40 + 16 + 88 + 88 + 84);
    // A fixed-width column counts at its own width; a leading checkbox adds.
    expect(
        dashboardTableMinWidth(
            const [DashboardTableColumn('#', width: 32), DashboardTableColumn('A')],
            leadingWidth: 36),
        40 + 36 + 8 + 32 + 84);
  });

  testWidgets('wide enough: no scrolling, columns share the width as before',
      (tester) async {
    await tester.pumpWidget(table(700));
    await tester.pumpAndSettle();
    expect(horizontalScroll(), findsNothing);
    expect(tester.getSize(find.byType(DashboardTableHeader)).width, 700);
  });

  testWidgets('too narrow: scrolls sideways and keeps the columns readable',
      (tester) async {
    await tester.pumpWidget(table(300));
    await tester.pumpAndSettle();

    expect(horizontalScroll(), findsOneWidget);
    final minWidth = dashboardTableMinWidth(columns);
    // Header and every row are laid out at the full table width — wider than
    // the card — and line up with each other.
    expect(tester.getSize(find.byType(DashboardTableHeader)).width, minWidth);
    for (final row in tester.widgetList(find.byType(DashboardTableRow))) {
      expect(tester.getSize(find.byWidget(row)).width, minWidth);
    }
    expect(minWidth, greaterThan(300));
    expect(tester.takeException(), isNull);

    // The part that was off-screen can be reached by dragging.
    final headerLeft = tester.getTopLeft(find.byType(DashboardTableHeader)).dx;
    await tester.drag(horizontalScroll(), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(DashboardTableHeader)).dx,
        lessThan(headerLeft));
  });

  testWidgets('it switches over exactly at the minimum width', (tester) async {
    final minWidth = dashboardTableMinWidth(columns);
    await tester.pumpWidget(table(minWidth));
    await tester.pumpAndSettle();
    expect(horizontalScroll(), findsNothing);

    await tester.pumpWidget(table(minWidth - 1));
    await tester.pumpAndSettle();
    expect(horizontalScroll(), findsOneWidget);
  });

  group('every Registrar table', () {
    Future<void> openTab(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      tester.takeException(); // see the Grades note below
    }

    /// For each table header on screen: is it inside a sideways scroll view?
    Map<DashboardTableHeader, bool> headers(WidgetTester tester) => {
          for (final e in find.byType(DashboardTableHeader).evaluate())
            e.widget as DashboardTableHeader: find
                .ancestor(
                    of: find.byWidget(e.widget),
                    matching: find.byWidgetPredicate((w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.right))
                .evaluate()
                .isNotEmpty,
        };

    for (final tab in [
      null, // Overview (New Students)
      'Student Records',
      'Grades',
      'Class Schedule',
      'RFID Notify',
    ]) {
      testWidgets('${tab ?? 'Overview'} scrolls sideways on a phone and not '
          'on a wide screen', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Wide: every table fits, so none scrolls.
        tester.view.physicalSize = const Size(1600, 1000);
        await tester.pumpWidget(const MaterialApp(home: RegistrarDashboardPage()));
        await tester.pumpAndSettle();
        if (tab != null) await openTab(tester, tab);
        final wide = headers(tester);
        expect(wide, isNotEmpty);
        expect(wide.values, everyElement(isFalse));

        // Phone: every table is narrower than its columns need, so each one
        // is inside a sideways scroll view, and is laid out at least as wide
        // as its columns need.
        tester.view.physicalSize = const Size(390, 900);
        await tester.pumpWidget(const MaterialApp(
            key: ValueKey('phone'), home: RegistrarDashboardPage()));
        await tester.pumpAndSettle();
        if (tab != null) await openTab(tester, tab);
        final phone = headers(tester);
        expect(phone, isNotEmpty);
        expect(phone.values, everyElement(isTrue),
            reason: '${tab ?? 'Overview'}: not scrolling on a phone');
        for (final header in phone.keys) {
          final width = tester.getSize(find.byWidget(header)).width;
          expect(width, greaterThanOrEqualTo(dashboardTableMinWidth(header.columns)),
              reason: 'crumpled: ${header.columns.map((c) => c.label)}');
        }
      });
    }
  });
}

/// The Generated Class Schedule card (shared by every dashboard that shows a
/// section's schedule) has its own six-column table.
void sectionScheduleTests() {
  testWidgets('the section schedule table scrolls sideways on a phone',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SectionScheduleCard(
            sectionOptions: const [(id: 'a', name: 'BSIT-1A')],
            onSectionSelected: (id) async => const [
              SectionScheduleRowModel(
                classSectionId: '1',
                subjectTitle: 'Mathematics in the Modern World',
                professorName: 'Prof. Example Person',
                day: 'M',
                startTime: '08:00',
                endTime: '09:30',
                room: 'Room 101',
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SectionPickerField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-1A').last);
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
