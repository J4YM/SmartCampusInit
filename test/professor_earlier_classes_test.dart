import 'package:capstone_dashboard/data/professor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

void main() {
  test('ProfessorSectionModel round-trips classSectionId', () {
    const model = ProfessorSectionModel(
      id: 's1',
      name: 'BSIT 3A',
      studentCount: 30,
      classSectionId: 'c1',
    );
    final back = ProfessorSectionModel.fromJson(model.toJson());
    expect(back.classSectionId, 'c1');
  });

  group('groupEarlierClasses', () {
    final classes = [
      {'id': 'b', 'subject_title': 'PE', 'professor_name': 'Reyes', 'start_time': '10:00'},
      {'id': 'a', 'subject_title': 'Math', 'professor_name': 'Cruz', 'start_time': '08:00'},
    ];

    test('orders by start time and maps status', () {
      final result = groupEarlierClasses(
        classes: classes,
        records: [
          {'student_id': 's1', 'class_section_id': 'a', 'status': 'Present'},
          {'student_id': 's1', 'class_section_id': 'b', 'status': 'Absent'},
        ],
        studentIds: ['s1'],
      );
      expect(result['s1']!.map((e) => e.subjectName), ['Math', 'PE']);
      expect(result['s1']![0].status, AttendanceStatus.present);
      expect(result['s1']![1].status, AttendanceStatus.absent);
    });

    test('unrecorded class is none, not absent', () {
      final result = groupEarlierClasses(
        classes: classes,
        records: const [],
        studentIds: ['s1'],
      );
      expect(result['s1']!.every((e) => e.status == AttendanceStatus.none),
          isTrue);
    });

    test('same start time is ordered by subject title deterministically', () {
      final tie = [
        {'id': 'x', 'subject_title': 'Zed', 'professor_name': 'P', 'start_time': '08:00'},
        {'id': 'y', 'subject_title': 'Alpha', 'professor_name': 'Q', 'start_time': '08:00'},
      ];
      final result = groupEarlierClasses(
          classes: tie, records: const [], studentIds: ['s1']);
      expect(result['s1']!.map((e) => e.subjectName), ['Alpha', 'Zed']);
    });

    test('no earlier classes yields empty map entries', () {
      final result = groupEarlierClasses(
          classes: const [], records: const [], studentIds: ['s1']);
      expect(result['s1'] ?? const [], isEmpty);
    });
  });

  group('groupEarlierClassesForAttendees', () {
    final classes = [
      {'id': 'a', 'section_id': 'secA', 'subject_title': 'Math', 'professor_name': 'Cruz', 'start_time': '08:00'},
      {'id': 'b', 'section_id': 'secB', 'subject_title': 'PE', 'professor_name': 'Reyes', 'start_time': '09:00'},
      {'id': 'c', 'section_id': 'secC', 'subject_title': 'Art', 'professor_name': 'Lim', 'start_time': '10:00'},
    ];

    test('only classes by home section or active enrollment apply', () {
      final result = groupEarlierClassesForAttendees(
        classes: classes,
        records: const [],
        studentSectionIds: {'s1': 'secA', 's2': 'secZ'},
        activeEnrollmentKeys: {'s1|c', 's2|b'},
      );
      expect(result['s1']!.map((e) => e.subjectName), ['Math', 'Art']);
      expect(result['s2']!.map((e) => e.subjectName), ['PE']);
    });
  });

  testWidgets('TapInPill shows time when tapped, otherwise "No tap yet"',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TapInPill(tapInAt: DateTime(2030, 1, 7, 8, 2)),
          const TapInPill(tapInAt: null),
        ]),
      ),
    ));
    expect(find.text('Tapped in 8:02 AM'), findsOneWidget);
    expect(find.text('No tap yet'), findsOneWidget);
  });

  testWidgets('EarlierClassChips renders one chip per class and Not recorded',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EarlierClassChips(items: [
          EarlierClassStatus(
              subjectName: 'Math',
              professorName: 'Cruz',
              startTime: '08:00',
              status: AttendanceStatus.present),
          EarlierClassStatus(
              subjectName: 'PE',
              professorName: 'Reyes',
              startTime: '10:00',
              status: AttendanceStatus.none),
        ]),
      ),
    ));
    expect(find.textContaining('Math'), findsOneWidget);
    expect(find.textContaining('Present'), findsOneWidget);
    expect(find.textContaining('Not recorded'), findsOneWidget);
  });

  testWidgets('EarlierClassChips renders nothing for an empty list',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EarlierClassChips(items: [])),
    ));
    expect(find.byType(Chip), findsNothing);
    expect(tester.getSize(find.byType(EarlierClassChips)).height, 0);
  });
}
