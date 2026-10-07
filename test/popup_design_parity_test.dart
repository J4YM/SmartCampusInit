import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';
import 'package:rfid_management_module/rfid_management_module.dart';

/// Registrar's "Edit Student Details" and IT Technician's "Edit Student" are
/// the same popup design: built from the same shared pieces, so every
/// measurable part of their chrome must agree.
void main() {
  const registrarStudent = RegistrarStudentModel(
    id: 's1',
    name: 'Juan D. Cruz',
    studentId: '2024-0001',
    program: 'BS Information Technology',
    section: 'IT-101',
    status: EnrollmentStatus.active,
    firstName: 'Juan',
    middleInitial: 'D',
    lastName: 'Cruz',
    email: 'juan@example.com',
    contactNo: '09170000000',
    parentGuardian: 'Maria Cruz',
    guardianContactNo: '09171234567',
  );

  const itStudent = RfidStudentRow(
    id: 's1',
    rfidNo: 'RFID-001',
    studentNumber: '2024-0001',
    firstName: 'Juan',
    middleInitial: 'D',
    lastName: 'Cruz',
    course: 'BS Information Technology',
    yearLevel: '1st Year',
    section: 'IT-101',
    guardianName: 'Maria Cruz',
    guardianContactNo: '09171234567',
  );

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> openRegistrar(WidgetTester tester, Brightness b) async {
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: b),
      home: Scaffold(
        body: EditStudentDialog(student: registrarStudent, onSave: (_, __) async {}),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  Future<void> openIt(WidgetTester tester, Brightness b) async {
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: b),
      home: Scaffold(
        body: StudentRecordsTab(
          students: const [itStudent],
          isLoading: false,
          isBusy: false,
          currentPage: 1,
          totalPages: 1,
          totalCount: 1,
          onSearchChanged: (_) {},
          onPreviousPage: () {},
          onNextPage: () {},
          onSave: (form, editing) async {},
          onDelete: (s) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Edit student'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit student'));
    await tester.pumpAndSettle();
    tester.takeException();
  }

  /// Every measurable part of a popup's chrome.
  Map<String, Object?> design(WidgetTester tester) {
    final popup = find.byType(AppPopup);
    expect(popup, findsOneWidget);
    final card = tester.widget<BentoCard>(
        find.descendant(of: popup, matching: find.byType(BentoCard)).first);
    final title = tester.widget<Text>(find.descendant(
        of: find.byType(AppPopupHeader), matching: find.byType(Text)).first);
    final section = tester.widget<AppPopupSection>(find.byType(AppPopupSection).first);
    final sectionText = tester.widget<Text>(find.descendant(
        of: find.byType(AppPopupSection).first, matching: find.byType(Text)));
    final sectionIcon = tester.widget<Icon>(find.descendant(
        of: find.byType(AppPopupSection).first, matching: find.byType(Icon)));
    final labelText = tester.widget<Text>(find.descendant(
        of: find.byType(AppPopupFieldLabel).first, matching: find.byType(Text)));
    final field = tester.widget<TextField>(find.descendant(
        of: popup, matching: find.byType(TextField)).first);
    final d = field.decoration!;
    final cancel = find.descendant(of: popup, matching: find.byType(AppPopupSecondaryButton));
    final primary = find.descendant(of: popup, matching: find.byType(AppPopupPrimaryButton));
    final cancelRect = tester.getRect(cancel);
    final primaryRect = tester.getRect(primary);
    final cardRect = tester.getRect(find.descendant(of: popup, matching: find.byType(BentoCard)).first);
    return {
      'card width': cardRect.width,
      'card bg': card.backgroundColor,
      'card border': card.borderColor,
      'card radius': card.borderRadius,
      'title size': title.style!.fontSize,
      'title weight': title.style!.fontWeight,
      'title color': title.style!.color,
      'close buttons': find.byTooltip('Close').evaluate().length,
      'section text size': sectionText.style!.fontSize,
      'section text weight': sectionText.style!.fontWeight,
      'section text color': sectionText.style!.color,
      'section icon size': sectionIcon.size,
      'section icon color': sectionIcon.color,
      'section has icon': section.icon != null,
      'label size': labelText.style!.fontSize,
      'label weight': labelText.style!.fontWeight,
      'label color': labelText.style!.color,
      'field text size': field.style!.fontSize,
      'field text color': field.style!.color,
      'field fill': d.fillColor,
      'field padding': d.contentPadding,
      'field has floating label': d.labelText != null,
      'field height': tester.getSize(find.descendant(of: popup, matching: find.byType(TextField)).first).height,
      'cancel left of primary': cancelRect.right < primaryRect.left,
      'button height': primaryRect.height,
      'cancel height': cancelRect.height,
      'button gap': primaryRect.left - cancelRect.right,
      'primary label': tester.widget<AppPopupPrimaryButton>(primary).label,
    };
  }

  void expectSame(Map<String, Object?> a, Map<String, Object?> b) {
    for (final key in a.keys) {
      expect(b[key], a[key], reason: 'IT and Registrar differ on "$key"');
    }
  }

  for (final (name, width, brightness) in [
    ('wide, light', 1400.0, Brightness.light),
    ('wide, dark', 1400.0, Brightness.dark),
    ('phone, light', 390.0, Brightness.light),
  ]) {
    testWidgets('Edit Student is one design in both dashboards ($name)',
        (tester) async {
      size(tester, Size(width, 2000));
      await openRegistrar(tester, brightness);
      final registrar = design(tester);
      await openIt(tester, brightness);
      final it = design(tester);
      expectSame(registrar, it);
      // And they are the title the user sees in both.
      expect(find.text('Edit Student'), findsOneWidget);
    });
  }
}
