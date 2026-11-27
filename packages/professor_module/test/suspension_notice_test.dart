import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:professor_module/professor_module.dart';

Future<void> _pump(
  WidgetTester tester,
  List<SuspendedStudentNote>? suspended,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: ProfessorDashboardPage(suspendedStudents: suspended),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows nothing when no student is suspended', (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('suspension-notice')), findsNothing);

    await _pump(tester, const []);
    expect(find.byKey(const Key('suspension-notice')), findsNothing);
  });

  testWidgets('names each suspended student, their dates and subject',
      (tester) async {
    await _pump(tester, [
      SuspendedStudentNote(
        studentName: 'Juan Dela Cruz',
        studentNumber: '2024-0001',
        subjects: const ['Data Structures'],
        startsOn: DateTime(2026, 3, 10),
        endsOn: DateTime(2026, 3, 12),
      ),
    ]);

    expect(find.byKey(const Key('suspension-notice')), findsOneWidget);
    expect(find.textContaining('Juan Dela Cruz'), findsOneWidget);
    expect(find.textContaining('Mar 10, 2026'), findsOneWidget);
    expect(find.textContaining('Mar 12, 2026'), findsOneWidget);
    expect(find.textContaining('Data Structures'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a student in several of the professor\'s subjects is one line',
      (tester) async {
    await _pump(tester, [
      SuspendedStudentNote(
        studentName: 'Maria Santos',
        studentNumber: '2024-0002',
        subjects: const ['Networks', 'Databases'],
        startsOn: DateTime(2026, 3, 10),
        endsOn: null,
      ),
    ]);
    expect(find.textContaining('Maria Santos'), findsOneWidget);
    expect(find.textContaining('Networks, Databases'), findsOneWidget);
    expect(find.textContaining('until further notice'), findsOneWidget);
  });

  testWidgets('the notice is still there on the Attendance tab',
      (tester) async {
    await _pump(tester, [
      SuspendedStudentNote(
        studentName: 'Juan Dela Cruz',
        studentNumber: '2024-0001',
        subjects: const ['Data Structures'],
        startsOn: DateTime(2026, 3, 10),
        endsOn: DateTime(2026, 3, 12),
      ),
    ]);
    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suspension-notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
