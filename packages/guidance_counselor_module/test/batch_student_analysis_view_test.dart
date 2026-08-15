import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidance_counselor_module/pages/batch_student_analysis/batch_student_analysis_view.dart';
import 'package:guidance_counselor_module/pages/single_student_analysis/single_student_analysis_view.dart'
    show AttendanceTrend;

void main() {
  group('parseBatchDatasetCsv', () {
    test('parses header + rows regardless of header casing/spacing', () {
      const csv = 'Student ID,Program,Total Classes,Total Absences,Max Streak,'
          'Weekly Absences,Daily Attendance 30D,Absence Trend,Recovery Score\n'
          '02000123456,BSIT,100,35,8,3,27/30,Increasing,0.20\n';

      final records = parseBatchDatasetCsv(csv);

      expect(records, hasLength(1));
      expect(records.single.studentId, '02000123456');
      expect(records.single.program, 'BSIT');
      expect(records.single.totalClasses, 100);
      expect(records.single.totalAbsences, 35);
      expect(records.single.absencesPercent, closeTo(35.0, 0.01));
      expect(records.single.absenceTrend, AttendanceTrend.increasing);
    });

    test('returns an empty list for a header-only file', () {
      expect(parseBatchDatasetCsv('Student ID,Program\n'), isEmpty);
    });
  });

  testWidgets('Default state shows zeroed summary stats and a disabled Analyze button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BatchStudentAnalysisView())),
    );

    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('Critical Risk'), findsOneWidget);
    expect(find.text('High Risk'), findsOneWidget);
    expect(find.text('Average Risk'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('0.0%'), findsOneWidget);

    final analyzeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Analyze All Student'),
    );
    expect(analyzeButton.onPressed, isNull);

    final downloadButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Download Results'),
    );
    expect(downloadButton.onPressed, isNull);
  });

  testWidgets('Analyze All Student enables and populates results once a dataset is loaded', (
    tester,
  ) async {
    final records = [
      const BatchStudentRecordModel(
        studentId: '02000123456',
        program: 'BSIT',
        totalClasses: 100,
        totalAbsences: 60,
        maxStreak: 9,
        weeklyAbsences: 5,
        dailyAttendance30D: '10/30',
        absenceTrend: AttendanceTrend.increasing,
        recoveryScore: 0.1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchStudentAnalysisView(onPickDataset: () async => records),
        ),
      ),
    );

    // The metric cards row above the dataset preview pushes these buttons
    // below the default test viewport — scroll them into view before
    // tapping, matching real (scrollable-page) usage.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Upload Files'));
    await tester.tap(find.widgetWithText(FilledButton, 'Upload Files'));
    await tester.pumpAndSettle();

    final analyzeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Analyze All Student'),
    );
    expect(analyzeButton.onPressed, isNotNull);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Analyze All Student'));
    await tester.tap(find.widgetWithText(FilledButton, 'Analyze All Student'));
    await tester.pumpAndSettle();

    // Appears in both the dataset preview row and the analysis result row.
    expect(find.text('02000123456'), findsNWidgets(2));
    expect(find.text('1'), findsWidgets); // "Total Students" metric.
  });
}
