import 'package:dashboard_layout/dashboard_layout.dart' show AppPopupPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

RegistrarStudentModel _student(
  String id,
  String name,
  String number, {
  required String program,
  required String section,
  double? gpa,
}) =>
    RegistrarStudentModel(
      id: id,
      name: name,
      studentId: number,
      program: program,
      section: section,
      gpa: gpa,
      status: EnrollmentStatus.active,
    );

void main() {
  final students = [
    _student('1', 'Ana Cruz', '0200001',
        program: 'BS Information Technology', section: 'BSIT 1A'),
    _student('2', 'Ben Reyes', '0200002',
        program: 'BSIT', section: 'BSIT 1B', gpa: 2.5),
    _student('3', 'Cara Lim', '0200003',
        program: 'BS Tourism Management', section: 'BSTM 1A'),
  ];

  Future<void> open(
    WidgetTester tester,
    Future<String> Function(String, double) onSave,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GwaEntryDialog(students: students, onSave: onSave)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every student, shows current GWA, nothing saveable yet',
      (tester) async {
    await open(tester, (_, __) async => 'SY / Term');

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Cara Lim'), findsOneWidget);
    expect(find.textContaining('GWA 2.50'), findsOneWidget);
    expect(find.textContaining('No GWA yet'), findsNWidgets(2));

    final save = tester.widget<AppPopupPrimaryButton>(
        find.byKey(const Key('gwa-save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('search narrows the list; picking + typing saves that student',
      (tester) async {
    String? savedId;
    double? savedGwa;
    await open(tester, (id, gwa) async {
      savedId = id;
      savedGwa = gwa;
      return '2025-2026 / 2nd Term';
    });

    await tester.enterText(find.byType(TextField).first, '0200003');
    await tester.pumpAndSettle();
    expect(find.text('Cara Lim'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsNothing);

    await tester.tap(find.text('Cara Lim'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1.75');
    await tester.tap(find.byKey(const Key('gwa-save')));
    await tester.pumpAndSettle();

    expect(savedId, '3');
    expect(savedGwa, 1.75);
    expect(find.textContaining('2025-2026 / 2nd Term'), findsOneWidget);
  });

  testWidgets('an out-of-range GWA is rejected without calling save',
      (tester) async {
    var calls = 0;
    await open(tester, (_, __) async {
      calls++;
      return 'x';
    });

    await tester.tap(find.text('Ana Cruz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0.5');
    await tester.tap(find.byKey(const Key('gwa-save')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.textContaining('between 1.00 and 5.00'), findsOneWidget);
  });

  testWidgets('the Course filter (acronym or full name) narrows the list, '
      'and the Section filter follows it', (tester) async {
    await open(tester, (_, __) async => 'x');

    await tester.tap(find.text('All courses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BS Information Technology').last);
    await tester.pumpAndSettle();

    // Both IT students — one stored under the acronym, one under the full
    // name — and nobody from Tourism.
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Cara Lim'), findsNothing);

    await tester.tap(find.text('All sections'));
    await tester.pumpAndSettle();
    expect(find.text('BSIT 1A'), findsWidgets);
    expect(find.text('BSTM 1A'), findsNothing);
    await tester.tap(find.text('BSIT 1B').last);
    await tester.pumpAndSettle();

    expect(find.text('Ben Reyes'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsNothing);
  });
}
