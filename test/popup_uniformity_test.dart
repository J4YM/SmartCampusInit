import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:registrar_module/registrar_module.dart';

/// Every popup in the app is an [AppPopup]: one shell, one header, one palette,
/// one footer. This opens a spread of them — from different dashboards — and
/// checks that their chrome is identical.
void main() {
  const student = RegistrarStudentModel(
    id: 's1',
    name: 'Juan Cruz',
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

  final popups = <String, Widget Function(bool dark)>{
    'Report a Technical Issue': (dark) => ReportTechnicalIssueDialog(
          isDarkMode: dark,
          onSubmit: ({required category, required description, location}) async {},
        ),
    'Mailbox message': (dark) => MailboxDetailDialog(
          isDarkMode: dark,
          kicker: 'Notification',
          subject: 'Hello there',
          body: 'A message body.',
          timestamp: DateTime(2026, 10, 4, 14, 5),
        ),
    'Confirm / form dialog': (dark) => BentoFormDialog(
          isDarkMode: dark,
          title: 'Rename',
          content: const Text('Are you sure?'),
          cancelLabel: 'Cancel',
          onCancel: () {},
          confirmLabel: 'Rename',
          onConfirm: () {},
        ),
    'Registrar: Edit Student': (_) =>
        EditStudentDialog(student: student, onSave: (_, __) async {}),
    'Registrar: Add Student': (_) => AddStudentDialog(onSave: (_) async {}),
    'Registrar: Notification Logs': (_) =>
        const RfidNotificationLogsDialog(logs: []),
  };

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester,
    Widget popup, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: popup),
    ));
    await tester.pumpAndSettle();
    // Fixed-size test fonts may overflow a label somewhere; that is not what
    // this test is about.
    tester.takeException();
  }

  Text titleOf(WidgetTester tester) => tester.widget<Text>(find
      .descendant(
          of: find.byType(AppPopupHeader), matching: find.byType(Text))
      .first);

  /// The chrome every popup shares.
  Map<String, Object?> chrome(WidgetTester tester) {
    final popup = find.byType(AppPopup);
    expect(popup, findsOneWidget, reason: 'built from AppPopup');
    final card = tester.widget<BentoCard>(
        find.descendant(of: popup, matching: find.byType(BentoCard)).first);
    final title = titleOf(tester);
    return {
      'card bg': card.backgroundColor,
      'card border': card.borderColor,
      'card radius': card.borderRadius,
      'card padding': card.padding,
      'title size': title.style!.fontSize,
      'title weight': title.style!.fontWeight,
      'title color': title.style!.color,
      'close buttons':
          find.descendant(of: popup, matching: find.byTooltip('Close')).evaluate().length,
    };
  }

  for (final (themeName, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
    testWidgets('every popup shares one shell, header and palette ($themeName)',
        (tester) async {
      size(tester, const Size(1400, 2400));
      Map<String, Object?>? reference;
      String? referenceName;
      for (final entry in popups.entries) {
        await open(tester, entry.value(brightness == Brightness.dark),
            brightness: brightness);
        final c = chrome(tester);
        if (reference == null) {
          reference = c;
          referenceName = entry.key;
          continue;
        }
        for (final key in reference.keys) {
          expect(c[key], reference[key],
              reason: '"${entry.key}" differs from "$referenceName" on "$key"');
        }
      }
    });
  }

  testWidgets('the title steps down to 16 on a phone, for all of them',
      (tester) async {
    size(tester, const Size(390, 2400));
    for (final entry in popups.entries) {
      await open(tester, entry.value(false));
      expect(titleOf(tester).style!.fontSize, 16, reason: entry.key);
    }
  });

  testWidgets('footers: secondary pills sit left of the primary pill',
      (tester) async {
    size(tester, const Size(1400, 2400));
    for (final entry in popups.entries) {
      await open(tester, entry.value(false));
      final popup = find.byType(AppPopup);
      final primary = find.descendant(
          of: popup, matching: find.byType(AppPopupPrimaryButton));
      if (primary.evaluate().isEmpty) continue;
      expect(primary, findsOneWidget, reason: entry.key);
      final secondary = find.descendant(
          of: popup, matching: find.byType(AppPopupSecondaryButton));
      for (final e in secondary.evaluate()) {
        expect(
          tester.getRect(find.byWidget(e.widget)).right,
          lessThanOrEqualTo(tester.getRect(primary).left),
          reason: '${entry.key}: secondary is left of the primary',
        );
      }
    }
  });

  testWidgets("showAppPopup carries the calling page's dark theme into the "
      'dialog', (tester) async {
    size(tester, const Size(1400, 1000));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Theme(
        // A page-level dark theme the root overlay would not otherwise see.
        data: ThemeData(brightness: Brightness.dark),
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppPopup<void>(
                context: context,
                builder: (_) => const AppPopup(title: 'Hi', body: Text('body')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final card = tester.widget<BentoCard>(find
        .descendant(of: find.byType(AppPopup), matching: find.byType(BentoCard))
        .first);
    expect(card.backgroundColor, const Color(0xFF191A1F), reason: 'dark card');
  });

  testWidgets('showAppMessage is a titled message with one OK button',
      (tester) async {
    size(tester, const Size(1400, 1000));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAppMessage(context,
                title: 'Import failed', message: 'Something went wrong.'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Import failed'), findsOneWidget);
    expect(find.text('Something went wrong.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('popup-message-ok')));
    await tester.pumpAndSettle();
    expect(find.byType(AppPopup), findsNothing);
  });
}
