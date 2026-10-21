import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

ActivityLogEntry _e(
  String id,
  String kind, {
  String name = 'Jane Doe',
  String? detail,
}) =>
    ActivityLogEntry(
      id: id,
      at: DateTime(2026, 10, 20, 8, 5),
      kind: kind,
      label: kind == 'tap_in'
          ? 'Tapped in'
          : kind == 'tap_out'
              ? 'Tapped out'
              : 'Class: Late',
      studentName: name,
      studentNumber: '2024-0001',
      section: 'BSIT 3-A',
      detail: detail,
    );

class _Call {
  _Call({this.studentQuery, this.sectionId, this.course, this.from, this.to});
  final String? studentQuery;
  final String? sectionId;
  final String? course;
  final DateTime? from;
  final DateTime? to;
}

Future<List<_Call>> _pump(
  WidgetTester tester, {
  Future<List<ActivityLogEntry>> Function(_Call call)? answer,
}) async {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final calls = <_Call>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AttendanceActivityView(
          sections: const [
            SectionOption(id: 'sec-1', name: 'BSIT 3-A', yearLevel: 3),
            SectionOption(id: 'sec-2', name: 'BSHM 1-B', yearLevel: 1),
          ],
          courses: const ['BS Information Technology', 'BS Hospitality Management'],
          onLoad: ({studentQuery, sectionId, course, from, to}) async {
            final call = _Call(
                studentQuery: studentQuery,
                sectionId: sectionId,
                course: course,
                from: from,
                to: to);
            calls.add(call);
            if (answer != null) return answer(call);
            return [
              _e('t1', 'tap_in', detail: 'Gate 1'),
              _e('c1', 'class_late', detail: 'Data Structures'),
            ];
          },
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('loads the latest activity with no filters and lists it',
      (tester) async {
    final calls = await _pump(tester);
    expect(calls, hasLength(1));
    expect(calls.single.sectionId, isNull);
    expect(calls.single.course, isNull);
    expect(calls.single.studentQuery, isNull);
    expect(calls.single.from, isNull);

    expect(find.text('Activity Log'), findsOneWidget);
    expect(find.text('Tapped in'), findsOneWidget);
    expect(find.text('Class: Late'), findsOneWidget);
    expect(find.text('Gate 1'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('BSIT 3-A'), findsWidgets);
  });

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('activity-filter')));
    await tester.pumpAndSettle();
  }

  testWidgets('choosing a section in the Filter popup reloads filtered to it',
      (tester) async {
    final calls = await _pump(tester);
    await openFilter(tester);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'bshm');
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSHM 1-B').last);
    await tester.pumpAndSettle();
    expect(calls.last.sectionId, 'sec-2');
  });

  testWidgets('choosing a course in the Filter popup reloads filtered to it',
      (tester) async {
    final calls = await _pump(tester);
    await openFilter(tester);
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), 'hospitality');
    await tester.pumpAndSettle();
    // (The program heading of the BSHM section also says this; the Course
    // option is the first one in the list.)
    await tester.tap(find.text('BS Hospitality Management').first);
    await tester.pumpAndSettle();
    expect(calls.last.course, 'BS Hospitality Management');
  });

  testWidgets('searching a student reloads with the text once typing pauses',
      (tester) async {
    final calls = await _pump(tester);
    await tester.enterText(find.byKey(const Key('activity-search')), '  jane ');
    // Not yet: it waits for a pause in typing.
    expect(calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(calls.last.studentQuery, 'jane');
  });

  testWidgets('the Date facet sets a range ending today', (tester) async {
    final calls = await _pump(tester);
    await openFilter(tester);
    await tester.tap(find.text('Last 7 days').last);
    await tester.pumpAndSettle();
    final c = calls.last;
    final today = DateTime.now();
    expect(c.to, DateTime(today.year, today.month, today.day));
    expect(c.from, DateTime(today.year, today.month, today.day - 6));

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    expect(calls.last.from, calls.last.to); // today only
  });

  testWidgets('Clear all in the Filter popup goes back to everything',
      (tester) async {
    final calls = await _pump(tester);
    await openFilter(tester);
    await tester.tap(find.text('Last 30 days').last);
    await tester.pumpAndSettle();
    expect(calls.last.from, isNotNull);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(calls.last.from, isNull);
    expect(calls.last.to, isNull);
    expect(calls.last.sectionId, isNull);
  });

  testWidgets('an empty answer says so', (tester) async {
    await _pump(tester, answer: (_) async => const []);
    expect(find.text('No activity matches these filters'), findsOneWidget);
  });

  testWidgets('a failed load shows the message and can be retried',
      (tester) async {
    var fail = true;
    final calls = await _pump(tester, answer: (_) async {
      if (fail) throw Exception('boom');
      return [_e('t1', 'tap_in')];
    });
    expect(find.textContaining('boom'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('activity-retry')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(find.text('Tapped in'), findsOneWidget);
  });
}
