import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/pages/dashboard/professor_dashboard_page.dart';
import 'package:professor_module/professor_module.dart';

/// Wide enough to trigger the desktop master-detail layout (section list +
/// attendance panel side by side), matching this app's own convention for
/// exercising a dashboard's non-mobile branch in tests.
Future<void> _pumpDesktop(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: ProfessorDashboardPage()));
  await tester.pumpAndSettle();
  // The dashboard opens on My Schedule; these tests exercise Attendance.
  await tester.tap(find.text('Attendance'));
  await tester.pumpAndSettle();
}

/// Status icons inside the matrix's own cells — not the legend above the table,
/// which repeats the same icons.
Finder _cellIcon(IconData icon) => find.descendant(
      of: find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('attendance-cell-')),
      matching: find.byIcon(icon),
    );

int _iconCount(WidgetTester tester, IconData icon) =>
    tester.widgetList(_cellIcon(icon)).length;

void main() {
  // Deliberately excludes phone-narrow widths (<800px counts as "mobile"
  // for isMobileWidth, but AppHeaderNavBar itself already overflows below
  // ~450px on EVERY tab of this page — confirmed pre-existing and
  // unrelated to the attendance matrix: it reproduces identically on the
  // Conduct Report tab, before any of this file's changes. Tracked
  // separately; not something this refactor should paper over here.
  final sizes = <String, Size>{
    'tablet (stacked columns)': const Size(850, 1000),
    'desktop': const Size(1400, 900),
  };

  for (final entry in sizes.entries) {
    testWidgets('Attendance tab renders with no overflow at ${entry.key}',
        (tester) async {
      await tester.binding.setSurfaceSize(entry.value);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ProfessorDashboardPage()));
      await tester.pumpAndSettle();
      // The dashboard opens on My Schedule; these tests exercise Attendance.
      await tester.tap(find.text('Attendance'));
      await tester.pumpAndSettle();

      expect(find.text('Student List'), findsOneWidget);
      expect(find.text('+ Add Attendance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Attendance tab renders the weekly matrix with Student List and '
      "this week's date columns", (tester) async {
    await _pumpDesktop(tester);

    expect(find.text('Student List'), findsOneWidget);

    final weekStart = mondayOf(DateTime.now());
    final today = dateOnly(DateTime.now());
    // Mock data covers every weekday in the 20 days up to today, so at
    // least today's own column (a weekday, since Sat/Sun never get
    // sessions) must be showing whenever this test runs on a weekday.
    if (today.weekday != DateTime.saturday && today.weekday != DateTime.sunday) {
      // Date headers are UPPERCASE like every dashboard table's column labels.
      expect(find.text(formatDayMonthDate(today).toUpperCase()), findsOneWidget);
    }
    expect(find.text(formatWeekRangeLabel(weekStart)), findsOneWidget);

    // Status icons for the mock data's seeded present/absent/late/excused
    // mix are all present somewhere in the matrix.
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'date columns run newest first: the latest date is the very first '
      '(left) column, then the day before it, and so on', (tester) async {
    await _pumpDesktop(tester);

    // Last week is fully covered by the mock data (Monday-Friday), so this
    // holds on any day of the week the suite runs.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
    await tester.pumpAndSettle();

    final lastMonday =
        mondayOf(DateTime.now()).subtract(const Duration(days: 7));
    final xs = <double>[];
    for (var i = 0; i < 5; i++) {
      final date = lastMonday.add(Duration(days: i));
      final header = find.text(formatDayMonthDate(date).toUpperCase());
      expect(header, findsOneWidget);
      xs.add(tester.getTopLeft(header).dx);
    }

    // Monday..Friday left edges must strictly decrease: Friday is first.
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], lessThan(xs[i - 1]),
          reason: 'weekday ${i + 1} should sit left of weekday $i');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('cells are read-only until Edit mode is turned on',
      (tester) async {
    await _pumpDesktop(tester);

    final presentBefore = _iconCount(tester, Icons.check_circle_rounded);
    final absentBefore = _iconCount(tester, Icons.cancel_rounded);

    // Tapping a cell before entering Edit mode must be a no-op.
    await tester.tap(_cellIcon(Icons.check_circle_rounded).first);
    await tester.pumpAndSettle();
    expect(_iconCount(tester, Icons.check_circle_rounded), presentBefore);
    expect(_iconCount(tester, Icons.cancel_rounded), absentBefore);
    expect(find.byType(EarlierClassesPopup), findsNothing);

    // "Edit" toggles edit mode on, swapping in Save Changes/Discard.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Save Changes'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    // Now the same tap cycles present -> absent (see AttendanceStatus.next).
    await tester.tap(_cellIcon(Icons.check_circle_rounded).first);
    await tester.pumpAndSettle();
    expect(_iconCount(tester, Icons.check_circle_rounded), presentBefore - 1);
    expect(_iconCount(tester, Icons.cancel_rounded), absentBefore + 1);
  });

  testWidgets('Discard reverts every change made during the edit session',
      (tester) async {
    await _pumpDesktop(tester);

    final presentBefore = _iconCount(tester, Icons.check_circle_rounded);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(_cellIcon(Icons.check_circle_rounded).first);
    await tester.pumpAndSettle();
    expect(_iconCount(tester, Icons.check_circle_rounded), presentBefore - 1);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(_iconCount(tester, Icons.check_circle_rounded), presentBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"+ Add Attendance" opens a date picker defaulting to today',
      (tester) async {
    await _pumpDesktop(tester);

    await tester.tap(find.text('+ Add Attendance'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Dismiss without picking a date — no column should be added.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week navigation moves to the adjacent week without error',
      (tester) async {
    await _pumpDesktop(tester);

    final thisWeekLabel = formatWeekRangeLabel(mondayOf(DateTime.now()));
    final previousWeekLabel =
        formatWeekRangeLabel(mondayOf(DateTime.now()).subtract(const Duration(days: 7)));
    expect(find.text(thisWeekLabel), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text(previousWeekLabel), findsOneWidget);
    expect(find.text(thisWeekLabel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('formatWeekRangeLabel spans Monday through Saturday, not Sunday', () {
    final monday = DateTime(2026, 9, 7); // known Monday
    expect(formatWeekRangeLabel(monday), 'Sep 7 - 12');
  });

  testWidgets(
      'picking a date via "+ Add Attendance" auto-enables edit mode '
      '(Save/Discard show, and the new column is immediately tappable)',
      (tester) async {
    await _pumpDesktop(tester);

    expect(find.text('Save Changes'), findsNothing);

    await tester.tap(find.text('+ Add Attendance'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Confirm the picker's default date instead of cancelling — today's,
    // or the next selectable day if today is a disabled Sunday (see
    // "Disable Sunday in Date Picker" below).
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Edit mode turned on without a separate tap on "Edit".
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    // A cell can be cycled immediately, with no extra "Edit" click needed.
    // Which status shows up first in the matrix depends on the date this
    // suite happens to run on: an existing present/absent/late/excused mix
    // if today already had a column, or an all-unmarked new column if
    // today didn't (e.g. it rolled forward from a disabled Sunday) — cycle
    // whichever status is actually present and confirm it advances exactly
    // one step (AttendanceStatus.next's order).
    const cycle = [
      (Icons.remove_circle_outline_rounded, Icons.check_circle_rounded),
      (Icons.check_circle_rounded, Icons.cancel_rounded),
      (Icons.cancel_rounded, Icons.watch_later_rounded),
      (Icons.watch_later_rounded, Icons.info_rounded),
      (Icons.info_rounded, Icons.check_circle_rounded),
    ];
    final (tappedIcon, nextIcon) =
        cycle.firstWhere((pair) => _iconCount(tester, pair.$1) > 0);
    final tappedBefore = _iconCount(tester, tappedIcon);
    final nextBefore = _iconCount(tester, nextIcon);

    await tester.tap(_cellIcon(tappedIcon).first);
    await tester.pumpAndSettle();
    expect(_iconCount(tester, tappedIcon), tappedBefore - 1);
    expect(_iconCount(tester, nextIcon), nextBefore + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'date columns stretch to fill the card width instead of staying '
      'pinned to their fixed minimum (which left whitespace on the right)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ProfessorDashboardPage()));
    await tester.pumpAndSettle();
    // The dashboard opens on My Schedule; these tests exercise Attendance.
    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();

    // The mock data only seeds cells up to today, so the *current* week can
    // have as few as one populated column right after a week boundary
    // (e.g. running this on a Monday) — not enough to measure spacing
    // between columns. The previous week is always fully populated (every
    // weekday within the last 20 days has data), so step back to it first.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
    await tester.pumpAndSettle();

    final xs = <double>[];
    for (final icon in [
      Icons.check_circle_rounded,
      Icons.cancel_rounded,
      Icons.watch_later_rounded,
      Icons.info_rounded,
      Icons.remove_circle_outline_rounded,
    ]) {
      for (final element in _cellIcon(icon).evaluate()) {
        final box = element.renderObject! as RenderBox;
        xs.add(box.localToGlobal(Offset.zero).dx + box.size.width / 2);
      }
    }
    xs.sort();
    // Every student row repeats the same per-column x position — collapse
    // rows down to one x per column so gaps below measure column-to-column
    // spacing, not row-to-row noise.
    final columnXs = <double>[];
    for (final x in xs) {
      if (columnXs.isEmpty || x - columnXs.last > 1) columnXs.add(x);
    }
    expect(columnXs.length, greaterThan(1),
        reason: 'need at least 2 date columns to measure spacing');

    // _dateColumnWidth in professor_dashboard_page.dart is 112 — a
    // fixed-width layout spaces columns exactly that far apart regardless
    // of viewport. On this 1800-wide desktop viewport there's easily
    // enough room for the (at most 6, Monday-Saturday) columns to flex
    // wider than that instead of leaving the rest of the card empty.
    for (var i = 1; i < columnXs.length; i++) {
      expect(columnXs[i] - columnXs[i - 1], greaterThan(112));
    }
  });

  testWidgets('Sundays are disabled and unclickable in the date picker',
      (tester) async {
    await _pumpDesktop(tester);

    await tester.tap(find.text('+ Add Attendance'));
    await tester.pumpAndSettle();

    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final sunday = mondayOf(DateTime.now()).add(const Duration(days: 6));
    expect(picker.selectableDayPredicate, isNotNull);
    expect(picker.selectableDayPredicate!(sunday), isFalse);
    expect(picker.selectableDayPredicate!(sunday.add(const Duration(days: 1))),
        isTrue); // Monday stays selectable

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "today's number stays readable when today is the selected date "
      '(not the same color as the selected-cell fill)', (tester) async {
    await _pumpDesktop(tester);

    await tester.tap(find.text('+ Add Attendance'));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(DatePickerDialog)))
        .datePickerTheme;
    final selectedFill =
        theme.dayBackgroundColor!.resolve({WidgetState.selected});
    final todaySelected =
        theme.todayForegroundColor!.resolve({WidgetState.selected});
    final todayUnselected = theme.todayForegroundColor!.resolve({});

    expect(todaySelected, isNot(selectedFill));
    expect(todaySelected, Colors.white);
    expect(todayUnselected, isNot(Colors.white));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "a date column's bulk menu can mark every visible student Present",
      (tester) async {
    await _pumpDesktop(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final presentBefore = _iconCount(tester, Icons.check_circle_rounded);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all Present'));
    await tester.pumpAndSettle();

    // Marking a whole column Present can only add check marks, never
    // remove any (other columns are untouched).
    expect(_iconCount(tester, Icons.check_circle_rounded),
        greaterThan(presentBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the matrix uses the shared dashboard table chrome: full-width header '
      'band, UPPERCASE labels, left-aligned cells and a row-wide hover',
      (tester) async {
    await _pumpDesktop(tester);

    // Header band: the table's header fill, spanning the card edge to edge.
    final student = find.text('STUDENT');
    expect(student, findsOneWidget);
    final band = find.ancestor(
      of: student,
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color ==
              DashboardTableColors.headerBackground(
                  tester.element(find.text('STUDENT')))),
    );
    expect(band, findsOneWidget);
    final card = find.ancestor(
        of: band, matching: find.byType(BentoCard)).first;
    final bandRect = tester.getRect(band);
    final cardRect = tester.getRect(card);
    expect(bandRect.left, closeTo(cardRect.left + 1, 2.5));
    expect(bandRect.right, closeTo(cardRect.right - 1, 2.5));

    // Every date header is UPPERCASE and centered over its column, with the
    // status icons beneath it centered in the same column.
    final today = dateOnly(DateTime.now());
    final dateLabel = find.text(formatDayMonthDate(today).toUpperCase());
    if (today.weekday != DateTime.saturday && today.weekday != DateTime.sunday) {
      final labelCenter = tester.getCenter(dateLabel).dx;
      final iconCenters = [
        for (final e in _cellIcon(Icons.check_circle_rounded).evaluate())
          tester.getCenter(find.byWidget(e.widget)).dx,
      ];
      expect(iconCenters.any((x) => (x - labelCenter).abs() < 1), isTrue,
          reason: 'label centered at $labelCenter, icons at $iconCenters');
    }

    // Each icon sits in the middle of its own column cell.
    final cell = find
        .byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('attendance-cell-'))
        .first;
    final cellIcon = find.descendant(of: cell, matching: find.byType(Icon)).first;
    expect(tester.getCenter(cellIcon).dx,
        closeTo(tester.getCenter(cell).dx, 0.5));

    // Hovering a row highlights it across the name column AND the date
    // cells (same fill in both).
    // The first status icon that is part of the matrix (other cards use the
    // same icon).
    final firstIcon = find.descendant(
      of: find.ancestor(of: find.text('STUDENT'), matching: find.byType(BentoCard)).first,
      matching: _cellIcon(Icons.check_circle_rounded),
    ).first;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(firstIcon));
    await tester.pumpAndSettle();

    Color? fillBehind(Finder f) {
      for (final e in find.ancestor(of: f, matching: find.byType(AnimatedContainer)).evaluate()) {
        final deco = (e.widget as AnimatedContainer).decoration;
        if (deco is BoxDecoration && deco.color != null) return deco.color;
      }
      return null;
    }

    final hover = DashboardTableColors.rowHover(tester.element(firstIcon));
    expect(fillBehind(firstIcon), hover);
    final nameOfFirstRow = find.descendant(
      of: find.ancestor(of: find.text('STUDENT'), matching: find.byType(BentoCard)).first,
      matching: find.byWidgetPredicate((w) =>
          // A student's name: the table's 13px primary style (this used to
          // also require maxLines == 1, which names no longer set — they wrap).
          w is Text &&
          w.data != null &&
          w.data!.contains(' ') &&
          w.style?.fontWeight == FontWeight.w600 &&
          w.style?.fontSize == 13),
    ).first;
    expect(fillBehind(nameOfFirstRow), hover);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the Student column grows to fit the longest full name on ONE line, '
      'with nothing clipped or wrapped', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longName = 'Maria Josefina Alexandra Dela Cruz-Villanueva';
    await tester.pumpWidget(const MaterialApp(
      home: ProfessorDashboardPage(
        initialStudentAttendance: [
          StudentAttendanceRecordModel(
            id: 's-long',
            studentName: longName,
            studentId: '02-2223-0001',
            presentCount: 3,
            totalSessions: 4,
            absentCount: 1,
          ),
          StudentAttendanceRecordModel(
            id: 's-short',
            studentName: 'Ana Lim',
            studentId: '02-2223-0002',
            presentCount: 4,
            totalSessions: 4,
            absentCount: 0,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();

    final name = find.text(longName);
    expect(name, findsOneWidget);
    final text = tester.widget<Text>(name);
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);

    // One line: exactly as tall as a short name...
    final shortHeight = tester.getSize(find.text('Ana Lim')).height;
    expect(tester.getSize(name).height, shortHeight);

    // ...and the column was widened to hold it, so the whole name is laid out
    // in full (nothing ellipsized) and fits inside the Student column.
    final studentHeader = find.text('STUDENT');
    final columnCell = find
        .ancestor(of: studentHeader, matching: find.byType(Container))
        .first;
    final columnWidth = tester.getSize(columnCell).width;
    expect(columnWidth, greaterThan(200), reason: 'wider than the old fixed 200');
    final painter = TextPainter(
      text: TextSpan(
        text: longName,
        style: DefaultTextStyle.of(tester.element(name)).style.merge(text.style),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    expect(tester.getSize(name).width, greaterThanOrEqualTo(painter.width - 1));
    expect(tester.getRect(name).right,
        lessThanOrEqualTo(tester.getRect(columnCell).right));

    // Rows keep the normal height, name column and date cells alike.
    double rowHeight(Finder f) => tester
        .getSize(find.ancestor(of: f, matching: find.byType(AnimatedContainer)).first)
        .height;
    expect(rowHeight(name), 65);
    expect(rowHeight(find.text('Ana Lim')), 65);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with only short names the Student column is never narrower than 200px',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: ProfessorDashboardPage(
        initialStudentAttendance: [
          StudentAttendanceRecordModel(
            id: 's-short',
            studentName: 'Ana Lim',
            studentId: '02-2223-0002',
            presentCount: 4,
            totalSessions: 4,
            absentCount: 0,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();

    final columnCell = find
        .ancestor(of: find.text('STUDENT'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(columnCell).width, greaterThanOrEqualTo(200),
        reason: 'never narrower than the 200px minimum');
    expect(tester.takeException(), isNull);
  });

  // The test font is taller than the production one, so a student cell can
  // report a cosmetic RenderFlex overflow (the same allowance
  // test/professor_dashboard_attendance_flow_test.dart makes); only that is
  // ignored, every other framework error still fails the test.
  void ignoreCosmeticOverflow(WidgetTester tester) {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('RenderFlex') && text.contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
  }

  const lim = StudentAttendanceRecordModel(
    id: 'st1',
    studentName: 'Ana Lim',
    studentId: '2024-001',
    presentCount: 0,
    totalSessions: 0,
    absentCount: 0,
  );
  final limWithTaps = StudentAttendanceRecordModel(
    id: 'st1',
    studentName: 'Ana Lim',
    studentId: '2024-001',
    presentCount: 0,
    totalSessions: 0,
    absentCount: 0,
    kioskTapInAt: DateTime(2026, 10, 1, 8, 5),
    kioskTapOutAt: DateTime(2026, 10, 1, 15, 10),
  );
  const otherClass = EarlierClassStatus(
    subjectName: 'Introduction to Human Computer Interaction',
    professorName: 'Reyes',
    startTime: '13:00',
    status: AttendanceStatus.absent,
  );

  Future<void> pumpOneStudent(
    WidgetTester tester,
    StudentAttendanceRecordModel record, {
    bool withOtherClasses = false,
  }) async {
    ignoreCosmeticOverflow(tester);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final monday = dateOnly(mondayOf(DateTime.now()));
    await tester.pumpWidget(MaterialApp(
      home: ProfessorDashboardPage(
        initialSections: const [
          ProfessorSectionModel(
            id: 'sec1',
            name: 'BSIT 3A',
            studentCount: 1,
            subjectId: 'sub-math',
            subjectName: 'Mathematics',
            classSectionId: 'cs-math',
          ),
        ],
        initialStudentAttendance: [record],
        initialAttendanceCells: [
          AttendanceCellModel(studentRecordId: 'st1', date: monday),
        ],
        onFetchEarlierClasses: !withOtherClasses
            ? null
            : (section, date, ids) async => {
                  for (final id in ids) id: const [otherClass],
                },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance').first);
    await tester.pumpAndSettle();
  }

  double studentColumnWidth(WidgetTester tester) => tester
      .getSize(find
          .ancestor(of: find.text('STUDENT'), matching: find.byType(Container))
          .first)
      .width;

  testWidgets(
      'the Student column is never under 200px, and widens for a wide tap '
      'in/out pill without cutting it off', (tester) async {
    await pumpOneStudent(tester, lim);
    expect(studentColumnWidth(tester), greaterThanOrEqualTo(200));

    await pumpOneStudent(tester, limWithTaps);
    final pillText = find.text(
        TapInPill.labelFor(limWithTaps.kioskTapInAt, limWithTaps.kioskTapOutAt));
    expect(pillText, findsOneWidget);
    final column = find
        .ancestor(of: find.text('STUDENT'), matching: find.byType(Container))
        .first;
    final style = DefaultTextStyle.of(tester.element(pillText))
        .style
        .merge(tester.widget<Text>(pillText).style);
    final natural = (TextPainter(
      text: TextSpan(text: tester.widget<Text>(pillText).data, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout())
        .width;
    // Laid out in full (not ellipsized) and inside the Student column.
    expect(tester.getSize(pillText).width, greaterThanOrEqualTo(natural - 0.5));
    expect(tester.getRect(pillText).right,
        lessThanOrEqualTo(tester.getRect(column).right));
  });

  testWidgets(
      "the \"i\" left of a student's name opens a popup listing their other "
      'classes; the row itself no longer shows them, but keeps the tap in/out '
      'pill',
      (tester) async {
    await pumpOneStudent(tester, limWithTaps, withOtherClasses: true);

    // Only the "i" opens the popup: the rest of the row does nothing.
    final info = find.byKey(const ValueKey('student-info-st1'));
    expect(info, findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    // It sits to the LEFT of the student's name, in a column of its own: the
    // 56px info column ends exactly where the STUDENT column (and its header)
    // begins, and the info cell lines up with the name's row.
    final iconX = tester.getCenter(info).dx;
    final nameLeft = tester.getRect(find.text('Ana Lim')).left;
    expect(iconX, lessThan(nameLeft));
    expect(iconX + 28, closeTo(tester.getRect(find.text('STUDENT')).left, 0.5));
    // Horizontally centered between the card's left edge and the name text.
    final cardLeft = tester
        .getRect(find
            .ancestor(of: find.text('STUDENT'), matching: find.byType(BentoCard))
            .first)
        .left;
    expect(iconX - cardLeft, closeTo(nameLeft - iconX, 2.5));
    expect(tester.getCenter(info).dy,
        closeTo(tester.getCenter(find.text('Ana Lim')).dy, 20));
    await tester.tap(find.text('Ana Lim'));
    await tester.pumpAndSettle();
    expect(find.byType(EarlierClassesPopup), findsNothing);

    // Focus a date (edit mode + tapping its cell) so the other classes load.
    final monday = dateOnly(mondayOf(DateTime.now()));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey(
          'attendance-cell-st1-${monday.year}-${monday.month}-${monday.day}')),
      matching: find.byType(InkResponse),
    ));
    await tester.pumpAndSettle();

    final title = EarlierClassRow.titleFor(otherClass);
    // Not in the row; the tap in/out pill still is.
    expect(find.text(title), findsNothing);
    expect(
        find.text(TapInPill.labelFor(
            limWithTaps.kioskTapInAt, limWithTaps.kioskTapOutAt)),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('student-info-st1')));
    await tester.pumpAndSettle();

    final popup = find.byType(EarlierClassesPopup);
    expect(popup, findsOneWidget);
    Finder inPopup(Finder f) => find.descendant(of: popup, matching: f);
    expect(inPopup(find.text('Ana Lim')), findsOneWidget);
    expect(inPopup(find.textContaining('Other classes on')), findsOneWidget);
    expect(inPopup(find.text(title)), findsOneWidget);
    expect(inPopup(find.text('Absent')), findsOneWidget);
    expect(inPopup(find.text('Reyes')), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
  });

  testWidgets('the other-classes popup explains an empty or undated list',
      (tester) async {
    Future<void> show(DateTime? date, List<EarlierClassStatus> items) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EarlierClassesPopup(
            studentName: 'Ana Lim',
            studentId: '2024-001',
            date: date,
            items: items,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await show(DateTime(2026, 10, 19), const []);
    expect(find.text('No other classes recorded for this day.'), findsOneWidget);

    await show(null, const []);
    expect(find.textContaining('Pick a date column'), findsOneWidget);

    await show(DateTime(2026, 10, 19), const [
      EarlierClassStatus(
        subjectName: 'Network Technology',
        professorName: 'Cruz',
        startTime: '07:00',
        status: AttendanceStatus.none,
      ),
    ]);
    expect(find.text('7:00 AM Network Technology'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
  });
}
