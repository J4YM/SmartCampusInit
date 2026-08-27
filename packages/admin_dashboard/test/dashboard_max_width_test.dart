import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:admin_dashboard/pages/main_content_area.dart';
import 'package:admin_dashboard/widgets/sidebar/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Main content pane fills the full viewport on ultra-wide screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();

    // MainContentArea (and, inside it, each routed page's own scroll view)
    // now fills the FULL content pane next to the Sidebar — no width cap
    // out here — so its own scrollbar sits at the pane's true right edge
    // rather than being trapped at the edge of a centered 1440px column.
    // The 1440px cap moved inward onto each routed page's own content
    // (see the second test below).
    final contentWidth = tester.getSize(find.byType(MainContentArea)).width;
    final sidebarWidth = tester.getSize(find.byType(Sidebar)).width;
    expect(contentWidth, 2000 - sidebarWidth);
  });

  testWidgets(
      "A routed page's inner content is capped at 1440px and centered, even though the pane itself is full-width",
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();

    final constrainedBox = find.byWidgetPredicate(
      (w) => w is ConstrainedBox && w.constraints.maxWidth == 1440,
    );
    expect(constrainedBox, findsWidgets);
    expect(tester.getSize(constrainedBox.first).width, 1440);

    // Centered, not flush against the pane's left edge.
    final contentLeft = tester.getTopLeft(find.byType(MainContentArea)).dx;
    final innerLeft = tester.getTopLeft(constrainedBox.first).dx;
    expect(innerLeft, greaterThan(contentLeft + 50));
  });

  testWidgets('Main content fills the viewport below the 1440px breakpoint',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();

    final contentWidth = tester.getSize(find.byType(MainContentArea)).width;
    final sidebarWidth = tester.getSize(find.byType(Sidebar)).width;
    expect(contentWidth, 1200 - sidebarWidth);
  });
}
