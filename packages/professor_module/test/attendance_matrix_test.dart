import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

/// Wide enough to trigger the desktop master-detail layout (section list +
/// attendance panel side by side), matching this app's own convention for
/// exercising a dashboard's non-mobile branch in tests.
Future<void> _pumpDesktop(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: ProfessorDashboardPage()));
  await tester.pumpAndSettle();
}

int _iconCount(WidgetTester tester, IconData icon) =>
    tester.widgetList(find.byIcon(icon)).length;

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
      expect(find.text(formatDayMonthDate(today)), findsOneWidget);
    }
    expect(find.text(formatWeekRangeLabel(weekStart)), findsOneWidget);

    // Status icons for the mock data's seeded present/absent/late/excused
    // mix are all present somewhere in the matrix.
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cells are read-only until Edit mode is turned on',
      (tester) async {
    await _pumpDesktop(tester);

    final presentBefore = _iconCount(tester, Icons.check_circle_rounded);
    final absentBefore = _iconCount(tester, Icons.cancel_rounded);

    // Tapping a cell before entering Edit mode must be a no-op.
    await tester.tap(find.byIcon(Icons.check_circle_rounded).first);
    await tester.pumpAndSettle();
    expect(_iconCount(tester, Icons.check_circle_rounded), presentBefore);
    expect(_iconCount(tester, Icons.cancel_rounded), absentBefore);

    // "Edit" toggles edit mode on, swapping in Save Changes/Discard.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Save Changes'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    // Now the same tap cycles present -> absent (see AttendanceStatus.next).
    await tester.tap(find.byIcon(Icons.check_circle_rounded).first);
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
    await tester.tap(find.byIcon(Icons.check_circle_rounded).first);
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

    await tester.tap(find.byIcon(tappedIcon).first);
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
      for (final element in find.byIcon(icon).evaluate()) {
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
}
