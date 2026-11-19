import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_portal_module/parent_portal_module.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('renders nothing when there are no sanctions', (tester) async {
    await tester.pumpWidget(_wrap(const SanctionHistoryCard(entries: [])));
    expect(find.text('Sanction history'), findsNothing);
  });

  testWidgets('lists each sanction with its dates and enrollment tag',
      (tester) async {
    await tester.pumpWidget(_wrap(SanctionHistoryCard(entries: [
      SanctionHistoryEntry(
        id: 'a',
        typeLabel: 'Suspension',
        description: '3-day suspension',
        effectiveOn: DateTime(2026, 11, 18),
        endsOn: DateTime(2026, 11, 20),
        affectsEnrollment: false,
      ),
      SanctionHistoryEntry(
        id: 'b',
        typeLabel: 'Dismissal',
        description: 'Dismissed from the school',
        effectiveOn: DateTime(2026, 10, 1),
        endsOn: null,
        affectsEnrollment: true,
      ),
    ])));

    expect(find.text('Sanction history'), findsOneWidget);
    expect(find.text('Suspension'), findsOneWidget);
    expect(find.text('3-day suspension'), findsOneWidget);
    expect(find.textContaining('Nov 18, 2026'), findsOneWidget);
    expect(find.textContaining('Nov 20, 2026'), findsOneWidget);
    expect(find.text('Dismissal'), findsOneWidget);
    expect(find.textContaining('Open-ended'), findsOneWidget);
    expect(find.text('Affects enrollment'), findsOneWidget);
  });
}
