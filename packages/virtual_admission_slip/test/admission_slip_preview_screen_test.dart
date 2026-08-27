import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_admission_slip/virtual_admission_slip.dart';

void main() {
  Widget buildScreen({
    required VoidCallback onDone,
    required Future<void> Function() onPrint,
  }) {
    return MaterialApp(
      home: AdmissionSlipPreviewScreen(
        data: const AdmissionSlipData(
          studentName: 'Test Student',
          qrUrl: 'https://example.com/slip/test',
        ),
        onDone: onDone,
        onPrint: onPrint,
      ),
    );
  }

  testWidgets(
    'opens directly with Done and Print available, no write-related state',
    (tester) async {
      await tester.pumpWidget(buildScreen(onDone: () {}, onPrint: () async {}));

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
    },
  );

  testWidgets('tapping Done calls onDone immediately without printing',
      (tester) async {
    var doneCalled = false;
    var printCalled = false;

    await tester.pumpWidget(
      buildScreen(
        onDone: () => doneCalled = true,
        onPrint: () async => printCalled = true,
      ),
    );

    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(doneCalled, isTrue);
    expect(printCalled, isFalse);
  });

  testWidgets(
    '"Print" plays the slide-down animation, calls onPrint, shows the '
    'printed message, then auto-returns via onDone',
    (tester) async {
      var printCalled = false;
      var doneCalled = false;

      await tester.pumpWidget(
        buildScreen(
          onDone: () => doneCalled = true,
          onPrint: () async {
            printCalled = true;
          },
        ),
      );

      expect(find.text('Print'), findsOneWidget);
      await tester.tap(find.text('Print'));
      await tester.pump(); // enters "printing"

      expect(find.text('Printed successfully.'), findsNothing);

      // Advance past the slide-down animation duration — onPrint should
      // have already resolved (it's synchronous-ish here), so this single
      // pump covers both the animation and the Future.wait completing.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(printCalled, isTrue);
      expect(find.text('Printed successfully.'), findsOneWidget);
      expect(
        find.text('Kindly get your printed admission slip.'),
        findsOneWidget,
      );
      expect(doneCalled, isFalse);

      // Advance past the auto-return timer.
      await tester.pump(const Duration(seconds: 4));

      expect(doneCalled, isTrue);
    },
  );

  testWidgets(
    'a print failure does not prevent the printed message from showing',
    (tester) async {
      await tester.pumpWidget(
        buildScreen(
          onDone: () {},
          onPrint: () async {
            throw Exception('printer offline');
          },
        ),
      );

      await tester.tap(find.text('Print'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      // The host's onPrint is expected to swallow its own errors (see
      // silentPrintAdmissionSlip's doc comment) — this test's fake onPrint
      // deliberately does not, to prove a bare throwing onPrint doesn't
      // wedge the screen.
      expect(find.text('Printed successfully.'), findsOneWidget);
      expect(find.text('Admission Slip Confirmed'), findsOneWidget);
    },
  );
}
