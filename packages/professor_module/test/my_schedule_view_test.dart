import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

ProfessorScheduleEntryModel _entry(
  String id,
  String subject,
  String day,
  String start,
  String end, {
  String section = 'BSIT-3A',
  String? component = 'Lecture',
  String room = 'Rm 301',
}) =>
    ProfessorScheduleEntryModel(
      id: id,
      subjectTitle: subject,
      sectionName: section,
      component: component,
      day: day,
      startTime: start,
      endTime: end,
      room: room,
    );

// Deliberately out of week order, as the database returns them (alphabetical
// by day code: F, M, S, T, TH, W).
final _entries = [
  _entry('1', 'Capstone Project 2', 'F', '13:00', '16:00', component: null),
  _entry('2', 'Web Systems and Technologies', 'M', '09:00', '10:30'),
  _entry('3', 'Web Systems and Technologies', 'M', '07:30', '09:00',
      component: 'Laboratory', room: 'Lab 2'),
  _entry('4', 'Networking 1', 'TH', '10:30', '12:00', section: 'BSIT-2B'),
];

Future<void> _pump(
  WidgetTester tester, {
  List<ProfessorScheduleEntryModel>? entries,
  Size size = const Size(1400, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: ProfessorDashboardPage(initialSchedule: entries ?? _entries),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('classes are grouped by day in week order, earliest first',
      (tester) async {
    await _pump(tester);

    expect(find.text('4 classes a week · 3 days'), findsOneWidget);
    final monday = tester.getTopLeft(find.byKey(const ValueKey('schedule-band-M'))).dy;
    final thursday =
        tester.getTopLeft(find.byKey(const ValueKey('schedule-band-TH'))).dy;
    final friday = tester.getTopLeft(find.byKey(const ValueKey('schedule-band-F'))).dy;
    expect(monday, lessThan(thursday));
    expect(thursday, lessThan(friday));
    expect(find.text('Monday · 2 classes'), findsOneWidget);
    expect(find.text('Friday · 1 class'), findsOneWidget);

    // The 7:30 lab comes before the 9:00 lecture on Monday.
    final lab = tester.getTopLeft(find.byKey(const ValueKey('schedule-tile-3')));
    final lecture =
        tester.getTopLeft(find.byKey(const ValueKey('schedule-tile-2')));
    expect(lab.dx < lecture.dx || lab.dy < lecture.dy, isTrue);
  });

  testWidgets('a tile shows time, subject, section, component and room',
      (tester) async {
    await _pump(tester);

    final tile = find.byKey(const ValueKey('schedule-tile-3'));
    for (final text in ['7:30 AM - 9:00 AM', 'Laboratory', 'BSIT-3A', 'Lab 2']) {
      expect(
        find.descendant(of: tile, matching: find.textContaining(text)),
        findsWidgets,
        reason: text,
      );
    }
    // A subject with no Lecture/Laboratory split has no component chip.
    final unsplit = find.byKey(const ValueKey('schedule-tile-1'));
    expect(
      find.descendant(of: unsplit, matching: find.text('Lecture')),
      findsNothing,
    );
  });

  testWidgets('the day filter narrows the tab to one day and All restores it',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('schedule-day-TH')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-tile-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-tile-2')), findsNothing);
    expect(find.byKey(const ValueKey('schedule-band-M')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('schedule-day-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-tile-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-tile-4')), findsOneWidget);
  });

  testWidgets('only today gets the Today badge, and none on a Sunday',
      (tester) async {
    await _pump(tester);
    final weekday = DateTime.now().weekday;
    const withClasses = {1, 4, 5}; // Mon, Thu, Fri in the fixture
    expect(
      find.byKey(const ValueKey('schedule-today-badge')),
      withClasses.contains(weekday) ? findsOneWidget : findsNothing,
    );
  });

  for (final size in [
    const Size(1400, 1000),
    const Size(800, 1000),
    const Size(360, 800),
  ]) {
    testWidgets('lays out without overflow at ${size.width.toInt()}px',
        (tester) async {
      await _pump(tester, size: size);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('schedule-tile-2')), findsOneWidget);
    });
  }

  testWidgets('with no classes it says so and shows no filter', (tester) async {
    await _pump(tester, entries: const []);
    expect(find.text('No classes scheduled yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-day-all')), findsNothing);
  });
}
