import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

Future<void> _pump(
    WidgetTester tester, Future<void> Function(NewStudentForm) onSave) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AddStudentDialog(onSave: onSave)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, Key dropdown, String option) async {
  await tester.tap(find.byKey(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

bool _saveEnabled(WidgetTester tester) => tester
        .widget<AppPopupPrimaryButton>(find.byKey(const Key('add-student-save')))
        .onPressed !=
    null;

void main() {
  testWidgets('there is no Section field: it is assigned automatically',
      (tester) async {
    await _pump(tester, (_) async {});
    expect(find.byKey(const Key('add-section')), findsNothing);
    expect(find.text('Section'), findsNothing);
  });

  testWidgets('a student can be added with just course and year level',
      (tester) async {
    NewStudentForm? saved;
    await _pump(tester, (f) async => saved = f);
    expect(_saveEnabled(tester), isFalse);

    await tester.enterText(find.byKey(const Key('add-student-number')), '02000999');
    await tester.enterText(find.byKey(const Key('add-first-name')), 'Jane');
    await tester.enterText(find.byKey(const Key('add-last-name')), 'Doe');
    await _pick(tester, const Key('add-course'), 'BS Information Technology');
    await _pick(tester, const Key('add-year-level'), '1st Year');
    await tester.pump();

    expect(_saveEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('add-student-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.course, 'BS Information Technology');
    expect(saved!.yearLevel, '1st Year');
    expect(saved!.studentNumber, '02000999');
  });
}
