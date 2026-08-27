import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

void main() {
  /// Pumps a host screen with a button that opens [AdmissionSlipConfirmDialog]
  /// on tap, taps it, and returns the `Future<bool?>` from [showDialog] so
  /// the caller can drive the dialog further before awaiting its result.
  Future<Future<bool?>> openDialog(
    WidgetTester tester, {
    required List<String> violationLabels,
    required Future<void> Function() onConfirm,
  }) async {
    late Future<bool?> resultFuture;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              resultFuture = showDialog<bool>(
                context: context,
                builder: (_) => AdmissionSlipConfirmDialog(
                  violationLabels: violationLabels,
                  onConfirm: onConfirm,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return resultFuture;
  }

  testWidgets('shows each selected violation label for review',
      (tester) async {
    await openDialog(
      tester,
      violationLabels: const ['Improper uniform', 'Missing ID'],
      onConfirm: () async {},
    );

    expect(find.text('•  Improper uniform'), findsOneWidget);
    expect(find.text('•  Missing ID'), findsOneWidget);
  });

  testWidgets('Cancel closes the dialog without calling onConfirm',
      (tester) async {
    var confirmCalled = false;

    final resultFuture = await openDialog(
      tester,
      violationLabels: const ['Improper uniform'],
      onConfirm: () async => confirmCalled = true,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await resultFuture, isNot(true));
    expect(confirmCalled, isFalse);
  });

  testWidgets(
    'Confirm calls onConfirm and pops true once it resolves',
    (tester) async {
      var confirmCalled = false;

      final resultFuture = await openDialog(
        tester,
        violationLabels: const ['Improper uniform'],
        onConfirm: () async {
          confirmCalled = true;
        },
      );

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(confirmCalled, isTrue);
      expect(await resultFuture, isTrue);
    },
  );

  testWidgets(
    'a failed onConfirm shows an error and keeps the dialog open for retry',
    (tester) async {
      var attempts = 0;

      await openDialog(
        tester,
        violationLabels: const ['Improper uniform'],
        onConfirm: () async {
          attempts++;
          if (attempts == 1) throw Exception('network error');
        },
      );

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('network error'), findsOneWidget);
      // Dialog is still open (didn't pop) — Confirm can be tapped again.
      expect(find.text('Confirm'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
    },
  );
}
