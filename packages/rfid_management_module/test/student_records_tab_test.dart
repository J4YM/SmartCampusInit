import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:rfid_management_module/ui/shared_form_widgets.dart';

void main() {
  // The tab's content (title row, year-level chips, filter row, fixed-height
  // table area, pagination footer) exceeds the default 800x600 test window's
  // height, producing a RenderFlex overflow unrelated to the behavior under
  // test. `tester.binding.setSurfaceSize` does not propagate into
  // `MediaQuery` on this Flutter version (3.41.9) — setting
  // `tester.view.physicalSize`/`devicePixelRatio` directly (the replacement
  // the Flutter SDK's own doc comment on `setSurfaceSize` recommends) is
  // what actually gives the widget enough height to lay out without
  // overflowing.
  void setLogicalSurfaceSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  RfidStudentRow makeStudent() => const RfidStudentRow(
        id: 's1',
        rfidNo: 'RFID-001',
        studentNumber: '2024-0001',
        firstName: 'Juan',
        middleInitial: 'D',
        lastName: 'Cruz',
        course: 'BS Information Technology',
        yearLevel: '1st Year',
        section: 'IT-101',
        guardianName: 'Maria Cruz',
      );

  Widget buildTab({required List<RfidStudentRow> students, bool isLoading = false, VoidCallback? onDeleteCalled}) {
    return MaterialApp(
      home: Scaffold(
        body: StudentRecordsTab(
          students: students,
          isLoading: isLoading,
          isBusy: false,
          currentPage: 1,
          totalPages: 1,
          totalCount: students.length,
          selectedCourse: 'All Courses',
          selectedYearLevel: 'All Years',
          selectedSection: 'All Sections',
          sectionOptions: const [],
          onSearchChanged: (_) {},
          onCourseChanged: (_) {},
          onYearLevelChanged: (_) {},
          onSectionChanged: (_) {},
          onPreviousPage: () {},
          onNextPage: () {},
          onSave: (form, editing) async {},
          onDelete: (student) async => onDeleteCalled?.call(),
        ),
      ),
    );
  }

  testWidgets('shows skeleton rows while loading with no data yet', (tester) async {
    setLogicalSurfaceSize(tester, const Size(1400, 900));
    await tester.pumpWidget(buildTab(students: const [], isLoading: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No students match these filters.'), findsNothing);
  });

  testWidgets('a full 25-row page stays reachable by scrolling the table vertically', (tester) async {
    // Regression test: the table area is a fixed SizedBox(height: 460), but
    // `_StudentTable` only scrolled horizontally, so a default-sized page of
    // 25 rows (~1200px of DataTable) rendered ~8 visible rows and clipped the
    // rest with no way to reach them.
    setLogicalSurfaceSize(tester, const Size(1400, 900));

    final students = List.generate(
      25,
      (i) => RfidStudentRow(
        id: 's$i',
        rfidNo: 'RFID-${i.toString().padLeft(3, '0')}',
        studentNumber: '2024-${i.toString().padLeft(4, '0')}',
        firstName: 'Student$i',
        middleInitial: '',
        lastName: 'Lastname$i',
        course: 'BS Information Technology',
        yearLevel: '1st Year',
        section: 'IT-101',
        guardianName: 'Guardian $i',
      ),
    );

    await tester.pumpWidget(buildTab(students: students));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Exactly one vertically-scrolling viewport inside the tab — the one this
    // fix added around the existing horizontal one.
    final verticalScrollable = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    expect(verticalScrollable, findsOneWidget);

    final lastRow = find.text('Student24 Lastname24');
    final viewport = tester.getRect(verticalScrollable);

    // A SingleChildScrollView builds all of its children eagerly, so the last
    // row exists in the tree either way — what the bug actually broke is that
    // it laid out below the visible area and could never be brought into it.
    final beforeY = tester.getTopLeft(lastRow).dy;
    expect(beforeY, greaterThan(viewport.bottom));

    await tester.drag(verticalScrollable, const Offset(0, -1200));
    await tester.pumpAndSettle();

    final afterY = tester.getTopLeft(lastRow).dy;
    expect(afterY, lessThan(beforeY));
    expect(afterY, greaterThanOrEqualTo(viewport.top));
    expect(afterY, lessThan(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires tapping the destructive Delete button, not a bare tap', (tester) async {
    setLogicalSurfaceSize(tester, const Size(1400, 900));
    var deleteCalls = 0;
    await tester.pumpWidget(buildTab(students: [makeStudent()], onDeleteCalled: () => deleteCalls++));

    // The Actions column sits at the far right of a horizontally scrollable
    // DataTable, so it can lay out beyond the viewport's right edge even at
    // a generous window width. Scroll it into view before tapping.
    await tester.ensureVisible(find.byTooltip('Delete student'));
    await tester.tap(find.byTooltip('Delete student'));
    await tester.pumpAndSettle();

    // The danger-zone dialog is open but nothing has been deleted yet.
    expect(deleteCalls, 0);
    expect(find.text('Delete Juan D. Cruz?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);

    await tester.ensureVisible(find.byTooltip('Delete student'));
    await tester.tap(find.byTooltip('Delete student'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
  });
}
