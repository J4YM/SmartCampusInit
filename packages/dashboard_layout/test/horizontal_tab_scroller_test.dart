import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 60,
            child: HorizontalTabScroller(
              child: Row(
                children: [
                  for (var i = 0; i < 6; i++)
                    Container(width: 120, height: 40, color: Colors.blue, margin: const EdgeInsets.all(2)),
                ],
              ),
            ),
          ),
        ),
      );

  double offset(WidgetTester t) =>
      t.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  testWidgets('a tab strip wider than the screen scrolls by touch drag', (t) async {
    await t.pumpWidget(host());
    expect(offset(t), 0);
    await t.drag(find.byType(Scrollable), const Offset(-150, 0));
    await t.pumpAndSettle();
    expect(offset(t), greaterThan(100));
  });

  testWidgets('and by mouse click-drag', (t) async {
    await t.pumpWidget(host());
    final gesture = await t.startGesture(
      t.getCenter(find.byType(Scrollable)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-150, 0));
    await gesture.up();
    await t.pumpAndSettle();
    expect(offset(t), greaterThan(100));
  });

  testWidgets('and by a plain vertical mouse wheel', (t) async {
    await t.pumpWidget(host());
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(
        pointer.hover(t.getCenter(find.byType(Scrollable))));
    await t.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await t.pump();
    expect(offset(t), 120);
  });
}
