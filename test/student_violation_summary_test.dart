import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DisciplineCaseModel _c(
  String id, {
  String? category = 'Minor',
  String? status = 'Pending',
  bool classified = true,
  DateTime? at,
  DateTime? expiredAt,
}) =>
    DisciplineCaseModel(
      id: id,
      studentName: 'Jane Doe',
      studentNumber: '2024-0001',
      programGradeSection: 'BSIT 3-A',
      violationType: classified ? 'Offense $id' : 'Awaiting classification',
      offenseCategory: classified ? category : null,
      isClassified: classified,
      submittedBy: 'Prof Cruz',
      submitterRole: '',
      incidentDateTime: at ?? DateTime(2026, 10, 1),
      description: '',
      status: status,
      expiredAt: expiredAt,
    );

void main() {
  group('StudentViolationSummary', () {
    test('counts by severity and status', () {
      final s = StudentViolationSummary.of([
        _c('1', category: 'Minor', status: 'Resolved'),
        _c('2', category: 'Minor', status: 'Pending'),
        _c('3', category: 'Major_B', status: 'Under_Investigation'),
        _c('4', category: 'Major_A', status: 'Investigation_Complete'),
      ]);
      expect(s.total, 4);
      expect(s.minor, 2);
      expect(s.major, 2);
      expect(s.sanctioned, 1);
      expect(s.open, 3);
      expect(s.underInvestigation, 1);
    });

    test('unclassified reports are counted separately, not as minor or major',
        () {
      final s = StudentViolationSummary.of([
        _c('1', classified: false),
        _c('2', category: 'Minor'),
      ]);
      expect(s.awaitingClassification, 1);
      expect(s.minor, 1);
      expect(s.major, 0);
      expect(s.total, 2);
    });

    test('expired open cases are counted; resolved ones are not', () {
      final s = StudentViolationSummary.of([
        _c('1', expiredAt: DateTime(2026, 10, 20)),
        _c('2', status: 'Resolved', expiredAt: DateTime(2026, 10, 20)),
        _c('3'),
      ]);
      expect(s.expired, 1);
    });

    test('the latest violation is the most recent incident', () {
      final s = StudentViolationSummary.of([
        _c('1', at: DateTime(2026, 9, 1)),
        _c('2', at: DateTime(2026, 10, 15)),
        _c('3', at: DateTime(2026, 10, 2)),
      ]);
      expect(s.latestAt, DateTime(2026, 10, 15));
      expect(s.latestViolation, 'Offense 2');
    });

    test('an empty history is all zeros', () {
      final s = StudentViolationSummary.of(const []);
      expect(s.total, 0);
      expect(s.latestAt, isNull);
    });

    test('the one-line summary reads naturally', () {
      expect(
        StudentViolationSummary.of([
          _c('1', category: 'Minor', status: 'Resolved'),
          _c('2', category: 'Major_A'),
        ]).sentence,
        '2 violations: 1 minor, 1 major. 1 still open.',
      );
      expect(
        StudentViolationSummary.of([_c('1', status: 'Resolved')]).sentence,
        '1 violation: 1 minor. All resolved.',
      );
    });
  });

  testWidgets('the student popup opens with the summary', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final group = groupCasesByStudent([
      _c('1', category: 'Minor', status: 'Resolved'),
      _c('2', category: 'Major_B', status: 'Under_Investigation',
          at: DateTime(2026, 10, 15)),
      _c('3', classified: false),
    ]).single;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StudentViolationHistorySheet(group: group)),
    ));
    await tester.pumpAndSettle();

    String tile(String key) => tester
        .widget<Text>(find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first)
        .data!;
    expect(tile('summary-total'), '3');
    expect(tile('summary-open'), '2');
    expect(tile('summary-sanctioned'), '1');
    expect(tile('summary-minor'), '1');
    expect(tile('summary-major'), '1');
    expect(tile('summary-unclassified'), '1');
    expect(find.textContaining('Last violation'), findsOneWidget);
  });

  test('the status label knows the new workflow statuses', () {
    expect(violationStatusLabel(_c('1', status: 'Investigation_Complete')),
        'Investigation Complete');
    expect(violationStatusLabel(_c('2', status: 'Under_Investigation')),
        'Under Investigation');
    expect(violationStatusLabel(_c('3', status: 'Resolved')), 'Resolved');
    expect(violationStatusLabel(_c('4')), 'Pending');
  });
}
