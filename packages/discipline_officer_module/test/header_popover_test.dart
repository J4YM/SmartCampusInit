import 'package:discipline_officer_module/discipline_officer_module.dart'
    show showHeaderPopover;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header popovers (profile, notifications, …) float over the page; the
/// page behind them must never be dimmed, whichever way they are anchored.
void main() {
  for (final mode in ['default', 'centered', 'aboveBottomNav', 'topRight']) {
    testWidgets('a header popover does not dim the page ($mode)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showHeaderPopover(
                context: ctx,
                centered: mode == 'centered',
                anchorAboveBottomNav: mode == 'aboveBottomNav',
                anchorTopRight: mode == 'topRight',
                contentBuilder: (c, setState) =>
                    const Card(child: Text('popover')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('popover'), findsOneWidget);

      // Every modal barrier on screen is fully transparent...
      final barriers =
          tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).toList();
      expect(barriers, isNotEmpty);
      for (final barrier in barriers) {
        expect(barrier.color == null || barrier.color!.opacity == 0, isTrue,
            reason: 'barrier color is ${barrier.color}');
      }

      // ...and tapping outside still dismisses the popover.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('popover'), findsNothing);
    });
  }
}
