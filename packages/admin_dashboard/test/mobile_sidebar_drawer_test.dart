import 'package:admin_dashboard/admin_dashboard.dart';
import 'package:admin_dashboard/pages/main_content_area.dart';
import 'package:admin_dashboard/widgets/sidebar/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// On mobile the sidebar previously stayed inline in the body `Row` at all
/// times (just switching between its full 260px and collapsed 80px widths),
/// permanently eating into the content pane's width. It's now a standard
/// `Scaffold.drawer` on mobile instead — zero layout space until opened —
/// and unchanged inline behavior on desktop/tablet.
///
/// Uses `tester.view.physicalSize`/`devicePixelRatio`, not the legacy
/// `tester.binding.setSurfaceSize` — the latter was found (while
/// investigating an unrelated Guidance Counselor Dashboard report) to leave
/// `MediaQuery.of(context).size` stuck at the test binding's 800x600
/// default in this Flutter SDK version even though it does resize the raw
/// RenderObject layout constraints, which is exactly the kind of mismatch
/// that would make an `isMobileWidth` test like this one unreliable.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'on mobile the sidebar is not inline — it takes no space in the '
      'body Row, and the content pane fills the full width', (tester) async {
    await pumpAt(tester, const Size(390, 800));

    expect(tester.takeException(), isNull);
    // Not rendered in the body at all — it only exists inside the Drawer,
    // which is closed (and thus not built) until opened.
    expect(find.byType(Sidebar), findsNothing);

    final contentWidth = tester.getSize(find.byType(MainContentArea)).width;
    expect(contentWidth, 390);
  });

  testWidgets(
      'tapping the hamburger on mobile opens the sidebar as a drawer, '
      'and selecting a route closes it again', (tester) async {
    await pumpAt(tester, const Size(390, 800));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(Drawer), findsOneWidget);

    // Deliberately re-selects Overview (the already-active default route)
    // rather than navigating to a content-heavier page: several routed
    // pages (e.g. Reports & Exports) have their own pre-existing, unrelated
    // RenderFlex overflows at this width — fixed-width table/toolbar Rows
    // that a narrow viewport simply never exercised before this task
    // started testing the admin dashboard below ~800px at all. Not this
    // test's concern; it's only checking that a selection closes the
    // drawer, which doesn't depend on which route was picked.
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // The drawer closed itself after the selection, per the requirement
    // that picking a menu item auto-dismisses it rather than leaving it
    // open over the newly-selected page.
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(Sidebar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tapping the scrim outside the drawer closes it without selecting '
      'anything', (tester) async {
    await pumpAt(tester, const Size(390, 800));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);

    // Tap far to the right of the 260px-wide drawer, on the modal scrim —
    // Scaffold's own drawer machinery treats this as "dismiss".
    await tester.tapAt(const Offset(380, 400));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'on desktop/tablet the sidebar stays inline in the body Row, '
      'unchanged from before', (tester) async {
    await pumpAt(tester, const Size(1400, 900));

    expect(tester.takeException(), isNull);
    expect(find.byType(Sidebar), findsOneWidget);

    final contentWidth = tester.getSize(find.byType(MainContentArea)).width;
    final sidebarWidth = tester.getSize(find.byType(Sidebar)).width;
    expect(contentWidth, 1400 - sidebarWidth);

    // The hamburger still does the old collapse-to-rail toggle here, not
    // open a drawer (there's nothing to open — `drawer` is null on
    // desktop/tablet).
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Sidebar)).width, lessThan(sidebarWidth));
    expect(tester.takeException(), isNull);
  });
}
