import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SanctionHistoryItem _item({
  String id = 's1',
  String type = 'Suspension',
  String status = 'Serving',
}) =>
    SanctionHistoryItem(
      id: id,
      typeLabel: type,
      description: 'Three-day suspension',
      basisLabel: 'Handbook',
      effectiveOn: DateTime(2026, 3, 10),
      endsOn: DateTime(2026, 3, 12),
      affectsEnrollment: false,
      status: status,
    );

Future<void> _pump(
  WidgetTester tester,
  List<SanctionHistoryItem> items, {
  Future<void> Function(SanctionHistoryItem, String)? onSetStatus,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SanctionHistoryDialog(
          studentName: 'Juan Dela Cruz',
          items: items,
          onSetStatus: onSetStatus,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an ongoing suspension shows a banner with its dates',
      (tester) async {
    await _pump(tester, [_item()]);
    expect(find.byKey(const Key('ongoing-suspension-banner')), findsOneWidget);
    expect(find.textContaining('Mar 10, 2026'), findsWidgets);
    expect(find.textContaining('Mar 12, 2026'), findsWidgets);
  });

  testWidgets('a completed suspension is not ongoing', (tester) async {
    await _pump(tester, [_item(status: 'Completed')]);
    expect(find.byKey(const Key('ongoing-suspension-banner')), findsNothing);
  });

  testWidgets('a warning never shows the suspension banner', (tester) async {
    await _pump(tester, [_item(type: 'Warning', status: 'Pending')]);
    expect(find.byKey(const Key('ongoing-suspension-banner')), findsNothing);
  });

  testWidgets('marking a sanction completed calls back and updates the status',
      (tester) async {
    final calls = <(String, String)>[];
    await _pump(tester, [_item()],
        onSetStatus: (i, status) async => calls.add((i.id, status)));

    await tester.tap(find.byKey(const Key('sanction-complete-s1')));
    await tester.pumpAndSettle();

    expect(calls, [('s1', 'Completed')]);
    expect(find.byKey(const Key('ongoing-suspension-banner')), findsNothing);
    expect(find.byKey(const Key('sanction-complete-s1')), findsNothing);
  });

  testWidgets('without a handler there are no status buttons', (tester) async {
    await _pump(tester, [_item(status: 'Pending')]);
    expect(find.byKey(const Key('sanction-serving-s1')), findsNothing);
    expect(find.byKey(const Key('sanction-complete-s1')), findsNothing);
  });
}
