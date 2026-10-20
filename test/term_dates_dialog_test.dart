import 'package:capstone_dashboard/ui/admin/term_dates_dialog.dart';
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({DateTime start, DateTime end})?> _open(
  WidgetTester tester, {
  DateTime? start,
  DateTime? end,
  required void Function(({DateTime start, DateTime end})?) onResult,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => onResult(
            await showAppPopup<({DateTime start, DateTime end})>(
          context: context,
          builder: (_) => TermDatesDialog(
            termLabel: '2026-2027 · 1st Semester',
            initialStart: start,
            initialEnd: end,
          ),
        )),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return null;
}

bool _saveEnabled(WidgetTester tester) => tester
        .widget<AppPopupPrimaryButton>(find.byKey(const Key('term-dates-save')))
        .onPressed !=
    null;

void main() {
  testWidgets('save is off until both dates are chosen', (tester) async {
    await _open(tester, onResult: (_) {});
    expect(_saveEnabled(tester), isFalse);
    expect(find.text('Choose a date'), findsNWidgets(2));
  });

  testWidgets('existing dates are shown and can be saved unchanged',
      (tester) async {
    ({DateTime start, DateTime end})? result;
    await _open(
      tester,
      start: DateTime(2026, 8, 4),
      end: DateTime(2027, 5, 30),
      onResult: (r) => result = r,
    );
    expect(find.text('Aug 4, 2026'), findsOneWidget);
    expect(find.text('May 30, 2027'), findsOneWidget);
    expect(_saveEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('term-dates-save')));
    await tester.pumpAndSettle();
    expect(result!.start, DateTime(2026, 8, 4));
    expect(result!.end, DateTime(2027, 5, 30));
  });

  testWidgets('an end that is not after the start is flagged and cannot be saved',
      (tester) async {
    await _open(
      tester,
      start: DateTime(2026, 8, 4),
      end: DateTime(2026, 8, 4),
      onResult: (_) {},
    );
    expect(find.text('The end date must be after the start date.'),
        findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
  });

  test('validateTermDates', () {
    expect(validateTermDates(DateTime(2026, 8, 4), DateTime(2027, 5, 30)), isNull);
    expect(validateTermDates(DateTime(2026, 8, 4), DateTime(2026, 8, 4)),
        'The end date must be after the start date.');
    expect(validateTermDates(null, DateTime(2026, 8, 4)), isNotNull);
  });
}
