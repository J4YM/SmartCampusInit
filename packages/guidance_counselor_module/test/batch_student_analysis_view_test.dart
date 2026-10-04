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
      // Like the real dashboard, the page scrolls — the view itself is a plain
      // column that is taller than a short window.
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BatchStudentAnalysisView()),
        ),
      ),
    );

    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('Critical Risk'), findsOneWidget);
    expect(find.text('High Risk'), findsOneWidget);
    expect(find.text('Average Risk'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('0.0%'), findsOneWidget);

    final analyzeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Analyze All Students'),
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
          body: SingleChildScrollView(
            child: BatchStudentAnalysisView(onPickDataset: () async => records),
          ),
        ),
      ),
    );

    // The metric cards row above the dataset preview pushes these buttons
    // below the default test viewport — scroll them into view before
    // tapping, matching real (scrollable-page) usage.
    await tester.ensureVisible(find.byTooltip('Upload Files'));
    await tester.tap(find.byTooltip('Upload Files'));
    await tester.pumpAndSettle();

    final analyzeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Analyze All Students'),
    );
    expect(analyzeButton.onPressed, isNotNull);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Analyze All Students'));
    await tester.tap(find.widgetWithText(FilledButton, 'Analyze All Students'));
    await tester.pumpAndSettle();

    // Appears in both the dataset preview row and the analysis result row.
    expect(find.text('02000123456'), findsNWidgets(2));
    expect(find.text('1'), findsWidgets); // "Total Students" metric.
  });

  group('live roster', () {
    BatchStudentRecordModel record(String id) => BatchStudentRecordModel(
          studentId: id,
          program: 'BSIT',
          totalClasses: 14,
          totalAbsences: 1,
          maxStreak: 1,
          weeklyAbsences: 0,
          dailyAttendance30D: '1/1',
          absenceTrend: AttendanceTrend.stable,
          recoveryScore: 1,
        );

    testWidgets('previews the live roster on open, without tapping Live Roster',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loads = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BatchStudentAnalysisView(
                onLoadLiveRoster: () async {
                  loads++;
                  return [record('900188'), record('900004')];
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loads, 1);
      expect(find.text('900188'), findsOneWidget);
      expect(find.text('900004'), findsOneWidget);
      // Opening the tab is not an action worth a toast.
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
