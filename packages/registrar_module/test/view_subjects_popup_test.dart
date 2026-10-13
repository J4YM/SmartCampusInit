import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/pages/dashboard/class_schedule_view.dart'
    show SubjectOption;
import 'package:registrar_module/pages/dashboard/registrar_dashboard_page.dart'
    show EnrollmentStatus, RegistrarStudentModel;
import 'package:registrar_module/pages/dashboard/student_records_view.dart';
import 'package:registrar_module/pages/dashboard/subject_enrollments_view.dart';

/// A student's subjects are no longer listed under the Student Profile card:
/// the card has a "View Subjects" button, and the list — with "Enroll in
/// Subject" — is in the popup it opens.
void main() {
  const student = RegistrarStudentModel(
    id: 's1',
    name: 'Maria Santos',
    studentId: '2024-0001',
    program: 'BS Information Technology',
    section: 'BSIT - 2A',
    status: EnrollmentStatus.active,
  );

  const regular = StudentEnrollmentModel(
    enrollmentId: 'e1',
    subjectTitle: 'Database Systems',
    sectionName: 'BSIT-2A',
    professorName: 'Prof. Reyes',
    isIrregular: false,
  );
  const irregular = StudentEnrollmentModel(
    enrollmentId: 'e2',
    subjectTitle: 'Web Development',
    sectionName: 'BSIT-1B',
    professorName: 'Prof. Cruz',
    isIrregular: true,
  );

  Future<void> pumpProfile(
    WidgetTester tester, {
    required Future<List<StudentEnrollmentModel>> Function(String) fetch,
    Future<void> Function(String enrollmentId)? onDrop,
    Future<void> Function(String, String)? onEnroll,
    bool withOfferings = true,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentRecordsView(
          students: const [student],
          selectedStudent: student,
          onSelect: (_) {},
          subjectOptions: const [
            SubjectOption(id: 'sub1', code: 'IT101', title: 'Intro to IT'),
          ],
          onFetchEnrollments: fetch,
          onFetchOfferings: withOfferings
              ? (_) async => const [
                    ClassSectionOffering(
                      id: 'cs1',
                      sectionName: 'BSIT-1A',
                      professorName: 'Prof. Lim',
                    ),
                  ]
              : null,
          onEnroll: onEnroll,
          onDrop: onDrop,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the profile card shows a View Subjects button, not the list',
      (tester) async {
    await pumpProfile(
      tester,
      fetch: (_) async => const [regular, irregular],
      onEnroll: (_, __) async {},
    );

    expect(find.text('Maria Santos'), findsWidgets);
    expect(find.text('View Subjects'), findsOneWidget);
    // Nothing of the old inline section remains under the card.
    expect(find.text('Subject Enrollments'), findsNothing);
    expect(find.text('Database Systems'), findsNothing);
    expect(find.text('Enroll in Subject'), findsNothing);
  });

  testWidgets('View Subjects opens the list with Enroll in Subject',
      (tester) async {
    await pumpProfile(
      tester,
      fetch: (_) async => const [regular, irregular],
      onEnroll: (_, __) async {},
    );

    await tester.tap(find.byKey(const Key('view-subjects')));
    await tester.pumpAndSettle();

    expect(find.text('Subjects'), findsOneWidget);
    expect(find.text('Database Systems'), findsOneWidget);
    expect(find.text('BSIT-2A — Prof. Reyes'), findsOneWidget);
    expect(find.text('Web Development'), findsOneWidget);
    expect(find.textContaining('Irregular'), findsOneWidget);
    expect(find.byKey(const Key('enroll-in-subject')), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Database Systems'), findsNothing);
  });

  testWidgets('an empty list says so', (tester) async {
    await pumpProfile(tester, fetch: (_) async => const []);

    await tester.tap(find.byKey(const Key('view-subjects')));
    await tester.pumpAndSettle();

    expect(find.text('No subject enrollments on file yet.'), findsOneWidget);
  });

  testWidgets('Enroll in Subject opens the picker, and the list refreshes '
      'after it closes', (tester) async {
    var fetches = 0;
    await pumpProfile(
      tester,
      fetch: (_) async {
        fetches++;
        return const [regular];
      },
      onEnroll: (_, __) async {},
    );

    await tester.tap(find.byKey(const Key('view-subjects')));
    await tester.pumpAndSettle();
    expect(fetches, 1);

    await tester.tap(find.byKey(const Key('enroll-in-subject')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 2 — pick the subject.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Back on the subjects list, re-read.
    expect(find.text('Database Systems'), findsOneWidget);
    expect(fetches, 2);
  });

  testWidgets('Drop asks first, then removes the subject and re-reads the '
      'list', (tester) async {
    final enrollments = [regular, irregular];
    String? dropped;
    await pumpProfile(
      tester,
      fetch: (_) async => List.of(enrollments),
      onDrop: (id) async {
        dropped = id;
        enrollments.removeWhere((e) => e.enrollmentId == id);
      },
    );

    await tester.tap(find.byKey(const Key('view-subjects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drop-e2')));
    await tester.pumpAndSettle();

    // Nothing is dropped until it is confirmed.
    expect(find.text('Drop this subject?'), findsOneWidget);
    expect(find.textContaining('Maria Santos will be dropped from '
        'Web Development'), findsOneWidget);
    expect(dropped, isNull);

    await tester.tap(find.byKey(const Key('confirm-drop-subject')));
    await tester.pumpAndSettle();

    expect(dropped, 'e2');
    expect(find.text('Web Development'), findsNothing);
    expect(find.text('Database Systems'), findsOneWidget);
  });

  testWidgets('cancelling the drop confirmation keeps the subject',
      (tester) async {
    String? dropped;
    await pumpProfile(
      tester,
      fetch: (_) async => const [regular, irregular],
      onDrop: (id) async => dropped = id,
    );

    await tester.tap(find.byKey(const Key('view-subjects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drop-e1')));
    await tester.pumpAndSettle();
    expect(find.text('Drop this subject?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(dropped, isNull);
    expect(find.text('Drop this subject?'), findsNothing);
    // Still on the subjects list, subject intact.
    expect(find.text('Database Systems'), findsOneWidget);
    expect(find.byKey(const ValueKey('drop-e1')), findsOneWidget);
  });

  testWidgets('without enroll callbacks there is no Enroll in Subject, and '
      'without Drop no drop buttons', (tester) async {
    await pumpProfile(tester, fetch: (_) async => const [regular]);

    await tester.tap(find.byKey(const Key('view-subjects')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('enroll-in-subject')), findsNothing);
    expect(find.byKey(const ValueKey('drop-e1')), findsNothing);
    expect(find.text('Database Systems'), findsOneWidget);
  });
}
