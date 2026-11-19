import 'package:discipline_officer_module/discipline_officer_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('lists sanctions newest first with the override reason',
      (tester) async {
    await tester.pumpWidget(_wrap(SanctionHistoryDialog(
      studentName: 'Juan Dela Cruz',
      items: [
        SanctionHistoryItem(
          id: 'new',
          typeLabel: 'Suspension',
          description: '3-day suspension',
          basisLabel: 'Handbook',
          effectiveOn: DateTime(2026, 11, 18),
          endsOn: DateTime(2026, 11, 20),
          affectsEnrollment: false,
          overrideReason: 'Early decision: repeat offence',
        ),
        SanctionHistoryItem(
          id: 'old',
          typeLabel: 'Warning',
          description: 'Verbal warning',
          basisLabel: 'Custom',
          effectiveOn: DateTime(2026, 10, 1),
          endsOn: null,
          affectsEnrollment: false,
        ),
      ],
    )));

    expect(find.textContaining('Juan Dela Cruz'), findsOneWidget);
    expect(find.textContaining('Early decision: repeat offence'), findsOneWidget);
    final suspensionY = tester.getTopLeft(find.text('Suspension')).dy;
    final warningY = tester.getTopLeft(find.text('Warning')).dy;
    expect(suspensionY, lessThan(warningY), reason: 'newest sanction first');
    expect(find.textContaining('Open-ended'), findsOneWidget);
  });

  testWidgets('says so when the student has no sanctions', (tester) async {
    await tester.pumpWidget(_wrap(const SanctionHistoryDialog(
      studentName: 'Juan Dela Cruz',
      items: [],
    )));
    expect(find.text('No sanctions on record.'), findsOneWidget);
  });
}
