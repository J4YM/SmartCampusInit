import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In dark mode every checkbox (and the Issue Escalation Report icon) is the
/// light blue #A9C6FD — the brand blue is too dark to see on dark surfaces.
void main() {
  const lightBlue = Color(0xFFA9C6FD);

  group('withPoppins() dark theme', () {
    testWidgets('selected checkboxes fill with #A9C6FD and tick in dark navy',
        (tester) async {
      final theme = ThemeData(brightness: Brightness.dark).withPoppins();
      expect(theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}),
          lightBlue);
      expect(theme.checkboxTheme.checkColor!.resolve({WidgetState.selected}),
          kDarkCheckboxCheckColor);
    });

    testWidgets('unselected and disabled checkboxes keep the default look',
        (tester) async {
      final theme = ThemeData(brightness: Brightness.dark).withPoppins();
      expect(theme.checkboxTheme.fillColor!.resolve(<WidgetState>{}), isNull);
      expect(
          theme.checkboxTheme.fillColor!
              .resolve({WidgetState.selected, WidgetState.disabled}),
          isNull);
    });

    testWidgets('light themes are unchanged', (tester) async {
      final theme = ThemeData(brightness: Brightness.light).withPoppins();
      expect(theme.checkboxTheme.fillColor, isNull);
      expect(theme.checkboxTheme.checkColor, isNull);
    });
  });

  Future<void> pumpPopupTile(WidgetTester tester, Brightness b) async {
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: b),
      home: Scaffold(
        body: AppPopupCheckboxTile(
            title: 'SMS', value: true, onChanged: (_) {}),
      ),
    ));
  }

  testWidgets('the popup tick-box is #A9C6FD in dark, brand blue in light',
      (tester) async {
    await pumpPopupTile(tester, Brightness.dark);
    var box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.activeColor, lightBlue);
    expect(box.checkColor, kDarkCheckboxCheckColor);

    await pumpPopupTile(tester, Brightness.light);
    box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.activeColor, AppPopupColors.accent);
  });

  testWidgets('the shared picker list: a ticked checkbox row is #A9C6FD in dark',
      (tester) async {
    PickerPalette palette(bool dark) => PickerPalette(
          surface: dark ? const Color(0xFF191A1F) : Colors.white,
          field: dark ? const Color(0xFF0E0E0E) : const Color(0xFFF1F5F9),
          border: Colors.grey,
          text: dark ? Colors.white : Colors.black,
          muted: Colors.grey,
          placeholder: Colors.grey,
          accent: const Color(0xFF345892),
        );
    Future<Color?> iconColor(bool dark, {required bool multi}) async {
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: PickerOptionRow(
            entry: const PickerEntry(id: 'a', title: 'BSIT-3A'),
            palette: palette(dark),
            selected: true,
            multi: multi,
            onTap: () {},
          ),
        ),
      ));
      return tester
          .widget<Icon>(find.byIcon(
              multi ? Icons.check_box_rounded : Icons.radio_button_checked_rounded))
          .color;
    }

    expect(await iconColor(true, multi: true), lightBlue);
    expect(await iconColor(false, multi: true), const Color(0xFF345892));
    // The radio dot (single choice) keeps the palette accent.
    expect(await iconColor(true, multi: false), const Color(0xFF345892));
  });

  group('Issue Escalation Report icon', () {
    final cases = [
      DisciplineCaseModel(
        id: 'a',
        studentName: 'Jane Doe',
        studentNumber: '24-0001',
        programGradeSection: 'BSIT-3A',
        violationType: 'Major – Fighting',
        submittedBy: 'Guard',
        submitterRole: '',
        incidentDateTime: DateTime(2026, 1, 1),
        description: '',
        isEscalated: true,
      ),
    ];

    Future<Color?> iconColor(WidgetTester tester, Brightness b) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: ThemeData(brightness: b),
        home: Scaffold(
          body: ParentalInterventionView(
            reports: const [],
            cases: cases,
            onIssue: (_) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();
      return tester.widget<Icon>(find.byIcon(kIssueEscalationIcon)).color;
    }

    testWidgets('is #A9C6FD in dark mode', (tester) async {
      expect(await iconColor(tester, Brightness.dark), lightBlue);
    });

    testWidgets('is the brand blue in light mode', (tester) async {
      expect(await iconColor(tester, Brightness.light), const Color(0xFF345892));
    });
  });
}
